# Contributing to SoundCompass

Thanks for your interest in helping with SoundCompass. This is an
accessibility app for people with single-sided deafness, so the bar for
correctness is high and the surface area is deliberately small.

## Before you start

- Read `README.md` end-to-end and the `SoundCompass/Documentation.docc`
  articles so you understand the DSP pipeline before touching it.
- Run the unit tests (`⌘U` in Xcode, or
  `xcodebuild test -scheme SoundCompass -destination 'platform=iOS Simulator,name=iPhone 15'`)
  and make sure they pass on `main` before you start changing things.
- If you're planning a non-trivial change (new feature, architectural
  rework, tuning the DSP blend weights), open an issue first so we can
  agree on the approach.

## Project layout

```
SoundCompass/
├── README.md
├── LICENSE
├── CONTRIBUTING.md                  ← you are here
├── project.yml                      ← XcodeGen spec
├── Shared/                          ← cross-platform code (iOS + watch + widgets)
├── SoundCompass/                    ← iOS app target
│   ├── DSP/                         ← Accelerate-backed direction estimation
│   ├── Motion/                      ← FrontBackResolver
│   ├── Services/                    ← audio, classifier, speech, watch, live activity
│   ├── Settings/                    ← SettingsStore + SettingsSheet
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

- Swift 5.9, iOS 17+, watchOS 10+.
- Prefer `let` over `var`, small types, and `final` on classes that
  aren't meant to be subclassed.
- No force unwraps outside `vDSP_create_fftsetup` / `fatalError` cases
  where the failure is genuinely unrecoverable.
- Comment the *why*, not the *what*. If a DSP constant or algorithm
  choice is non-obvious, explain it inline.
- User-facing strings go through SwiftUI's `Text("literal")` so
  `Localizable.strings` can pick them up for translation.
- Run the SwiftUI previews for any view you touch, plus one Dynamic
  Type size step larger than the default, to make sure it still fits.

## Testing guidelines

- **DSP changes must ship with a test.** The
  `SoundCompassTests/TestSignals.swift` helper generates deterministic
  white noise and sines; the delayed-pair helper simulates an
  arbitrary-lag stereo signal.
- Don't rely on the microphone in unit tests — it isn't available in
  the Simulator and tests run on CI in headless mode.
- Avoid sleeps; use `expectation(description:)` + `wait(for:)` to
  synchronize with main-queue publishes from `@Published` properties.

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
- If you touched the DSP, include a recording or at least a
  description of the test setup you verified against.
- CI (`.github/workflows/soundcompass.yml`) will build and test on
  every push. PRs that don't pass CI won't be merged.

## Reporting bugs / requesting features

File a GitHub issue with:

- What happened, what you expected.
- Device model, iOS version, OS language.
- Reproduction steps, including rough environment description
  (indoor / outdoor, quiet / loud).
- A video or audio clip if the issue is directional.

## Security

For any security-sensitive issue (credential leak, privacy violation,
anything that involves data leaving the device), email the maintainers
privately rather than filing a public issue.
