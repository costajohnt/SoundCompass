# SoundCompass architecture

A one-page map of how the iOS app, the watchOS companion, and the
widget extensions fit together. For the DSP-specific details see
`SoundCompass/Documentation.docc/DSPPipeline.md`.

## Targets

```
SoundCompass.xcodeproj (generated from project.yml via XcodeGen)
├── SoundCompass                  iOS 17+ app target
├── SoundCompassWatch             watchOS 10+ app target
├── SoundCompassWatchWidgets      watchOS WidgetKit extension (complication)
├── SoundCompassWidgets           iOS WidgetKit extension (Live Activity)
└── SoundCompassTests             iOS unit-test bundle
```

Everything in `Shared/` is compiled into all platform targets so the
compass view, direction label helpers, the `DirectionUpdate` payload
type, and the Live Activity `ActivityAttributes` are the exact same
symbols on both sides of every IPC boundary.

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
   │ AVAudioEngine│   │ CoreMotion   │   │ Shared ObservableObjects
   │     tap      │   │ FrontBack    │   │ SoundClassifier
   │              │   │ Resolver     │   │ SpeechAnnouncer
   └──────┬───────┘   └──────────────┘   │ WatchSessionManager
          │                              │ LiveActivityController
          ▼                              │ PassthroughMixer
   ┌──────────────┐                      │ HazardNotifier
   │ DSP pipeline │                      │ EventHistoryStore
   │ Direction /  │                      │ SessionStats
   │ Subband /    │                      │ SettingsStore
   │ GCC-PHAT     │                      └──────────────────┘
   └──────────────┘
```

### DSP pipeline

The pipeline in `SoundCompass/DSP/` is pure Swift, allocation-free
after init, and unit-testable with synthetic signal helpers in
`SoundCompassTests/TestSignals.swift`:

1. `AVAudioEngine.installTap` delivers a stereo `AVAudioPCMBuffer`
   on the audio thread.
2. `DirectionEstimator` fuses `vDSP_rmsqv`-based ILD with
   `GCCPHAT`-based ITD into a normalized direction / magnitude.
3. `SubbandDirectionEstimator` runs an independent estimator inside
   each of four octave-ish bands via streaming `BiquadBandpass`
   filters.
4. `SoundClassifier` (Apple's built-in
   `SNClassifySoundRequest(.version1)`) runs on its own
   analysisQueue and publishes a top label.
5. `FrontBackResolver` correlates direction changes with
   `CMDeviceMotion.attitude.yaw` to distinguish front from back.

Results are pushed to the main queue and into `@Published` state.

### Fan-out

On every DSP update, the detector fans out to:

- `SpeechAnnouncer` — `AVSpeechSynthesizer`, rate-limited.
- `WatchSessionManager` — `WCSession.sendMessage` or
  `updateApplicationContext` depending on reachability.
- `LiveActivityController` — Dynamic Island + Lock Screen.
- `HazardNotifier` — backgrounded local notifications on hazards.
- `EventHistoryStore` + `SessionStats` — in-memory event log.

### CROS passthrough

`PassthroughMixer` connects `engine.inputNode` to
`engine.mainMixerNode` and pans the output hard toward the user's
hearing ear, so headphones stream the full stereo capture into the
working ear. Only engages when a safe output route (headphones,
Bluetooth, AirPlay, USB audio, line-out) is connected — never over
the internal speaker to avoid feedback.

### Interruption + route changes

The detector observes `AVAudioSession.interruptionNotification` and
`routeChangeNotification`. Phone calls / Siri / alarms pause the tap
and resume cleanly; headset plug/unplug tears down the tap and
re-installs it with the new format.

### Settings

`SettingsStore` is an `ObservableObject` backed by a (dependency-
injected) `UserDefaults`. The detector subscribes to the relevant
publishers and propagates changes: sensitivity drives the
exponential smoother weights, hazard alerts gate the hazard override,
speech fields drive `SpeechAnnouncer`, and passthrough settings drive
`PassthroughMixer`.

## Watch companion

`SoundCompassWatch` is a thin SwiftUI mirror. `WatchConnectivityBridge`
receives `DirectionUpdate` dictionaries and both:

1. Updates `@Published` state so `WatchContentView` redraws.
2. Writes the latest direction to `UserDefaults` and calls
   `WidgetCenter.reloadAllTimelines()` so the
   `SoundCompassWatchWidgets` complication picks it up on its next
   timeline refresh.
3. Plays a `WKInterfaceDevice.directionUp/click/directionDown` haptic
   when a loud enough sound arrives at a meaningfully different
   direction.

## Widget extensions

`SoundCompassWidgets` (iOS) renders the `SoundCompassLiveActivity`
for the Lock Screen and Dynamic Island, consuming the
`SoundCompassActivityAttributes` defined in `Shared/`.

`SoundCompassWatchWidgets` (watchOS) ships a
`SoundCompassComplication` available in circular, corner, inline,
and rectangular accessory families.

## Tests

`SoundCompassTests` is an `@testable import SoundCompass` XCTest
bundle that exercises the DSP layer (`GCCPHAT`, `DirectionEstimator`,
`SubbandDirectionEstimator`), the motion-fusion `FrontBackResolver`
via a DEBUG-only injection hook, and the plain Swift state types
(`SettingsStore`, `SessionStats`, `EventHistoryStore`,
`HazardClassifier`, `DirectionLabel`, `DirectionUpdate`,
`SoundCompassActivityAttributes`, `CalibrationProcessor`,
`PassthroughMixer`). All tests run without a device — they use
synthetic signals from `TestSignals.swift` and dependency-injected
`UserDefaults` suites.

## CI

`.github/workflows/soundcompass.yml` runs on `macos-14`, installs
XcodeGen via Homebrew, regenerates the project, builds for the iOS
Simulator, and runs the full test suite on every push and pull
request.
