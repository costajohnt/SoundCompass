# Changelog

All notable changes to SoundCompass land here. Each batch corresponds to
a commit on the development branch.

## Unreleased

### Added

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
