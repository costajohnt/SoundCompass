# Changelog

All notable changes to SoundCompass land here. Each batch corresponds to
a commit on the development branch.

## Unreleased

### Fixed (audit follow-up — see `AUDIT.md` for the findings)

- **Front/back resolver sign.** CoreMotion yaw is counter-clockwise
  positive, so a source in front makes direction *grow* with yaw. The
  resolver had the two cases swapped; the tests encoded the same wrong
  assumption. Both fixed, plus a physically derived clockwise-turn test.
- **Bluetooth passthrough.** The session now sets `.allowBluetoothA2DP`;
  without it `playAndRecord` never routes output to Bluetooth headphones
  and the CROS feature could only work over a wire. HFP stays disallowed
  so the built-in stereo mic remains the input. The I/O buffer is
  shortened to 10 ms while passthrough is connected.
- **Stale classifier label re-arming hazards.** Labels are now cleared by
  a low-confidence result and expire after 2.5 s (`ClassifierLabelTracker`);
  the banner logic is an explicit edge-triggered `HazardGate`.
- **Watch complication never updated.** It read `UserDefaults.standard`
  in its own sandbox. Both watch targets now share an App Group suite
  (`SharedDefaults`), with entitlements checked in, and timeline reloads
  are throttled to WidgetKit's budget.
- **Hazard identifier list** validated against Apple's real
  `knownClassifications` in a simulator test; keyword rules (`siren`,
  `alarm`, `horn`, …, with musical-instrument exclusions) catch the
  specific variants.
- **Route-change restart storm** guarded: the tap is reinstalled only when
  the input port set actually changed.
- **Invalid input format** (0 Hz / 0 ch) now throws a Swift error instead
  of an uncatchable Objective-C exception from `installTap`.
- **Buffers larger than 2048 frames** are processed in chunks instead of
  having their tail dropped.
- **Speech and haptic self-excitation.** Microphone input is muted while
  the synthesizer speaks and briefly after each haptic.
- **Front/back answer vanishing** seconds after the user stops turning:
  results are latched for ten seconds.
- **Time-sensitive hazard notifications** now carry the entitlement they
  need; the unavailable critical-alert sound was replaced with `.default`.
- **Localization actually applies.** Views that received `String` values
  used the non-localizing `Text` initializer; they now take
  `LocalizedStringKey` or `String(localized:)`. Spanish coverage extended
  to Settings, Help, History, Calibration and the dynamic banners.
- **Calibration recorder** used the first stereo source and could be
  mirrored relative to the live compass; both now share
  `AudioSessionConfigurator`.
- Settings copy no longer promises watch behaviour that did not exist;
  the watch now does tap on hazards (`DirectionUpdate.isHazard`).
- Documentation drift (bundle prefix, repo name, paths, deployment
  targets, DSP description, test counts, license) corrected throughout.

### Added

- `DirectionSmoother` — one smoother shared by the live pipeline and the
  calibration trace, unit-tested.
- Per-device ILD gain: the calibration screen derives a gain from a
  hard-side recording and stores it (`SettingsStore.ildGain`).
- Developer option to measure the ILD in a 1–8 kHz band
  (`BiquadBandLimiter`), off by default pending device measurements.
- Per-band and ILD-source RMS columns in the diagnostics trace.
- `SoundCompass-watchOS` scheme and a watchOS build job in CI.
- 45 new unit tests (120 total); clock injection removed all sleeps.

### Removed

- Unused `ObjCExceptionCatcher` and bridging header; unused `Log`
  categories; per-band GCC-PHAT (ILD-only per band, 3× cheaper).

### Previously in Unreleased

- **Direction-finding audit** — root-caused the inaccurate direction
  estimates and fixed the pipeline end to end:
  - `configureSession()` now explicitly prefers the **back** stereo data
    source. Front and back sources deliver mirrored left/right images
    (WWDC20 10226); the old code took whichever stereo-capable source
    enumerated first, which mirrors left/right on devices that list the
    front source before the back one. Falling back to the front source
    now flips the sign of every direction estimate to compensate.
  - `DirectionEstimator` fuses cues by per-frame confidence instead of a
    fixed 40/60 ILD/ITD blend. The GCC-PHAT lag only earns weight when
    its normalized correlation peak is sharp and inside the physical
    window; lags railed at the search-window edge are rejected. ILD is
    expanded with `tanh(ildGain · ild)` instead of a hard clamp.
  - `maxLagSamples` now defaults to the physical aperture limit
    (≈21 samples at 48 kHz) instead of 48, so reverb tails can no longer
    win the correlation peak at impossible lags.
  - `setPreferredInputNumberOfChannels(2)` is requested explicitly.
  - Debug overlay (gated by the developer DSP-stats setting) shows the
    active data source, raw ILD/ITD, lag, and ITD confidence live.
  - New regression tests: uncorrelated noise stays centered; railed lag
    is ignored.

- **Hardening pass**
  - `ContentView.regularLayout` was collapsing the right-column
    `ScrollView` because the enclosing `HStack` had no explicit
    `maxHeight: .infinity`. Fixed.
  - `ARCHITECTURE.md` — one-page overview of targets, layers, and
    how all the pieces fit together.
  - `CHANGELOG.md` — this file.

### Previous batches

- **CROS passthrough, hazard notifications, Spanish localization**
  - `PassthroughMixer` routes phone-mic audio through
    `mainMixerNode` panned toward the user's good ear. Only engages
    on a safe output route (headphones / Bluetooth / AirPlay / USB /
    line-out).
  - `HazardNotifier` posts a time-sensitive local notification when
    the app is in background and a hazard sound is detected.
  - `es.lproj/Localizable.strings` full Spanish translation.
  - `PassthroughMixerTests` smoke test covering the state machine.

- **Session stats, hazard AHAP haptic, CSV export, iPad layout, GH templates**
  - `SessionStats` — duration, event / hazard counters, top label /
    direction bucket, `csv(events:)` exporter.
  - `EventHistoryView` now includes a session summary card and an
    ellipsis menu with Clear + Export CSV via `ShareLink`.
  - Rich `CHHapticPattern` for hazard events (0.25 s continuous
    buzz + three sharp transients).
  - iPad (`horizontalSizeClass == .regular`) split layout with
    compass on the left and a scrollable card column on the right.
  - `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.yml` and
    `.github/PULL_REQUEST_TEMPLATE.md`.

- **Hazard alerts, event history, good-ear, permission deep link, voice**
  - `HazardClassifier` flags safety-critical sounds; detector
    bypasses the exponential smoother on hazards.
  - `EventHistoryStore` + `EventHistoryView` for a "what was that?"
    timeline.
  - `SettingsStore.hearingEar`, `hazardAlerts`, `speechVoiceIdentifier`
    with pickers in `SettingsSheet`.
  - Permission-denied banner with an **Open Settings** deep link via
    `@Environment(\.openURL)`.
  - Approximate dB SPL readout in `DebugStatsView`.

- **Calibration trace, help sheet, scene phase, license, watch haptics**
  - `CalibrationRecorder` + `CalibrationProcessor` + `CalibrationView`
    for recording 5 seconds of audio and walking it through the
    offline DSP pipeline, rendered as a `Charts` line graph.
  - `HelpSheet` with an in-app FAQ.
  - `AudioDirectionDetector.handleBackgroundTransition()` /
    `handleForegroundTransition()` driven from `@Environment(\.scenePhase)`.
  - Watch haptic feedback on loud, direction-distinct sounds.
  - MIT `LICENSE` + `CONTRIBUTING.md`.
  - `Assets.xcassets` with a `LaunchBackground` color asset and
    `UILaunchScreen` pointing at it.

- **Live Activity, watch complication, Siri Shortcuts, a11y**
  - `SoundCompassWidgets` WidgetKit extension rendering the compass
    on the Lock Screen and Dynamic Island.
  - `LiveActivityController` throttled to ~3 Hz.
  - `SoundCompassWatchWidgets` WidgetKit extension for the watch
    complication (circular / corner / inline / rectangular).
  - `SoundCompassIntents` + `SoundCompassShortcutsProvider` for
    `StartListeningIntent` / `StopListeningIntent` /
    `AnnounceDirectionIntent`.
  - Dynamic Type semantic text styles across the iOS UI.
  - Reduce Motion gate on `CompassView` animations.
  - Audio `routeChangeNotification` handling.

- **Motion disambiguation, settings, privacy manifest, CI, DocC**
  - `FrontBackResolver` with CoreMotion yaw unwrap +
    ordinary-least-squares regression of direction on yaw.
  - `SettingsStore` backed by injectable `UserDefaults` +
    `SettingsSheet`.
  - `AudioDirectionDetector.start()` re-entrancy guard.
  - `PrivacyInfo.xcprivacy` with CA92.1 (UserDefaults) and 35F9.1
    (SystemBootTime).
  - `.github/workflows/soundcompass.yml` CI running `xcodebuild test`
    via XcodeGen on every push / PR.
  - `Documentation.docc/SoundCompass.md` + `DSPPipeline.md`.

- **Audio interruption + race + onboarding + GCCPHAT fix**
  - Fixed Swift exclusive-access violation in `GCCPHAT.estimateLag`
    (`vDSP_zvmul` was aliasing `&rightSplit` as both `A` and `C`).
  - `AVAudioSession.interruptionNotification` handler for phone
    calls, Siri, alarms.
  - `SoundClassifier` `streamAnalyzer` access serialized on the
    private analysis queue.
  - `OnboardingSheet` gated by `@AppStorage("hasSeenOnboarding")`.

- **GCC-PHAT, subbands, classifier, watch, tests**
  - Replaced naive dot-product ITD with GCC-PHAT (FFT / PHAT weight /
    IFFT).
  - `SubbandDirectionEstimator` with RBJ biquad filter bank.
  - Built-in sound classification via `SNClassifySoundRequest`.
  - watchOS app target with `WatchConnectivityBridge`.
  - XCTest bundle + XcodeGen `project.yml` + initial CI.

- **Initial scaffold**
  - SwiftUI iOS app with a basic ILD + naive cross-correlation ITD
    direction estimator, compass view, and haptic feedback.
