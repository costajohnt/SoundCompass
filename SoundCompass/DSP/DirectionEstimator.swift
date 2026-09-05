import Accelerate
import Foundation

/// A single-shot direction estimate produced by `DirectionEstimator`.
struct DirectionEstimate: Equatable {
    /// Normalized lateral direction in `[-1, 1]`. `-1` is hard left, `0` is
    /// straight ahead, `+1` is hard right.
    var direction: Double

    /// Normalized loudness in `[0, 1]`.
    var magnitude: Double

    /// Raw combined RMS (left + right) before the `* 8` scaling and `[0, 1]`
    /// clamp. Used by `SubbandDirectionEstimator` for inter-band loudness
    /// comparison where clamping would make all loud bands look equal.
    var combinedRms: Double

    /// `true` when the input was above the noise floor and the estimate is
    /// worth trusting; `false` otherwise (direction will be zero).
    var isConfident: Bool

    /// Raw debug values for diagnostic display.
    var rawILD: Double = 0
    var rawITD: Double = 0
    var lagSamples: Int = 0
    var leftRms: Double = 0
    var rightRms: Double = 0

    /// How much the GCC-PHAT lag was trusted this frame, `[0, 1]`. Low
    /// values mean the correlation peak was too weak or railed at the
    /// search-window edge, so the estimate leaned on ILD alone.
    var itdConfidence: Double = 0

    /// Per-channel RMS of the signal the ILD was actually computed from.
    /// Equal to `leftRms` / `rightRms` for a broadband estimator; the
    /// band-passed RMS when `ildBandHz` is set.
    var ildLeftRms: Double = 0
    var ildRightRms: Double = 0
}

/// Pure-Swift direction estimator that fuses interaural level and time
/// difference cues into a single direction value in `[-1, 1]`.
///
/// `DirectionEstimator` has no dependency on AVFoundation so it can be
/// exercised from unit tests with synthetic buffers. It is allocation-free
/// after `init` and must be driven from a single thread.
final class DirectionEstimator {

    /// Maximum lag, in samples, searched for the interaural time difference.
    /// Defaults to the physical limit: sound crossing the device's ~15 cm
    /// aperture takes `0.15 / 343` seconds, ≈21 samples at 48 kHz. Searching
    /// beyond that only lets reverb and noise win the correlation peak.
    let maxLagSamples: Int

    /// Sample rate of the incoming audio.
    let sampleRate: Double

    /// Total RMS (left + right) below which direction is clamped to 0.
    let noiseFloor: Float

    /// Frame count the estimator was initialised for. Buffers passed to
    /// `estimate(...)` must not exceed this; longer buffers are clamped, so
    /// callers with larger buffers should chunk them.
    let frameCount: Int

    /// Gain applied to the raw normalized level difference before the tanh
    /// squash. Apple's synthesized stereo uses shallow cardioid-like beams,
    /// so the raw `(R−L)/(R+L)` ratio is compressed well below the ±1 an
    /// ideal opposing-cardioid pair would produce; this expands it back.
    /// Device measurement (iPhone 16 Pro, 2026-06-10, broadband ILD): a
    /// hard-side source at ~1 m produces |ild| ≈ 0.08, so gain 12 maps it
    /// to ~75% deflection. Mutable so a per-device calibration can replace
    /// the default; written from the main thread, read on the DSP thread —
    /// a torn read of a `Double` is not possible on arm64, and a one-frame
    /// stale value is harmless.
    var ildGain: Double

    /// Default `ildGain` when no calibration has been stored.
    static let defaultIldGain: Double = 12.0

    /// |ild| below this is treated as zero. Ambient room noise produces
    /// |ild| ≈ 0.01–0.02 even with no directional source; without a
    /// dead-zone the high `ildGain` would turn that into visible wobble.
    static let ildDeadZone: Double = 0.01

    /// Frequency band the ILD is measured in, or `nil` for broadband.
    /// Apple's beamformer has almost no left/right directivity below
    /// ~1 kHz at the phone's aperture, so low-frequency energy contributes
    /// level with ILD ≈ 0 and dilutes the ratio. Restricting the ILD
    /// measurement to a band where the beams actually diverge is expected
    /// to raise the usable cue; loudness (`magnitude`) is always broadband.
    let ildBandHz: ClosedRange<Double>?

    /// Whether the GCC-PHAT lag is computed and fused at all. On Apple's
    /// synthesized stereo the lag sits at 0 by construction, so the
    /// per-band estimators turn it off to save three FFTs per band.
    let usesITD: Bool

    /// Normalized GCC-PHAT peak height below which the lag is treated as
    /// pure noise. A diffuse/uncorrelated input peaks around
    /// `1/sqrt(fftSize)` (~0.016 at 4096); a genuine coherent wavefront
    /// produces 0.2+. Confidence ramps linearly from this floor to
    /// `floor + 0.15`.
    private let itdPeakFloor = 0.05

    private let gccPhat: GCCPHAT?
    private let ildLeftFilter: BiquadBandLimiter?
    private let ildRightFilter: BiquadBandLimiter?
    private var ildLeftScratch: [Float]
    private var ildRightScratch: [Float]

    init(
        sampleRate: Double,
        maxLagSamples: Int? = nil,
        noiseFloor: Float = 0.003,
        frameCount: Int = 2048,
        ildGain: Double = DirectionEstimator.defaultIldGain,
        ildBandHz: ClosedRange<Double>? = nil,
        usesITD: Bool = true
    ) {
        self.sampleRate = sampleRate
        // Physical travel time across the device aperture, with headroom.
        self.maxLagSamples = maxLagSamples ?? max(4, Int((0.15 / 343.0 * sampleRate).rounded(.up)))
        self.noiseFloor = noiseFloor
        self.frameCount = frameCount
        self.ildGain = ildGain
        self.usesITD = usesITD
        self.gccPhat = usesITD ? GCCPHAT(frameCount: frameCount) : nil

        // Clamp the ILD band under Nyquist and drop it if nothing is left
        // (a 16 kHz Bluetooth route with a 1–8 kHz band keeps 1–7.2 kHz).
        if let band = ildBandHz {
            let upper = min(band.upperBound, 0.45 * sampleRate)
            if band.lowerBound > 0, upper > band.lowerBound * 1.2 {
                let usable = band.lowerBound...upper
                self.ildBandHz = usable
                self.ildLeftFilter = BiquadBandLimiter(sampleRate: sampleRate, lowHz: usable.lowerBound, highHz: usable.upperBound)
                self.ildRightFilter = BiquadBandLimiter(sampleRate: sampleRate, lowHz: usable.lowerBound, highHz: usable.upperBound)
                self.ildLeftScratch = [Float](repeating: 0, count: frameCount)
                self.ildRightScratch = [Float](repeating: 0, count: frameCount)
            } else {
                self.ildBandHz = nil
                self.ildLeftFilter = nil
                self.ildRightFilter = nil
                self.ildLeftScratch = []
                self.ildRightScratch = []
            }
        } else {
            self.ildBandHz = nil
            self.ildLeftFilter = nil
            self.ildRightFilter = nil
            self.ildLeftScratch = []
            self.ildRightScratch = []
        }
    }

    /// Flush the ILD band filters' memory. Call when the stream restarts.
    func reset() {
        ildLeftFilter?.reset()
        ildRightFilter?.reset()
    }

    /// Computes a direction estimate from a single stereo buffer.
    func estimate(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) -> DirectionEstimate {
        // Clamp to configured size — installTap's bufferSize is a hint,
        // the system can deliver larger buffers.
        let frameCount = min(frameCount, self.frameCount)

        // Broadband per-channel RMS via Accelerate → loudness.
        var leftRms: Float = 0
        var rightRms: Float = 0
        vDSP_rmsqv(left,  1, &leftRms,  vDSP_Length(frameCount))
        vDSP_rmsqv(right, 1, &rightRms, vDSP_Length(frameCount))

        let combined = leftRms + rightRms
        let loudness = Double(min(combined * 8, 1.0))

        // ILD source: band-passed copies when a band is configured. The
        // filters are streaming, so run them even below the noise floor to
        // keep their state continuous.
        var ildLeft = leftRms
        var ildRight = rightRms
        if let lf = ildLeftFilter, let rf = ildRightFilter {
            ildLeftScratch.withUnsafeMutableBufferPointer { buf in
                lf.process(input: left, output: buf.baseAddress!, count: frameCount)
                vDSP_rmsqv(buf.baseAddress!, 1, &ildLeft, vDSP_Length(frameCount))
            }
            ildRightScratch.withUnsafeMutableBufferPointer { buf in
                rf.process(input: right, output: buf.baseAddress!, count: frameCount)
                vDSP_rmsqv(buf.baseAddress!, 1, &ildRight, vDSP_Length(frameCount))
            }
        }

        if combined < noiseFloor {
            return DirectionEstimate(
                direction: 0, magnitude: loudness, combinedRms: Double(combined), isConfident: false,
                leftRms: Double(leftRms), rightRms: Double(rightRms),
                ildLeftRms: Double(ildLeft), ildRightRms: Double(ildRight)
            )
        }

        // Interaural level difference. iPhone "stereo" is a synthesized
        // beamformed image (WWDC20 session 10226): for opposing cardioid-
        // like beams the normalized ratio (R−L)/(R+L) tracks sin(azimuth)
        // but compressed by how shallow Apple's beams are. tanh expands it
        // without the hard rail of a clamp.
        let ildSum = ildLeft + ildRight
        let ildRaw = ildSum > 1e-9 ? Double((ildRight - ildLeft) / ildSum) : 0
        let ildMagnitude = max(0, abs(ildRaw) - DirectionEstimator.ildDeadZone)
        let ildDirection = tanh(ildGain * ildMagnitude) * (ildRaw < 0 ? -1 : 1)

        // Interaural time difference via GCC-PHAT. Positive lag means the
        // left channel led in time → sound is on the left → direction < 0.
        var lag = 0
        var itd = 0.0
        var itdConfidence = 0.0
        if let gccPhat {
            let (bestLag, peak) = gccPhat.estimateLag(
                left: left,
                right: right,
                frameCount: frameCount,
                maxLag: maxLagSamples
            )
            lag = bestLag
            itd = max(-1.0, min(1.0, -Double(lag) / Double(maxLagSamples)))

            // Trust the lag only when the correlation peak is sharp. PHAT
            // whitening makes every bin a unit vector, so a coherent
            // wavefront sums to ≈fftSize at the true lag while diffuse input
            // stays near sqrt(fftSize). Normalizing by fftSize puts those at
            // ~1.0 vs ~0.016, with real-world signals in between. A peak
            // railed at the search-window edge is the classic signature of a
            // spurious match, so it is rejected outright.
            let peakNorm = Double(peak) / Double(gccPhat.fftSize)
            itdConfidence = max(0.0, min(1.0, (peakNorm - itdPeakFloor) / 0.15))
            if abs(lag) >= maxLagSamples {
                itdConfidence = 0
            }
        }

        // Fusion. ILD is THE direction signal on Apple's synthesized
        // stereo; device traces (iPhone 16 Pro, 2026-06-10) show the
        // GCC-PHAT lag pinned at 0 with a sharp peak for sources at any
        // azimuth, because the beamformer time-aligns the channels by
        // construction. A weighted *average* would let that confident
        // zero drag every estimate toward center, so the ITD enters as a
        // small additive correction instead: it can nudge the result when
        // a genuine inter-channel delay survives, and contributes nothing
        // when the lag is zero.
        let raw = ildDirection + 0.35 * itdConfidence * itd
        let clamped = max(-1.0, min(1.0, raw))

        return DirectionEstimate(
            direction: clamped, magnitude: loudness,
            combinedRms: Double(combined), isConfident: true,
            rawILD: ildRaw, rawITD: itd, lagSamples: lag,
            leftRms: Double(leftRms), rightRms: Double(rightRms),
            itdConfidence: itdConfidence,
            ildLeftRms: Double(ildLeft), ildRightRms: Double(ildRight)
        )
    }
}
