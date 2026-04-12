# SoundCompass

An iOS app (with an Apple Watch companion) that helps people with
**single-sided deafness (SSD)** localize sound. SSD users hear normally in one
ear but little or nothing in the other, which removes the binaural cues the
brain relies on to tell *where* a sound is coming from. SoundCompass uses the
iPhone's built-in multi-microphone array to reconstruct those cues and show
them visually, haptically, and via the Watch on the wrist.

## Features

- **GCC-PHAT direction estimation** — a whitened cross-correlation that picks
  the lag between the two microphones much more reliably than plain time-
  domain correlation, especially in reverberant rooms.
- **Per-frequency-band breakdown** — a biquad filter bank (low/speech/alert/
  high) runs a separate direction estimator per band, so the UI can tell you
  *"speech on your left, traffic on your right"* in the same frame.
- **Motion-assisted front/back disambiguation** — a two-microphone array
  cannot tell front from back on its own. `FrontBackResolver` subscribes to
  `CMDeviceMotion`, fits a regression of direction on yaw, and commits to
  *front* or *back* once the user has rotated the phone a few degrees.
- **Built-in sound classification** — Apple's `SNClassifySoundRequest(.version1)`
  labels the loudest sound ("car horn", "dog bark", "speech"…) without
  shipping a CoreML model.
- **Spoken direction cues** — a toggle lets the app announce the current
  direction through `AVSpeechSynthesizer` so users who can't look at the
  screen still get a voice callout through their hearing ear.
- **Haptic ticks** — Core Haptics ticks whose intensity and sharpness scale
  with loudness and off-center-ness. Three-level strength setting.
- **Persisted settings** — sensitivity presets (Calm / Balanced / Snappy),
  haptic strength, speech rate, and a developer DSP-stats toggle, all
  backed by `UserDefaults` through `SettingsStore`.
- **Siri + Shortcuts** — `SoundCompassShortcutsProvider` registers
  `StartListeningIntent`, `StopListeningIntent`, and
  `AnnounceDirectionIntent` so users can say *"Hey Siri, start
  SoundCompass"* or *"Where is the sound in SoundCompass?"*.
- **Lock Screen / Dynamic Island Live Activity** — a WidgetKit extension
  renders the compass direction and loudness in the compact / expanded /
  minimal Dynamic Island layouts and on the Lock Screen, updated
  ≤3 Hz from `LiveActivityController`.
- **Watch complication** — a circular / corner / inline / rectangular
  complication on the watch face shows the last known direction, read
  from a shared `UserDefaults` key that the WatchConnectivity bridge
  writes on every update.
- **Audio route change handling** — plugging in a Bluetooth headset or
  joining a CarPlay session re-runs `configureSession()` and re-installs
  the tap so the DSP keeps seeing the correct format.
- **Reduce Motion + Dynamic Type** — `CompassView` drops its arrow
  animations when `accessibilityReduceMotion` is on, and every `Text` in
  the iOS app uses semantic text styles so they scale with the user's
  Dynamic Type preference.
- **Offline calibration trace** — a developer-only screen records five
  seconds of stereo audio into memory, runs it through the offline DSP
  pipeline with `CalibrationProcessor`, and renders the direction trace
  as a `Charts` line chart so you can see how the app interpreted a
  known sound without staring at the live compass.
- **In-app Help / FAQ sheet** — a searchable list of the tricky topics
  (front/back, mono headsets, privacy, orientation).
- **MIT licensed, contributing guide included.**
- **Onboarding walkthrough** — first-launch sheet that explains phone
  orientation, microphone permission, the front/back limitation, and the
  mono-headset warning.
- **Apple Watch companion** — a SwiftUI watchOS app that mirrors the compass
  on the wrist via WatchConnectivity.
- **Audio interruption handling** — phone calls, Siri, and alarms suspend
  the engine; `AudioDirectionDetector` reacts to
  `AVAudioSession.interruptionNotification` and resumes when the system
  signals `.shouldResume`.
- **Unit-tested DSP** — synthetic signal tests for `GCCPHAT`,
  `DirectionEstimator`, `SubbandDirectionEstimator`, `FrontBackResolver`,
  `SettingsStore`, `DirectionUpdate`, and `DirectionLabel`.
- **DocC catalog** — `SoundCompass/Documentation.docc` contains an article
  walking through the DSP pipeline end to end.
- **Privacy manifest** — `PrivacyInfo.xcprivacy` declares all privacy-
  relevant API usage (UserDefaults, system boot time).
- **CI** — `.github/workflows/soundcompass.yml` regenerates the Xcode
  project with XcodeGen, builds for the Simulator, and runs the DSP tests
  on every push and PR.

## How the DSP works

Modern iPhones expose a stereo input that combines spatially separated
microphones. When held flat with the screen facing up and pointing away from
the user, the resulting left / right channels carry:

- an **interaural level difference (ILD)** — the side closer to the source
  is slightly louder
- an **interaural time difference (ITD)** — the closer side receives the
  wavefront a few samples earlier

`DirectionEstimator` computes both cues every buffer:

1. RMS energy per channel (via `vDSP_rmsqv`) gives ILD.
2. `GCCPHAT.estimateLag` runs a radix-2 split-complex FFT on each channel,
   computes the cross-spectrum `R(f) · conj(L(f))`, normalises each bin to
   unit magnitude (the PHAT weight), IFFTs, and picks the lag with the
   sharpest peak. That lag is normalised against `maxLagSamples` to yield
   the ITD contribution.
3. The two cues are weighted 40/60 (ILD/ITD), clamped to `[-1, 1]`, and
   exponentially smoothed in `AudioDirectionDetector` so the UI does not
   jitter.

`SubbandDirectionEstimator` wraps `DirectionEstimator` in a bank of streaming
biquad bandpass filters (cookbook RBJ coefficients, transposed direct form II)
so direction is estimated per band. The UI highlights the loudest band.

## Source layout

```
SoundCompass/
├── README.md
├── project.yml                         # XcodeGen project definition
├── .gitignore
│
├── Shared/                             # included in both iOS and watchOS targets
│   ├── CompassView.swift               # SwiftUI half-dial compass
│   ├── DirectionLabel.swift            # shared localization helpers
│   └── DirectionUpdate.swift           # WCSession payload type
│
├── SoundCompass/                       # iOS app target
│   ├── SoundCompassApp.swift           # @main
│   ├── ContentView.swift               # top-level UI, haptics, speech toggle
│   ├── AudioDirectionDetector.swift    # AVAudioEngine tap + orchestration
│   ├── Info.plist
│   ├── DSP/
│   │   ├── DirectionEstimator.swift    # ILD + GCC-PHAT fusion
│   │   ├── GCCPHAT.swift               # FFT/IFFT cross-correlator
│   │   ├── BiquadBandpass.swift        # RBJ TDF-II biquad
│   │   └── SubbandDirectionEstimator.swift
│   └── Services/
│       ├── SoundClassifier.swift       # SoundAnalysis wrapper
│       ├── SpeechAnnouncer.swift       # AVSpeechSynthesizer rate-limited cues
│       └── WatchSessionManager.swift   # WCSession → watch
│
├── SoundCompassWatch/                  # watchOS app target
│   ├── SoundCompassWatchApp.swift
│   ├── WatchContentView.swift
│   ├── WatchConnectivityBridge.swift   # WCSession ← phone
│   └── Info.plist
│
└── SoundCompassTests/                  # XCTest bundle
    ├── TestSignals.swift               # deterministic signal generators
    ├── GCCPHATTests.swift
    ├── DirectionEstimatorTests.swift
    ├── SubbandDirectionEstimatorTests.swift
    ├── DirectionUpdateTests.swift
    └── DirectionLabelTests.swift
```

## Generating the Xcode project

The repo ships a [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec so
the project file can be regenerated on any machine without checking a fragile
`project.pbxproj` into git:

```sh
brew install xcodegen
cd SoundCompass
xcodegen generate
open SoundCompass.xcodeproj
```

`project.yml` declares five targets:

| Target                    | Type               | Platform    | Sources                      |
|---------------------------|--------------------|-------------|------------------------------|
| `SoundCompass`            | application        | iOS 18+     | `SoundCompass/`, `Shared/`   |
| `SoundCompassWatch`       | application        | watchOS 11+ | `SoundCompassWatch/`, `Shared/{CompassView,DirectionLabel,DirectionUpdate}.swift` |
| `SoundCompassWidgets`     | app-extension      | iOS 18+     | `SoundCompassWidgets/`, `Shared/SoundCompassActivityAttributes.swift` |
| `SoundCompassWatchWidgets`| app-extension      | watchOS 11+ | `SoundCompassWatchWidgets/`, `Shared/DirectionLabel.swift` |
| `SoundCompassTests`       | unit-test bundle   | iOS 18+     | `SoundCompassTests/`         |

The watch target is embedded into the iOS app and wired to it through
`WKCompanionAppBundleIdentifier`.

> Once generated, flip the **Signing & Capabilities → Team** on both app
> targets to your own development team before building on a device.

## Installing on your iPhone

You need a Mac with Xcode. No paid Apple Developer account required —
a free Apple ID works for sideloading to your own device.

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
3. **Set your Team** — click the SoundCompass project in the left
   sidebar, then for each target under Signing & Capabilities, pick
   your Personal Team from the Team dropdown.
4. **Change the bundle ID** — find-replace `com.soundcompass.app` with
   something unique to you (e.g. `com.yourname.soundcompass`) in
   `project.yml`, then re-run `xcodegen generate`. This is needed
   because Apple ties signing to bundle IDs.
5. **Plug in your iPhone** via USB. Trust the computer if prompted.
   Select your phone from Xcode's device dropdown (top bar).
6. **Build and run** — hit ⌘R. Xcode will build, install, and launch
   the app on your phone.
7. **Trust the developer certificate** — if you see "Untrusted
   Developer" on your phone, go to Settings → General → VPN & Device
   Management → tap your Apple ID → Trust.
8. **Grant permissions** — the app will ask for microphone and motion
   access on first launch. Grant both.

The free Apple ID signing certificate expires after 7 days. Just
plug in and hit ⌘R again to re-sign. If that gets annoying, a
$99/year Apple Developer account gives you a year-long certificate.

## Using the app

1. Tap **Start listening**.
2. Hold the phone flat in your palm, screen up, top edge pointing
   the direction you're facing — like a real compass.
3. The arrow swings toward the loudest sound. The label underneath
   tells you the direction and loudness.
4. Open **Settings** (gear icon) to adjust sensitivity, enable
   spoken direction cues, or try the CROS audio passthrough with
   headphones.
5. Optional: pair an Apple Watch to mirror the compass on your wrist.

## Running the tests

From the command line:

```sh
xcodebuild test \
  -project SoundCompass.xcodeproj \
  -scheme SoundCompass-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Or in Xcode: `⌘U`. The tests are pure-Swift and require neither a device
nor microphone access; they exercise the DSP with synthetic signals.

## Known limitations

- **Front / back ambiguity.** A two-microphone array cannot distinguish a
  sound in front from a sound behind you — both produce identical ILD / ITD.
  `FrontBackResolver` uses device motion (gyroscope yaw) to disambiguate
  when the user rotates the phone slightly.
- **Bluetooth / wired headsets.** These deliver a single mono channel to the
  app, which makes direction estimation impossible. The UI surfaces a warning
  when it detects a mono input.
- **Reverberant rooms.** GCC-PHAT helps, but extremely reflective spaces
  (tiled bathrooms, stairwells) still confuse the estimator.
- **Background operation.** The `audio` background mode is declared in
  `Info.plist`, but long-running background listening has not been audited.
- **Watch-only.** The Watch companion is a pure mirror; it does not estimate
  direction from its own microphone.

## Roadmap ideas

- Richer classifier output (top-K results, per-band classification).
- Custom CoreML model trained on hazard sounds (sirens, smoke alarms,
  reversing beeps).
- Standalone watch direction estimation from the Watch's own mic.
- Swift 6 strict concurrency migration.

## License

TBD.
