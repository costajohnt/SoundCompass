# SoundCompass run book

Everything you need to go from a fresh `git clone` on your Mac to a
running build on your iPhone.

---

## Repo

- `costajohnt/SoundCompass`, default branch `main`.
- `project.yml` is at the repository root; there is no checked-in
  `.xcodeproj`.

---

## Step 0 — prerequisites

- **Xcode 26+** from the App Store. Launch it once so it installs the
  command-line tools.
- **iOS simulator runtime** (and **watchOS** if you want to build the
  companion): `Xcode → Settings → Components`, or
  ```bash
  xcodebuild -downloadPlatform iOS
  xcodebuild -downloadPlatform watchOS
  ```
- **Homebrew** — https://brew.sh
- An **Apple ID signed into Xcode** under `Settings → Accounts`. A free
  account is enough to sideload the iOS app to your own device.
- A **physical iPhone** on iOS 18 or later. The Simulator builds and runs
  the tests, but its microphone is mono, so the compass is meaningless
  there.
- Optional: a paired **Apple Watch** on watchOS 11+ and a paid developer
  account (the complication needs an App Group).

---

## Step 1 — clone and generate

```bash
git clone https://github.com/costajohnt/SoundCompass.git
cd SoundCompass
brew install xcodegen
xcodegen generate
open SoundCompass.xcodeproj
```

Re-run `xcodegen generate` whenever `project.yml` changes or a Swift
file is added.

---

## Step 2 — run the unit tests first

Select the `SoundCompass-iOS` scheme, an **iPhone 17 Pro** simulator,
and press `⌘U`. Or:

```bash
xcodebuild test \
  -project SoundCompass.xcodeproj \
  -scheme SoundCompass-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

All 120 tests should pass. Two of them read Apple's built-in sound
classifier label list from the simulator and validate the hazard
identifiers against it; they skip if the model is unavailable.

---

## Step 3 — signing and first device run

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your team and replace the
   bundle prefix `com.costajohnt.soundcompass` with your own, then
   `xcodegen generate`.
2. Plug in the iPhone, trust the computer, pick it as the destination.
3. ⌘R with the `SoundCompass-iOS` scheme.
4. Grant **microphone** permission on first launch. Device motion needs
   no prompt.
5. If the device says *not trusted*, go to **Settings → General → VPN &
   Device Management** and trust your certificate.
6. If signing fails on the *Time Sensitive Notifications* capability with
   a Personal Team, remove the iOS entitlements file and the
   `CODE_SIGN_ENTITLEMENTS` line; the app works without it.

---

## Step 4 — smoke-test on real hardware

Hold the phone flat in your palm, screen up, top edge pointing the way
you face. Tap **Start listening**.

- [ ] Clap to your **right**: arrow swings right. Clap **left**: left.
- [ ] Speak from straight ahead: arrow stays near centre.
- [ ] Have someone speak from **behind** you and turn your body ~30°
      either way. The banner should commit to **in front** / **behind**
      within a second or two and stay there for ~10 s after you stop.
- [ ] Settings → **Show DSP stats**. The overlay shows `ILD`, `iL`/`iR`
      (the ILD-source RMS) and `conf`. Then Settings → **Calibration
      trace…** → record a clap held hard to one side → **Store as this
      device's ILD gain**. Repeat the clap test; deflection should be
      fuller.
- [ ] Pull the trace for offline analysis:
      ```bash
      xcrun devicectl device copy from --device <udid> \
        --domain-type appDataContainer --domain-identifier <bundle-id> \
        --source Documents/dsp-diagnostics.csv --destination .
      ```
      Columns include broadband and per-band ILD; compare the flat hold
      against an upright hold (camera facing forward).
- [ ] Trigger a hazard: play a siren from a phone/laptop. Red banner,
      strong haptic. Lock the phone and repeat: a notification should
      arrive. The banner must **not** come back for a later non-hazard
      loud sound.
- [ ] Turn on **Speak direction**. The callout must not itself register
      as "Speech" on the classifier chip.
- [ ] Headphones: set **Hearing ear**, toggle **Audio passthrough**.
      Wired / USB-C: near-immediate. AirPods (A2DP): expect 100–200 ms of
      delay. Nothing should ever come out of the phone speaker.
- [ ] Siri: *"Hey Siri, start SoundCompass"*.
- [ ] Lock the phone while listening: Live Activity on the Lock Screen /
      Dynamic Island.
- [ ] Paired watch (paid account, watch target embedded): compass
      mirrors, hazard taps the wrist, complication updates within a few
      minutes.

---

## Step 5 — when something breaks

Report the exact error text from Xcode's Issue Navigator, the failing
file and line, and on hardware whether it was a crash, a wrong arrow,
silence, a banner that never flipped, or something else. Attach
`dsp-diagnostics.csv` for direction problems.

Console.app filter: subsystem `com.soundcompass.app`.

---

## Step 6 — iteration loop

```bash
git pull
xcodegen generate   # if project.yml or the file list changed
⌘U
```

---

## Step 7 — TestFlight (later)

Requires a paid Apple Developer account.

1. Bundle identifiers and team in `project.yml`, `xcodegen generate`.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
3. Optionally embed the watch app (uncomment the dependency) and rename
   the App Group in `Shared/SharedDefaults.swift` and the two watch
   entitlements files.
4. `Product → Archive` → **Distribute App → TestFlight & App Store**.
5. Privacy questionnaire: nothing leaves the device.
   `SoundCompass/PrivacyInfo.xcprivacy` already declares UserDefaults and
   SystemBootTime use.

---

## What still needs real-hardware validation

1. Direction accuracy across device models and the two holds (flat vs
   upright), using the trace. The band-limited ILD setting is off until
   this is done.
2. CROS passthrough with MFi hearing devices.
3. Long background sessions (battery).
4. Watch complication refresh cadence under WidgetKit's budget.
