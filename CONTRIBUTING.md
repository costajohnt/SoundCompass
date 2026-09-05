# Contributing to SoundCompass

Thanks for your interest in helping with SoundCompass. This is an
accessibility app for people with single-sided deafness, so the bar for
correctness is high and the surface area is deliberately small.

## Before you start

- Read `README.md`, `ARCHITECTURE.md` and the
  `SoundCompass/Documentation.docc` articles so you understand the DSP
  pipeline before touching it. `AUDIT.md` records the known limits of
  the sensor and the open experiments.
- Run the unit tests (`⌘U` on the `SoundCompass-iOS` scheme, or
  `xcodebuild test -project SoundCompass.xcodeproj -scheme SoundCompass-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`)
  and make sure they pass on `main` before you start changing things.
- If you're planning a non-trivial change (new feature, architectural
  rework, tuning the DSP constants), open an issue first so we can agree
  on the approach.

## Project layout

```
.
├── README.md
├── LICENSE
├── CONTRIBUTING.md                  ← you are here
├── AUDIT.md                         ← review findings and status
├── project.yml                      ← XcodeGen spec (repo root)
├── Shared/                          ← cross-platform code
├── SoundCompass/                    ← iOS app target
│   ├── DSP/                         ← Accelerate-backed direction estimation
│   ├── Motion/                      ← FrontBackResolver
│   ├── Services/                    ← session, classifier, speech, watch, hazards…
│   ├── Settings/                    ← SettingsStore + SettingsSheet
│   ├── Calibration/                 ← recorder, processor, view
│   ├── Intents/                     ← Siri/Shortcuts AppIntents
│   └── Documentation.docc/          ← DocC articles
├── SoundCompassWatch/               ← watchOS app target
├── SoundCompassWatchWidgets/        ← watchOS complication extension
├── SoundCompassWidgets/             ← iOS Live Activity extension
└── SoundCompassTests/               ← XCTest bundle
```

Before committing new Swift files, regenerate the Xcode project so
XcodeGen picks them up:

```sh
xcodegen generate
```

## Code style

- Swift 5.9 language mode, iOS 18+, watchOS 11+.
- Prefer `let` over `var`, small types, and `final` on classes that
  aren't meant to be subclassed.
- No force unwraps outside `vDSP_create_fftsetup` / `fatalError` cases
  where the failure is genuinely unrecoverable.
- DSP types must be allocation-free after `init` and single-threaded.
- Comment the *why*, not the *what*. If a DSP constant or algorithm
  choice is non-obvious, explain it inline.
- User-facing strings: a string literal inside `Text("…")`,
  `Label("…")`, `Button("…")` etc. is localized automatically. A `String`
  variable is **not** — pass a `LocalizedStringKey`, or build the value
  with `String(localized:)`, and use `Text(verbatim:)` for runtime
  values that should not be looked up. Add new keys to
  `SoundCompass/es.lproj/Localizable.strings`.
- Run the SwiftUI previews for any view you touch, plus one Dynamic
  Type size step larger than the default, to make sure it still fits.

## Testing guidelines

- **DSP changes must ship with a test.** `SoundCompassTests/TestSignals.swift`
  generates deterministic white noise and sines; the delayed-pair helper
  simulates an arbitrary-lag stereo signal.
- Don't rely on the microphone in unit tests — it isn't available in
  the Simulator and tests run on CI in headless mode.
- No sleeps. Types that depend on time take an injectable `now`
  closure; use it. Synchronize with main-queue publishes via
  `expectation(description:)` + `wait(for:)`.
- Prefer testing pure value types (`DirectionSmoother`, `HazardGate`,
  `ClassifierLabelTracker`) over driving `AudioDirectionDetector`.

## Commit messages

- Write them in the imperative: "Add X", "Fix Y", not "Added" or
  "Fixes".
- Include a paragraph explaining the *why* and any risks the reviewer
  should know about — e.g. "PHAT can land ±1 sample off under noise,
  so the test tolerance was widened".

## Pull requests

- Base your branch off `main`. Feature branches follow
  `feature/<short-slug>`; fixes follow `fix/<short-slug>`.
- Keep PRs focused. One conceptual change per PR.
- If you touched the DSP, include a trace (`dsp-diagnostics.csv`) or at
  least a description of the test setup you verified against.
- CI (`.github/workflows/soundcompass.yml`) builds and tests on every
  push. PRs that don't pass CI won't be merged.

## Reporting bugs / requesting features

File a GitHub issue with:

- What happened, what you expected.
- Device model, iOS version, OS language.
- Reproduction steps, including rough environment description
  (indoor / outdoor, quiet / loud).
- A trace or audio clip if the issue is directional.

## Security

For any security-sensitive issue (credential leak, privacy violation,
anything that involves data leaving the device), email the maintainers
privately rather than filing a public issue.
