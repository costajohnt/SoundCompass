# SoundCompass

An iOS app (with an Apple Watch companion) that helps people with
**single-sided deafness (SSD)** localize sound. SSD users hear normally in one
ear but little or nothing in the other, which removes the binaural cues the
brain relies on to tell *where* a sound is coming from. SoundCompass uses the
iPhone's built-in multi-microphone array to reconstruct those cues and show
them visually, haptically, and via the Watch on the wrist.

> **Honest expectations.** iOS never exposes raw per-microphone audio; the
> app works from Apple's *synthesized* stereo image, which carries only a
> modest left/right level difference. Expect the compass to tell **left /
> centre / right** reliably, with the exact angle being an estimate. See
> [AUDIT.md](AUDIT.md) §3 for the measurements behind that statement and
> the experiments that could raise the ceiling.

## Features

- **Level-difference direction estimation** — the interaural level
  difference (ILD) between the two channels of Apple's beamformed stereo
  image drives the arrow, expanded through a `tanh` with a per-device gain.
  A GCC-PHAT time-difference estimate is fused in only when its
  correlation peak is sharp, and only as a small correction.
- **Per-device calibration** — Settings → Calibration trace records five
  seconds, plots the direction over time, and can store the recording's
  measured level difference as this phone's full-scale gain.
- **Per-frequency-band breakdown** — a biquad filter bank (low/speech/alert/
  high) runs an ILD estimator per band, so the UI can tell you
  *"speech on your left, traffic on your right"* in the same frame.
- **Motion-assisted front/back disambiguation** — a two-microphone array
  cannot tell front from back on its own. `FrontBackResolver` subscribes to
  `CMDeviceMotion`, fits a regression of direction on yaw, commits to
  *front* or *back* once the user has rotated the phone 15°, and latches
  the answer for ten seconds.
- **Built-in sound classification** — Apple's `SNClassifySoundRequest(.version1)`
  labels the loudest sound ("car horn", "dog bark", "speech"…) without
  shipping a CoreML model. Labels expire after 2.5 s without a fresh
  confident result.
- **Hazard alerts** — sirens, alarms, horns, reversing beeps and similar
  (matched by identifier and keyword against Apple's label set) bypass the
  smoother, raise a red banner, play a strong haptic pattern, tap a paired
  watch, and post a time-sensitive notification when the app is in the
  background.
- **CROS audio passthrough** — with headphones connected (wired, USB-C,
  AirPlay or Bluetooth A2DP), the room audio is panned into the ear the
  user hears with. Never over the built-in speaker.
- **Spoken direction cues** — `AVSpeechSynthesizer` callouts, rate-limited;
  the microphone path is muted while the phone is talking so it does not
  classify its own voice.
- **Haptic ticks** — Core Haptics ticks whose intensity and sharpness scale
  with loudness and off-center-ness. Three-level strength setting.
- **Siri + Shortcuts** — `StartListeningIntent`, `StopListeningIntent`, and
  `AnnounceDirectionIntent`.
- **Lock Screen / Dynamic Island Live Activity** — updated ≤3 Hz.
- **Apple Watch companion** — a SwiftUI mirror of the compass with wrist
  haptics, plus a complication backed by an App Group (see *Watch* below).
- **Reduce Motion + Dynamic Type**, an onboarding walkthrough, an in-app
  Help / FAQ, and English + Spanish strings.
- **Developer diagnostics** — a debug overlay and an opt-in per-frame CSV
  trace (broadband and per-band ILD, lag, confidence) for offline analysis.
- **Unit-tested DSP** — 120 tests with synthetic signals; no device needed.
- **MIT licensed.**

## How the DSP works

iPhone "stereo" capture is **not** two raw microphones. The system records
from all built-in mics simultaneously and synthesizes a beamformed stereo
image (WWDC20 session 10226, "Record stereo audio with AVAudioSession").
Three facts about that image drive the design:

- The **front and back data sources produce mirrored left/right**.
  `AudioSessionConfigurator` prefers the **back** source, whose left/right
  match the user's when the phone is held flat, screen up, top edge
  pointing away. If only the front source supports stereo, the app uses it
  and flips the sign of every estimate.
- The image is **level-encoded**. The inter-channel time difference is a
  by-product of Apple's beamformer and sits at zero for most sources, so
  the level difference (ILD) is the cue that matters.
- The beamformer has almost **no directivity below ~1 kHz**, so
  low-frequency energy dilutes a broadband ILD. An optional developer
  setting measures the ILD in a 1–8 kHz band instead (default off until it
  has been measured on more devices).

`DirectionEstimator` produces one estimate per 2048-frame chunk:

1. Broadband RMS per channel gives loudness; the ILD source (broadband or
   band-limited) gives `(R−L)/(R+L)`, which passes through a 0.01
   dead-zone and `tanh(ildGain · ild)`.
2. `GCCPHAT.estimateLag` runs a split-complex FFT cross-correlation with
   PHAT weighting inside the physically possible window (~21 samples at
   48 kHz for a 15 cm aperture). Its normalized peak height becomes a
   confidence; a peak railed at the window edge is rejected.
3. The result is `ild + 0.35 · confidence · itd`, clamped to `[-1, 1]`.
4. `DirectionSmoother` blends successive estimates with a weight set by the
   sensitivity preset (or 0.9 during a hazard) and decays the arrow toward
   center when no confident estimate arrives.

`SubbandDirectionEstimator` runs ILD-only estimators inside four streaming
biquad bands so the UI can highlight the loudest band.

## Source layout

```
.
├── project.yml                          # XcodeGen project definition
├── AUDIT.md                             # review findings and fix status
├── Shared/                              # compiled into several targets
│   ├── CompassView.swift                # SwiftUI half-dial compass
│   ├── DirectionLabel.swift             # localized direction strings
│   ├── DirectionUpdate.swift            # WCSession payload
│   ├── SharedDefaults.swift             # App Group defaults (watch + complication)
│   └── SoundCompassActivityAttributes.swift
├── SoundCompass/                        # iOS app target
│   ├── SoundCompassApp.swift
│   ├── ContentView.swift
│   ├── AudioDirectionDetector.swift     # AVAudioEngine tap + orchestration
│   ├── DSP/                             # DirectionEstimator, DirectionSmoother,
│   │                                    # GCCPHAT, BiquadBandpass(+Limiter),
│   │                                    # SubbandDirectionEstimator
│   ├── Motion/FrontBackResolver.swift
│   ├── Services/                        # AudioSessionConfigurator, SoundClassifier,
│   │                                    # HazardClassifier, HazardGate, HazardNotifier,
│   │                                    # SpeechAnnouncer, WatchSessionManager,
│   │                                    # LiveActivityController, PassthroughMixer,
│   │                                    # EventHistoryStore, SessionStats,
│   │                                    # DSPDiagnostics, Log
│   ├── Settings/                        # SettingsStore, SettingsSheet
│   ├── Calibration/                     # recorder, processor, view
│   ├── Intents/                         # Siri / Shortcuts
│   ├── Documentation.docc/
│   ├── en.lproj/, es.lproj/
│   ├── SoundCompass.entitlements        # time-sensitive notifications
│   └── PrivacyInfo.xcprivacy
├── SoundCompassWatch/                   # watchOS companion
├── SoundCompassWatchWidgets/            # watchOS complication
├── SoundCompassWidgets/                 # iOS Live Activity
└── SoundCompassTests/                   # XCTest bundle (120 tests)
```

## Generating the Xcode project

The repo ships an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec so
the project file can be regenerated on any machine without checking a fragile
`project.pbxproj` into git. `project.yml` lives at the repository root:

```sh
brew install xcodegen
xcodegen generate
open SoundCompass.xcodeproj
```

`project.yml` declares five targets and three schemes:

| Target                    | Type               | Platform    | Sources                      |
|---------------------------|--------------------|-------------|------------------------------|
| `SoundCompass`            | application        | iOS 18+     | `SoundCompass/`, `Shared/`   |
| `SoundCompassWatch`       | application        | watchOS 11+ | `SoundCompassWatch/`, `Shared/{CompassView,DirectionLabel,DirectionUpdate,SharedDefaults}.swift` |
| `SoundCompassWidgets`     | app-extension      | iOS 18+     | `SoundCompassWidgets/`, `Shared/SoundCompassActivityAttributes.swift` |
| `SoundCompassWatchWidgets`| app-extension      | watchOS 11+ | `SoundCompassWatchWidgets/`, `Shared/{DirectionLabel,SharedDefaults}.swift` |
| `SoundCompassTests`       | unit-test bundle   | iOS 18+     | `SoundCompassTests/`         |

Schemes: `SoundCompass-iOS` (app + widgets + tests; use this day to day),
`SoundCompass-watchOS` (watch app + complication), and `SoundCompass`
(everything).

## Installing on your iPhone

You need a Mac with Xcode 26. No paid Apple Developer account is required
to sideload to your own device with a free Apple ID.

1. **Clone and generate:**
   ```sh
   git clone https://github.com/costajohnt/SoundCompass.git
   cd SoundCompass
   brew install xcodegen
   xcodegen generate
   open SoundCompass.xcodeproj
   ```
2. **Sign into Xcode** — Xcode → Settings (⌘,) → Accounts → click +
   → Apple ID. Sign in with the same Apple ID that's on your iPhone.
3. **Set your Team** — in `project.yml`, replace the `DEVELOPMENT_TEAM`
   value with your own team ID (or pick your Personal Team per target in
   Signing & Capabilities after generating).
4. **Change the bundle prefix** — find-replace `com.costajohnt.soundcompass`
   in `project.yml` with something unique to you, then re-run
   `xcodegen generate`. Apple ties signing to bundle IDs.
5. **Plug in your iPhone** via USB, trust the computer, select the phone
   in Xcode's device dropdown and the `SoundCompass-iOS` scheme.
6. **Build and run** — ⌘R.
7. **Trust the developer certificate** — Settings → General → VPN &
   Device Management → tap your Apple ID → Trust.
8. **Grant microphone access** on first launch. (Device motion for the
   front/back resolver needs no permission prompt.)

The free Apple ID signing certificate expires after 7 days; plug in and
⌘R again to re-sign.

If signing complains about the *Time Sensitive Notifications* capability
on a Personal Team, delete `SoundCompass/SoundCompass.entitlements` and
the `CODE_SIGN_ENTITLEMENTS` line for the iOS target in `project.yml`;
hazard notifications then arrive at normal priority.

### Watch

The watch app is not embedded in the iOS app by default (see the comment
in `project.yml`): embedding needs a paired watch for free provisioning,
and the complication's App Group (`group.com.costajohnt.soundcompass`)
needs a paid developer account. With a paid account, uncomment the
`SoundCompassWatch` dependency, rename the App Group in
`Shared/SharedDefaults.swift` and both watch entitlements files to your
team's prefix, and build the `SoundCompass` scheme.

## Using the app

1. Tap **Start listening**.
2. Hold the phone flat in your palm, screen up, top edge pointing the
   direction you're facing — like a real compass.
3. The arrow swings toward the loudest sound. The label underneath tells
   you the direction and loudness.
4. Open **Settings** (gear icon) to adjust sensitivity, enable spoken
   cues, or turn on the CROS passthrough with headphones.
5. Optional, once: Settings → **Calibration trace…**, record a clap or a
   speaker held hard to one side at about a metre, and tap **Store as this
   device's ILD gain**.

## Running the tests

```sh
xcodebuild test \
  -project SoundCompass.xcodeproj \
  -scheme SoundCompass-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Or in Xcode: `⌘U`. The tests are pure Swift and need neither a device nor
microphone access; they exercise the DSP with synthetic signals, the
state machines with injected clocks, and the hazard identifier list
against Apple's real classifier label set.

CI (`.github/workflows/soundcompass.yml`) runs the iOS tests and a
watchOS build on every push and pull request.

## Known limitations

- **Coarse angular resolution.** See the note at the top; the level cue
  available from the synthesized stereo image is small. Use the
  calibration screen and the developer trace to measure it on your phone.
- **Front / back ambiguity** is resolved only while the user rotates; the
  answer is latched for ten seconds after that.
- **Bluetooth / wired headsets with a microphone** deliver a single mono
  channel to the app if iOS picks their mic. The app asks for the built-in
  mic explicitly and warns when it still gets mono.
- **Passthrough latency** over Bluetooth is 100–200 ms; wired or USB-C
  headphones are far better for CROS use.
- **Reverberant rooms** still confuse the estimator.
- **Background operation** keeps the tap running via the `audio`
  background mode, but long sessions have not been power-audited.
- **Watch** is a mirror only; it does not estimate direction itself.

## Roadmap ideas

- Onset-gated estimation (trust the first 20 ms of a transient).
- Validate the band-limited ILD on several device models and make it the
  default.
- Coarse-sector presentation with confidence shading instead of degrees.
- Standalone watch direction estimation from the Watch's own mic.
- Swift 6 strict concurrency migration.

## License

MIT — see [LICENSE](LICENSE).
