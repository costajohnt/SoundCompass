# SoundCompass — code review and audit

Date: 2026-09-05. Scope: every Swift source, test, plist, the XcodeGen
spec, the CI workflow, and all docs at commit `1b70c35` on `main`.
Method: static reading plus the GitHub Actions history. This audit was
done on Linux, so nothing here was compiled or run on a device; CI on
`main` is green (run #9, 2026-08-01), so the project builds and the 75
unit tests pass on the iOS 26 simulator.

## 1. Bottom line

The codebase is well organised, allocation-conscious, documented, and
tested far above the norm for a project of this size. The blocker is
not code quality. It is that the core sensing problem — getting a
usable left/right cue out of Apple's *synthesized* stereo — has been
validated on exactly one device, and several downstream features are
built on assumptions that turn out to be wrong or unverified.

If the goal is "make it work" for a real SSD user, the order is:

1. Fix the four defects that make a shipped feature silently do the
   wrong thing (front/back sign, Bluetooth passthrough, stale hazard
   label, watch complication).
2. Spend device time on the ILD measurement problem (§3) with the
   diagnostics tracer that already exists, before touching any more UI.
3. Trim or park the features that cannot be validated yet (watch
   complication, Spanish, per-band GCC-PHAT) so the surface area
   matches what is actually working.

Realistic ceiling today: reliable **left / centre / right** with a
latency of roughly half a second. The UI currently shows "+37°", which
overstates the precision the sensor can deliver.

## 2. Findings by severity

Line numbers refer to `main` at `1b70c35`.

### HIGH — a shipped feature does the wrong thing

**H1. Front/back resolver sign is inverted.**
`SoundCompass/Motion/FrontBackResolver.swift:14-20, 215-218`.
The doc comment reasons "a clockwise yaw sweep makes `d` shrink for a
front source, so slope < 0 → front". The physics is right; the sign of
yaw is not. CoreMotion's device frame is right-handed with `z` out of
the screen, so with the phone flat and screen up, **positive yaw is
counter-clockwise** seen from above. A CCW turn moves a front source to
the *right* of the device's forward axis, so `d` grows with yaw:
front ⇒ slope > 0, back ⇒ slope < 0. The code (and the unit tests,
which encode `θ − yaw`) have this backwards. Fix: swap the two branches
at lines 215-218, or negate the yaw delta once in `ingestYaw`, and
update `FrontBackResolverTests.sweep` to use `θ + yaw`. Then verify on a
device: speaker in front, rotate, banner must say "in front".

**H2. CROS passthrough can never engage over Bluetooth.**
`SoundCompass/AudioDirectionDetector.swift:367-371`,
`SoundCompass/Services/PassthroughMixer.swift:109-125`.
The session is `.playAndRecord` with only `.defaultToSpeaker`. Without
`.allowBluetoothA2DP`, iOS never routes `playAndRecord` output to A2DP
headphones, so `hasSafeOutputRoute()` never sees `.bluetoothA2DP` and
AirPods / any BT headset silently fall back to the phone speaker (where
passthrough is, correctly, refused). Only wired headphones currently
work. Fix: add `.allowBluetoothA2DP` (output-only, so the built-in
stereo mic is preserved). Do **not** add `.allowBluetoothHFP` — HFP
switches input to the headset's mono mic and kills direction finding.
Also set `setPreferredIOBufferDuration(0.005)` while passthrough is on;
the default ~23 ms plus A2DP's 100-200 ms is noticeable. The RUNBOOK
still describes an `.allowBluetoothHFP` option that no longer exists in
the code.

**H3. The watch complication cannot read the value the watch app writes.**
`SoundCompassWatchWidgets/SoundCompassComplication.swift:56`,
`SoundCompassWatch/WatchConnectivityBridge.swift:59`.
The bridge writes `UserDefaults.standard` in the watch *app*; the
widget extension reads `UserDefaults.standard` in its *own* container.
They are different files. The comment calling this an "App Group-less"
key is wrong — it needs an App Group and `UserDefaults(suiteName:)` on
both targets. Note App Groups are not available on a free Personal
Team, which conflicts with the README's free-sideloading path. Two more
problems compound it: `reloadAllTimelines()` on every label change will
blow through WidgetKit's daily reload budget in minutes, and the watch
target is not embedded in the iOS app (`project.yml:59-62`), so the
watch app is not installable through the normal path anyway. Decision
needed: either do the App Group + paid account work, or remove the
complication and mark the watch app as "developer preview".

**H4. A stale classifier label re-arms the hazard path.**
`SoundCompass/Services/SoundClassifier.swift:30-38`,
`SoundCompass/AudioDirectionDetector.swift:518-520, 570-574`.
`topRawIdentifier` is only ever *set* (when confidence ≥ 0.5) and only
*cleared* on `reset()`. After one confident "siren", the identifier
stays "siren" indefinitely. The banner decays when magnitude < 0.15,
but `hazard` is recomputed from the stale id every frame, so the next
loud sound of any kind re-fires the hazard banner, haptic, VoiceOver
announcement, history entry and (in background) a notification. Fix:
timestamp results in `SoundClassifier` and expire the label after
~2 s without a fresh confident result, and publish `nil` when the top
result falls below `minConfidence`.

**H5. The hazard identifier list probably does not match SoundAnalysis.**
`SoundCompass/Services/HazardClassifier.swift:17-40`.
Entries such as `smoke_detector_fire_alarm`,
`vehicle_horn_car_horn_honking`, `backing_up_beep` and `reversing_beep`
read like AudioSet display names, not `SNClassifierIdentifier.version1`
identifiers, while several real ones (e.g. the specific siren classes)
are absent. This is checkable on the simulator: add a test that builds
`SNClassifySoundRequest(classifierIdentifier: .version1)` and asserts
every entry in `hazardIdentifiers` is in `request.knownClassifications`.
Whatever fails that test is dead weight; then walk the known list for
the hazard classes that are missing.

**H6. The directional cue is diluted before it is measured.**
`SoundCompass/DSP/DirectionEstimator.swift:106-126`.
This is the "make it work" item. The device trace (iPhone 16 Pro) gave
|ILD| ≈ 0.08 for a hard-side source against 0.01-0.02 ambient wobble —
a 4:1 signal-to-jitter ratio for the *only* cue that works. The ILD is
computed from broadband RMS, which is dominated by low-frequency energy
(room rumble, HVAC, voice fundamentals). Apple's beamformer has almost
no directivity below ~1 kHz at a 15 cm aperture, so those bands
contribute energy with ILD ≈ 0 and drag the ratio toward zero. The
subband estimator already shows this is likely: it computes per-band
ILD but only the broadband value drives the arrow.

Recommended experiment, in order:
1. Add per-band ILD columns to `DSPDiagnostics` (the plumbing exists;
   `SubbandDirectionEstimator` already has the numbers).
2. Record traces for: clap left / right / front / back, speech at 1 m,
   traffic, on at least two device models, and — importantly — with
   the phone **flat** (documented hold) and **upright** (camera facing
   forward). Apple's beams are designed around the camera axis; in the
   flat hold every horizon source sits 90° off that axis, which is a
   plausible reason the measured ILD is so small.
3. Compute the ILD from a 1-8 kHz band-passed copy of each channel
   (one `BiquadBandpass` per channel, already in the codebase) while
   keeping broadband RMS for loudness. Expect the usable ILD to grow by
   several times.
4. Make `ildGain` and `ildDeadZone` per-device calibration outputs
   instead of constants from one phone. `CalibrationView` records and
   plots but never *sets* anything; turning it into "clap on your left,
   then your right" that stores a measured gain is the natural home.

Until this is done, every downstream tuning constant (sensitivity
blends, haptic thresholds, speech hysteresis) is being tuned against a
signal that is mostly noise.

### MEDIUM — likely to bite on a device

**M1. Route-change restart loop risk.**
`AudioDirectionDetector.swift:343-358, 366-425`. `handleRouteChange`
tears down and calls `configureSession()` on `.routeConfigurationChange`.
`configureSession()` itself changes preferred input, data source, polar
pattern and orientation, each of which can post a route-change
notification, which lands on main after `isRunning` is already true. On
some devices this becomes a restart storm (and the classifier is
re-created each time). Guard: compare the new route's input port UID
and channel count with the previous route (`AVAudioSessionRouteChangePreviousRouteKey`)
and only restart when the input actually changed.

**M2. An invalid input format crashes with an uncatchable exception.**
`AudioDirectionDetector.swift:427-455`. If the session gives a 0 Hz /
0-channel format (permission race, Simulator, some CarPlay routes),
`installTap(format:)` and `SNAudioStreamAnalyzer(format:)` raise
ObjC exceptions. Guard `format.sampleRate > 0 && format.channelCount > 0`
and throw a Swift error instead. `ObjCExceptionCatcher` (bridging header
and `.m` file) is wired in but never called — either use it here or
delete it.

**M3. Self-excitation through the microphone.**
`SpeechAnnouncer.swift`, `ContentView.swift:530-555`. Speech callouts
come out of the speaker 10 cm from the mics: the classifier labels them
"speech", which changes the label, which permits another announcement
after 2 s. Haptic transients are picked up as low-band thumps and can
keep magnitude above the 0.35 haptic threshold. Gate DSP/classifier
input while `AVSpeechSynthesizer` is speaking (delegate `didStart` /
`didFinish`) and for ~60 ms after a haptic; the 1-8 kHz ILD band from
H6 also removes most haptic pickup.

**M4. The front/back answer un-latches as soon as the user stops turning.**
`FrontBackResolver.swift:193-196`. The regression window is 60
*direction* samples (~2.6 s at the ~23 Hz DSP rate, not the 1.2 s the
comment assumes from 50 Hz motion updates). Once rotation stops, the
window's yaw range drops under 15° within a few seconds and the banner
reverts to "keep rotating". Latch a `front`/`back` result for e.g. 10 s
or until the direction estimate itself changes materially.

**M5. Localization is mostly inert.**
Only string *literals* inside `Text("…")` are looked up. 23 call sites
pass a `String` variable (`Text(title)`, `Text(option.label)`,
`Text(result.band.name)`), which is the non-localizing initializer, and
`DirectionLabel` returns raw English that is then spoken by whatever
voice the user picked. `es.lproj` covers 60 keys; the Settings sheet's
newer sections, Help, History and Calibration have none. Either route
user-visible strings through `String(localized:)` or drop the "full
Spanish translation" claim from the changelog.

**M6. watchOS code is never compiled in CI.**
`.github/workflows/soundcompass.yml` builds only `SoundCompass-iOS`.
Add a job that builds the `SoundCompass` scheme for
`generic/platform=watchOS Simulator` with signing disabled, or the
watch/complication code will rot unnoticed. Also pin the Xcode version
(`DEVELOPER_DIR` or `maxim-lobanov/setup-xcode`) — the workflow
currently relies on whatever `macos-15` ships. The separate "Build iOS
app" step is redundant with `xcodebuild test`.

**M7. Notification priority is silently downgraded.**
`HazardNotifier.swift:58-59`. `.timeSensitive` requires the
Time-Sensitive Notifications entitlement; `.defaultCritical` requires
Apple-approved Critical Alerts. The project has no entitlements file, so
both fall back to a normal notification. Add an entitlements file with
`com.apple.developer.usernotifications.time-sensitive` and use
`.default` sound.

**M8. Settings copy promises behaviour that does not exist.**
`SettingsSheet.swift:43, 59`. "Which ear hears?" claims it picks the
wrist-side haptic on the Watch; the hazard footer claims the watch taps
on hazards. `DirectionUpdate` carries neither ear nor hazard, and the
bridge never looks at either. Either implement (add fields to
`DirectionUpdate`) or reword.

**M9. Calibration recorder disagrees with the live path.**
`CalibrationRecorder.swift:88-100`. It picks the *first* stereo data
source (the detector prefers *back*), so its trace can be mirrored
relative to the live compass, and it reconfigures the shared
`AVAudioSession` while the detector's engine may be running (see M1).
Share one session-configuration function, or have calibration tap the
detector's existing stream.

**M10. Smoothing logic is duplicated with divergent constants.**
`AudioDirectionDetector.process` (lines 508-534) and
`CalibrationProcessor.process` (lines 34-54) each implement the
smoother, with the calibration copy hard-coding blend 0.25 / 0.6 and
ignoring the hazard bypass. Extract a pure `DirectionSmoother` value
type; it also makes the detector's per-frame logic unit-testable, which
today it is not.

**M11. Only the first 2048 frames of each tap buffer are analysed.**
`DirectionEstimator.swift:104`, `SubbandDirectionEstimator.swift:66`.
The clamp that fixed the precondition crash now discards everything
past 2048 frames. Devices routinely deliver 4096+ frame buffers, so
more than half the audio never reaches the direction path (the
classifier still gets all of it). Loop over the buffer in 2048-frame
chunks instead.

**M12. Per-frame work on the tap thread contradicts the stated rule.**
`SubbandDirectionEstimator.estimate` allocates a result array per call
and `AudioDirectionDetector.process` maps it again, plus one dispatch
closure. More importantly, the subband path runs a full GCC-PHAT
(3 × 4096-point FFTs) per band per frame — 15 FFTs per 43 ms — on
narrow-band signals where PHAT is documented as unreliable, and its
ITD share of the result is ≤ 0.35 × confidence anyway. Make the
subband path ILD-only: roughly 3× cheaper and no less accurate.

### LOW — hygiene

- **L1. Documentation drift** (see §4). Enough of it to mislead a new
  contributor within the first ten minutes.
- **L2.** `GCCPHAT.swift:108-112`: comment says `X = R · conj(L)`;
  `vDSP_zvmul` with flag `-1` conjugates the *first* operand, so it is
  `conj(R) · L`. The trailing `-bestLag` makes the net sign correct, so
  this is a comment fix, but it explains the "sign was flipped" history.
- **L3.** `Log` declares nine categories; six are unused.
  `FrontBackResolver.swift:108` swallows the CoreMotion error with a
  "surface to logging" TODO.
- **L4.** `EventHistoryView.exportURL()` writes a temp file on every
  body evaluation; `SessionStats.csv` builds an `ISO8601DateFormatter`
  per row.
- **L5.** `WatchContentView` computes `isStale()` in `body` but nothing
  re-renders after 2 s of silence; the "No signal" text appears only on
  the next message. Use `TimelineView`.
- **L6.** `NSMotionUsageDescription` and the docs' "grant motion
  permission" step: `CMDeviceMotion` does not prompt. Harmless, but the
  onboarding promise is wrong.
- **L7.** `project.yml` hard-codes `DEVELOPMENT_TEAM: 554J63A469`; the
  README tells users to find-replace `com.soundcompass.app`, which does
  not appear anywhere — the actual prefix is `com.costajohnt.soundcompass`.
- **L8.** `INFOPLIST_KEY_UILaunchScreen_Generation` is set alongside an
  explicit `UILaunchScreen` dict; one of them is redundant.
- **L9.** Tests: `EventHistoryStoreTests` and `SessionStatsTests` sleep
  for a combined ~4.6 s (CONTRIBUTING says avoid sleeps — inject a
  clock). `PassthroughMixerTests` and `SpeechAnnouncerTests` are mostly
  `XCTAssertNotNil` / property round-trips. No test exercises the
  estimator at *realistic* ILD (0.03-0.08) or checks that ambient
  wobble (0.015) maps to ≈ 0 — those two tests would encode the device
  measurement that the constants came from.

### Security and privacy

Nothing leaves the device. No network code, no secrets, no analytics.
The DSP trace is opt-in behind the developer toggle, capped at 20 MB
and deleted when the toggle is off. `PrivacyInfo.xcprivacy` is
accurate. The hazard notification puts the label and direction on the
lock screen, which is the intent. No concerns.

## 3. The core question: can this sensor do the job?

What is known (from the repo's own device notes): Apple's stereo pair is
level-encoded; the GCC-PHAT lag sits at 0 because the beamformer
time-aligns the channels; the broadband ILD for a hard-side source is
~0.08.

What that implies: with ~0.015 of ambient ILD jitter, the raw cue
supports about three distinguishable states (left / centre / right)
per frame before smoothing. That is still genuinely useful for an SSD
user — "it came from my deaf side" is the question they most need
answered — but the product should present it that way (coarse sectors,
confidence shading) rather than as signed degrees.

What is untested and could move the ceiling substantially:

| Experiment | Why it matters | Cost |
|---|---|---|
| ILD from a 1-8 kHz band only | Low bands have ~0 directivity and dilute the ratio | 20 lines, then device traces |
| Upright hold vs flat hold | Beams are designed around the camera axis | Trace two holds, compare |
| Two or three device models | `ildGain 12` came from one phone | Borrow phones |
| Onset-gated estimation | Direct sound dominates in the first ~20 ms of a transient; reverb dominates after | Medium |
| Per-device calibration flow | Turns the constants into measurements | `CalibrationView` already records |

Everything else in the app is downstream of these numbers.

## 4. Documentation drift (fix in one pass)

| Where | Says | Actual |
|---|---|---|
| README "License" | TBD | MIT (LICENSE, and README's own feature list) |
| README, RUNBOOK | bundle prefix `com.soundcompass.app` | `com.costajohnt.soundcompass` |
| README | watch target embedded in iOS app | commented out in `project.yml` |
| README "Generating" | `cd SoundCompass && xcodegen generate` | `project.yml` is at the repo root |
| README source tree | 2019-era layout | missing Calibration, Motion, Settings, Intents, most Services, widgets |
| README, DSPPipeline.md | ILD 55 % / ITD up to 45 % blend | ILD + 0.35 · confidence · ITD additive |
| RUNBOOK | repo `costajohnt/sandbox`, `cd sandbox/SoundCompass`, "69 tests", `.allowBluetoothHFP` present | `costajohnt/SoundCompass`, root, 75 tests, no BT option |
| ARCHITECTURE.md, CONTRIBUTING.md | iOS 17+, watchOS 10+, `iPhone 15`, scheme `SoundCompass` | iOS 18+, watchOS 11+, `iPhone 17 Pro`, scheme `SoundCompass-iOS` |
| CHANGELOG | issue templates and PR template added | `.github/` contains only the workflow |
| `SoundCompassComplication.swift:49` | references `SoundCompassComplicationDefaults.swift` | file does not exist |
| HelpSheet | direction comes from the inter-mic time offset | code treats ITD as nearly useless |

## 5. Test coverage assessment

75 tests, all pure and CI-green. Strong: GCC-PHAT sign and noise
tolerance, estimator gating (uncorrelated noise, railed lag), subband
Nyquist fallback, diagnostics file lifecycle, settings persistence.

Gaps that matter, in priority order:

1. `AudioDirectionDetector.process` — the actual per-frame logic
   (smoothing, hazard edge-triggering, history recording, fan-out) has
   zero tests because it is a private method on a class that owns an
   `AVAudioEngine`. Extracting the smoother (M10) fixes this.
2. `HazardClassifier` against `knownClassifications` (H5).
3. Realistic-ILD estimator tests (L9).
4. `FrontBackResolver` sign with a physically derived fixture rather
   than one that shares the implementation's assumption (H1).
5. `SoundClassifier` label expiry (H4).

## 6. Recommended plan

**Phase 0 — correctness, no device needed (about a day):**
H1 sign fix + test; H2 `.allowBluetoothA2DP`; H4 label expiry; H5
`knownClassifications` test and prune; M1 route guard; M2 format guard;
M7 entitlements; M11 chunked processing.

**Phase 1 — measure (device time, the real work):**
Per-band ILD in the trace; flat vs upright; two device models; pick the
ILD band and gain from data (H6). Convert `CalibrationView` into a
calibration that stores `ildGain`.

**Phase 2 — make the good path solid:**
Latch front/back (M4); self-excitation gating (M3); extract
`DirectionSmoother` with tests (M10); subband ILD-only (M12); present
direction as sectors with confidence rather than degrees.

**Phase 3 — scope honesty:**
Decide watch/complication (H3) — App Group + paid account, or remove.
Fix or drop the Spanish claim (M5). Reword the Settings copy (M8).
One documentation pass (§4). Add the watchOS CI job (M6).

## 7. Not verified here

- No build or test run (Linux container, no Xcode). CI on `main` is
  the evidence that the tree compiles and tests pass.
- H1's sign is derived from CoreMotion's documented right-handed frame,
  not observed; confirm on device before shipping the flip.
- H5's identifier mismatches are based on the naming pattern; the
  proposed test is the authoritative check.
- M1 is a risk pattern, not an observed loop; the `Log.lifecycle` lines
  already present will show it if it happens.
