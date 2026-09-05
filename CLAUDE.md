# SoundCompass

## Project overview

iOS accessibility app for single-sided deafness (SSD). Uses the iPhone's multi-microphone array to estimate sound direction via GCC-PHAT cross-correlation fused with interaural level difference. Pure Swift, no third-party dependencies.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild test \
  -project SoundCompass.xcodeproj \
  -scheme SoundCompass-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Architecture

- `SoundCompass/DSP/` — allocation-free DSP pipeline (GCCPHAT, DirectionEstimator, DirectionSmoother, BiquadBandpass + BiquadBandLimiter, SubbandDirectionEstimator)
- `SoundCompass/Services/` — AudioSessionConfigurator, SoundClassifier (+ ClassifierLabelTracker), HazardClassifier, HazardGate, HazardNotifier, SpeechAnnouncer, WatchSessionManager, LiveActivityController, PassthroughMixer, EventHistoryStore, SessionStats, DSPDiagnostics, Log
- `SoundCompass/Motion/` — FrontBackResolver (CoreMotion yaw regression; yaw is CCW-positive, front ⇒ positive slope)
- `SoundCompass/Calibration/` — offline trace + per-device ILD gain
- `Shared/` — cross-platform code (CompassView, DirectionLabel, DirectionUpdate, SharedDefaults, SoundCompassActivityAttributes)
- `SoundCompassWatch/` — watchOS companion (mirror only; not embedded by default)
- `SoundCompassWidgets/` — iOS Live Activity / Dynamic Island
- `SoundCompassWatchWidgets/` — watchOS complication (App Group `UserDefaults`)
- `AUDIT.md` — review findings, fix status, and the open device experiments

## Key conventions

- XcodeGen: never check in `.xcodeproj`, always regenerate from `project.yml`
- DSP code must be allocation-free after init (runs on real-time audio thread)
- Use `SoundCompass-iOS` scheme for building/testing without watchOS platform installed
- All tests use synthetic signals from `SoundCompassTests/TestSignals.swift` — no device or mic needed; no sleeps (inject `now` closures)
- Session setup lives only in `AudioSessionConfigurator` (A2DP allowed, HFP not)
- User-facing strings: literals in `Text("…")` localize; `String` values need `String(localized:)` or `Text(verbatim:)`; add Spanish keys to `es.lproj`
- Swift 5.9 language mode (Swift 6 strict concurrency migration is a future task)
- Deployment targets: iOS 18+, watchOS 11+
- CI: iOS tests on `SoundCompass-iOS`, watchOS compile on `SoundCompass-watchOS`
