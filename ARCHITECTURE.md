# SoundCompass architecture

A one-page map of how the iOS app, the watchOS companion, and the
widget extensions fit together. For the DSP-specific details see
`SoundCompass/Documentation.docc/DSPPipeline.md`; for the review that
shaped the current design see `AUDIT.md`.

## Targets

```
SoundCompass.xcodeproj (generated from project.yml via XcodeGen)
├── SoundCompass                  iOS 18+ app target
├── SoundCompassWatch             watchOS 11+ app target (not embedded by default)
├── SoundCompassWatchWidgets      watchOS WidgetKit extension (complication)
├── SoundCompassWidgets           iOS WidgetKit extension (Live Activity)
└── SoundCompassTests             iOS unit-test bundle
```

`Shared/` holds the code compiled into more than one target: the compass
view, the localized direction labels, the `DirectionUpdate` payload, the
Live Activity `ActivityAttributes`, and `SharedDefaults` (the App Group
suite the watch app and its complication both read).

## iOS app layers

```
                   ┌──────────────────────┐
                   │       SwiftUI        │
                   │  ContentView / Sheets│
                   └──────────┬───────────┘
                              │ @EnvironmentObject
                              ▼
                   ┌──────────────────────┐
                   │ AudioDirectionDetector│  ObservableObject
                   └──┬────────┬────────┬──┘
                      │        │        │
           ┌──────────┘        │        └──────────┐
           ▼                   ▼                   ▼
   ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
   │ AVAudioEngine│   │ CoreMotion   │   │ SoundClassifier
   │     tap      │   │ FrontBack    │   │ SpeechAnnouncer
   │              │   │ Resolver     │   │ WatchSessionManager
   └──────┬───────┘   └──────────────┘   │ LiveActivityController
          │                              │ PassthroughMixer
          ▼                              │ HazardNotifier
   ┌──────────────┐                      │ EventHistoryStore
   │ DSP pipeline │                      │ SessionStats
   │ Estimator /  │                      │ SettingsStore
   │ Subband /    │                      │ DSPDiagnostics
   │ GCC-PHAT     │                      └──────────────────┘
   └──────┬───────┘
          ▼  (main queue)
   ┌──────────────┐
   │ DirectionSmoother + HazardGate │
   └──────────────┘
```

### Capture

`AudioSessionConfigurator` is the single owner of session setup:
`.playAndRecord` with `.defaultToSpeaker` and `.allowBluetoothA2DP`
(needed for any Bluetooth *output*; HFP is deliberately not allowed
because it would switch the input to a mono headset mic), built-in mic
preferred, **back** stereo data source preferred with the front source
as a mirrored fallback. Both the live detector and the calibration
recorder call it, so their left/right agree.

Route changes only reinstall the tap when the *input* port set changed;
output-only changes go to the passthrough mixer.

### DSP pipeline

1. `AVAudioEngine.installTap` delivers a stereo `AVAudioPCMBuffer`. The
   detector walks it in 2048-frame chunks so every frame is analysed even
   when the system delivers larger buffers.
2. `DirectionEstimator` computes broadband loudness, an ILD from either
   the broadband or a 1–8 kHz band-limited copy (`BiquadBandLimiter`),
   and an optional GCC-PHAT lag with a confidence gate. Output:
   `ild + 0.35 · confidence · itd`.
3. `SubbandDirectionEstimator` runs ILD-only estimators inside four
   streaming `BiquadBandpass` bands.
4. On the main queue, `DirectionSmoother` blends the estimate with the
   sensitivity preset's weight (0.9 during a hazard) and `HazardGate`
   turns "the classifier currently says hazard" into an edge-triggered
   banner state.
5. `SoundClassifier` runs Apple's `SNClassifySoundRequest(.version1)` on
   its own queue; `ClassifierLabelTracker` clears labels on a
   low-confidence result or after 2.5 s without one.
6. `FrontBackResolver` regresses direction on unwrapped yaw (front ⇒
   positive slope, CoreMotion yaw being counter-clockwise positive) and
   latches the answer for ten seconds.

### Self-excitation guard

The detector ignores microphone input while `AVSpeechSynthesizer` is
speaking (plus a 0.3 s tail) and for a few tens of milliseconds after
each haptic, via a lock-protected "mute until" timestamp read on the tap
thread.

### Fan-out

Per buffer, the detector fans out to `SpeechAnnouncer`,
`WatchSessionManager` (rate-limited, hazard transitions bypass the
limit), `LiveActivityController` (≤3 Hz), `HazardNotifier` (background
only), and `EventHistoryStore` + `SessionStats`.

### Settings

`SettingsStore` is an `ObservableObject` over an injectable
`UserDefaults`. Besides the user-facing options it stores the per-device
`ildGain` written by the calibration screen and the developer
`ildHighBand` switch. The detector subscribes to both: a gain change is
applied to the live estimators immediately, a band change reinstalls the
tap.

## Watch companion

`WatchConnectivityBridge` receives `DirectionUpdate` dictionaries, updates
`@Published` state, writes the last direction to `SharedDefaults.store`
(the App Group suite), asks WidgetKit to reload at most every five
minutes or on a hazard, and plays a wrist haptic — `.notification` when a
hazard begins, a direction tick otherwise.

`WatchContentView` renders inside a 1 Hz `TimelineView` so the stale
indicator appears without waiting for the next message.

## Widget extensions

`SoundCompassWidgets` (iOS) renders the Live Activity from
`SoundCompassActivityAttributes`. `SoundCompassWatchWidgets` (watchOS)
reads `SharedDefaults.store` for the complication; without the App Group
entitlement on both watch targets it would only ever see its placeholder.

## Tests

`SoundCompassTests` (`@testable import SoundCompass`) covers the DSP
(`GCCPHAT`, `DirectionEstimator` including device-scale ILD and the
band-limited path, `SubbandDirectionEstimator`, `DirectionSmoother`,
`CalibrationProcessor` including gain suggestion), the state machines
(`HazardGate`, `ClassifierLabelTracker`, `FrontBackResolver` via a
DEBUG-only injection hook, `EventHistoryStore` and `SessionStats` with
injected clocks, `SpeechAnnouncer` with the synthesizer disabled), the
session source-selection rule, and the hazard identifier list against
Apple's real `knownClassifications`.

## CI

`.github/workflows/soundcompass.yml` runs two jobs on `macos-15`: the
iOS unit tests via `xcodebuild test` on the `SoundCompass-iOS` scheme,
and a compile of the `SoundCompass-watchOS` scheme for the watchOS
Simulator so the companion cannot rot unnoticed.
