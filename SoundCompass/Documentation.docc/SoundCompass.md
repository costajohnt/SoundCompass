# ``SoundCompass``

A single-sided deafness assistant that estimates where nearby sounds are
coming from and surfaces the result visually, haptically, and by voice.

## Overview

SoundCompass is aimed at users with single-sided deafness (SSD), a condition
that removes the binaural cues the brain relies on to localize sound. The
app uses the iPhone's built-in multi-microphone array to reconstruct those
cues with classical signal processing, fuses them with device motion to
resolve the front/back ambiguity inherent to a two-microphone array, and
presents a live direction on screen and on an optional Apple Watch.

The implementation is intentionally boring: no machine learning for the
direction estimate, no proprietary models, no server round-trips. Everything
runs on device, in real time, using published Accelerate and CoreMotion APIs.

## Topics

### The DSP pipeline

- <doc:DSPPipeline>
- ``DirectionEstimator``
- ``GCCPHAT``
- ``SubbandDirectionEstimator``
- ``BiquadBandpass``

### Motion fusion

- ``FrontBackResolver``

### Audio orchestration

- ``AudioDirectionDetector``
- ``SoundClassifier``
- ``SpeechAnnouncer``
- ``WatchSessionManager``

### Configuration

- ``SettingsStore``

### Views

- ``ContentView``
- ``CompassView``
- ``OnboardingSheet``
- ``SettingsSheet``
- ``DebugStatsView``
