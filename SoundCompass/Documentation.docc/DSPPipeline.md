# The DSP pipeline

How SoundCompass turns two channels of microphone audio into a live
direction estimate that a single-sided deaf user can actually trust.

## The problem

Single-sided deafness removes the two cues the brain normally uses to
localize sound:

- **Interaural level difference (ILD).** The ear closer to the source hears
  it slightly louder.
- **Interaural time difference (ITD).** The closer ear hears it a fraction
  of a millisecond earlier.

An SSD user's working ear still picks up both cues, but without a second
reference the brain cannot triangulate them into a direction. SoundCompass
reconstructs the two cues from the phone's microphones, then surfaces them
as a visual compass, a haptic tick, and optional spoken callouts.

## Capture

iPhone stereo capture is a **synthesized image**, not two raw microphones:
the system records from all built-in mics simultaneously and beamforms a
binaural-style stereo pair (WWDC20 session 10226). ``AudioDirectionDetector``
configures an `AVAudioSession` with `.playAndRecord`, picks the built-in
mic explicitly (so a paired Bluetooth headset doesn't mask it), and
switches a data source to the `.stereo` polar pattern.

Crucially, the **front and back data sources deliver mirrored left/right**
relative to each other. The detector prefers the **back** source — its
left/right match the user's when the phone is held flat, screen up, top
edge pointing away — and if it has to fall back to the front source it
flips the sign of every direction estimate. The subsequent `AVAudioEngine`
tap delivers 2-channel float buffers of roughly 2048 frames each.

## Broadband direction estimation

``DirectionEstimator`` is called once per buffer and fuses two cues:

1. **ILD** via `vDSP_rmsqv`, per channel. The normalized difference
   `(R − L) / (R + L)` lives in `[-1, 1]` but is compressed by the shallow
   beam patterns of Apple's synthesized stereo, so it is expanded through
   `tanh(ildGain · ild)` before fusion.
2. **ITD** via ``GCCPHAT``, which computes the cross-spectrum
   `R · conj(L)`, whitens every bin with the PHAT weight
   `X[k] /= |X[k]|`, inverse-FFTs the result, and picks the lag that
   maximises the correlation peak inside the physically possible window
   (≈21 samples at 48 kHz for a 15 cm aperture).

Because the stereo image is level-encoded by construction, the ILD always
carries a 55% share of the blend. The ITD earns up to the remaining 45%
per frame, scaled by the normalized height of its correlation peak: a
coherent broadband wavefront gets full weight, a diffuse field or a peak
railed at the search-window edge gets none. The fused value is clamped to
`[-1, 1]` and smoothed with an exponential filter whose α is driven by
``SettingsStore/Sensitivity``.

### Why PHAT?

Plain cross-correlation picks up every strong frequency component in the
signal, so in reverberant rooms the peak wanders. The PHAT weight whitens
the cross-spectrum before the inverse FFT, making the correlation peak
sharp and reverberation-tolerant. The trade-off is worse performance on
narrow-band signals — a pure tone has almost no spectral content to
whiten — but for the broadband environmental sounds SoundCompass cares
about (speech, traffic, alarms), PHAT wins cleanly.

### Conventions

Positive lag out of ``GCCPHAT/estimateLag(left:right:frameCount:maxLag:)``
means the **left** channel leads in time. Negative lag means the right
channel leads. ``DirectionEstimator`` flips the sign when normalising the
ITD so that the app-wide convention `-1 = hard left, +1 = hard right`
holds for every published value.

## Per-frequency bands

``SubbandDirectionEstimator`` runs an independent ``DirectionEstimator``
inside each of several octave-ish bands carved out by streaming
``BiquadBandpass`` filters (RBJ cookbook coefficients, transposed direct
form II). The default bands are:

| Name   | Range         | Typical content                  |
|--------|---------------|----------------------------------|
| Low    | 100–500 Hz    | Traffic rumble, HVAC, voice F0   |
| Speech | 500–3000 Hz   | Voiced speech fundamentals       |
| Alert  | 3000–8000 Hz  | Sirens, alarm beeps, hissing     |
| High   | 8000–16000 Hz | Sibilants, bird calls, breakage  |

The UI highlights whichever band has the loudest magnitude so the user can
see at a glance "that siren on my right is in the Alert band, separate from
the speech on my left."

## Front / back disambiguation

A two-microphone array physically cannot distinguish `θ = 30°` from
`θ = 150°` — both produce the same `sin(θ)`. ``FrontBackResolver`` fixes
this by fusing direction samples with device motion.

The resolver subscribes to `CMDeviceMotion` at 50 Hz, unwraps yaw so it's
continuous past the ±π wrap point, and keeps a sliding window of
`(yaw, direction)` samples. When the user rotates the phone:

- A source **in front** shifts left in the device frame as yaw grows, so
  `direction` decreases: `∂direction / ∂yaw < 0`.
- A source **behind** shifts in the mirrored direction, producing a
  positive slope.

Once the user has rotated at least 15° and the regression slope exceeds a
confidence threshold, the resolver commits to ``FrontBackResolver/Resolution/front`` or
``FrontBackResolver/Resolution/back``. While the window is short, it emits
``FrontBackResolver/Resolution/needsRotation(accumulatedDegrees:)`` so the
UI can prompt the user to keep moving.

## Classification

``SoundClassifier`` wraps Apple's built-in
`SNClassifySoundRequest(classifierIdentifier: .version1)` so SoundCompass
can tag the loudest nearby sound ("car horn", "speech", "dog bark") without
shipping a custom CoreML model. The classifier runs on a dedicated serial
queue so its mutable `SNAudioStreamAnalyzer` never races with the tap
thread or with main-thread reset calls.

## Smoothing vs. responsiveness

All of the blending constants, the haptic strength, and the speech-rate
multiplier are driven by ``SettingsStore``. The three sensitivity presets
("Calm", "Balanced", "Snappy") correspond to different α values in the
exponential smoother; the user picks their trade-off between stability and
responsiveness.
