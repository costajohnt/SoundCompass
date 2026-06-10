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
}

/// Pure-Swift direction estimator that fuses interaural level and time
/// difference cues into a single direction value in `[-1, 1]`.
///
/// `DirectionEstimator` has no dependency on AVFoundation so it can be
/// exercised from unit tests with synthetic buffers.
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
    /// `estimate(...)` must not exceed this.
    let frameCount: Int

    /// Gain applied to the raw normalized level difference before the tanh
    /// squash. Apple's synthesized stereo uses shallow cardioid-like beams,
    /// so the raw `(R−L)/(R+L)` ratio is compressed well below the ±1 an
    /// ideal opposing-cardioid pair would produce; this expands it back.
    let ildGain: Double

    /// Normalized GCC-PHAT peak height below which the lag is treated as
    /// pure noise. A diffuse/uncorrelated input peaks around
    /// `1/sqrt(fftSize)` (~0.016 at 4096); a genuine coherent wavefront
    /// produces 0.2+. Confidence ramps linearly from this floor to
    /// `floor + 0.15`.
    private let itdPeakFloor = 0.05

    private let gccPhat: GCCPHAT

    init(
        sampleRate: Double,
        maxLagSamples: Int? = nil,
        noiseFloor: Float = 0.003,
        frameCount: Int = 2048,
        ildGain: Double = 4.0
    ) {
        self.sampleRate = sampleRate
        // Physical travel time across the device aperture, with headroom.
        self.maxLagSamples = maxLagSamples ?? max(4, Int((0.15 / 343.0 * sampleRate).rounded(.up)))
        self.noiseFloor = noiseFloor
        self.frameCount = frameCount
        self.ildGain = ildGain
        self.gccPhat = GCCPHAT(frameCount: frameCount)
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

        // Per-channel RMS via Accelerate.
        var leftRms: Float = 0
        var rightRms: Float = 0
        vDSP_rmsqv(left,  1, &leftRms,  vDSP_Length(frameCount))
        vDSP_rmsqv(right, 1, &rightRms, vDSP_Length(frameCount))

        let combined = leftRms + rightRms
        let loudness = Double(min(combined * 8, 1.0))

        if combined < noiseFloor {
            return DirectionEstimate(direction: 0, magnitude: loudness, combinedRms: Double(combined), isConfident: false)
        }

        // Interaural level difference. iPhone "stereo" is a synthesized
        // beamformed image (WWDC20 session 10226): for opposing cardioid-
        // like beams the normalized ratio (R−L)/(R+L) tracks sin(azimuth)
        // but compressed by how shallow Apple's beams are. tanh expands it
        // without the hard rail of a clamp.
        let ildRaw = Double((rightRms - leftRms) / combined)
        let ildDirection = tanh(ildGain * ildRaw)

        // Interaural time difference via GCC-PHAT. Positive lag means the
        // left channel led in time → sound is on the left → direction < 0.
        let (lag, peak) = gccPhat.estimateLag(
            left: left,
            right: right,
            frameCount: frameCount,
            maxLag: maxLagSamples
        )
        let itd = max(-1.0, min(1.0, -Double(lag) / Double(maxLagSamples)))

        // Trust the lag only when the correlation peak is sharp. PHAT
        // whitening makes every bin a unit vector, so a coherent wavefront
        // sums to ≈fftSize at the true lag while diffuse input stays near
        // sqrt(fftSize). Normalizing by fftSize puts those at ~1.0 vs
        // ~0.016, with real-world signals in between. A peak railed at the
        // search-window edge is the classic signature of a spurious match,
        // so it is rejected outright.
        let peakNorm = Double(peak) / Double(gccPhat.fftSize)
        var itdConfidence = max(0.0, min(1.0, (peakNorm - itdPeakFloor) / 0.15))
        if abs(lag) >= maxLagSamples {
            itdConfidence = 0
        }

        // Confidence-weighted fusion. ILD carries a fixed share because the
        // synthesized stereo image is fundamentally level-encoded; ITD earns
        // its share per frame via the correlation peak instead of getting a
        // fixed cut whether or not the lag meant anything.
        let ildWeight = 0.55
        let itdWeight = 0.45 * itdConfidence
        let raw = (ildDirection * ildWeight + itd * itdWeight) / (ildWeight + itdWeight)
        let clamped = max(-1.0, min(1.0, raw))

        return DirectionEstimate(
            direction: clamped, magnitude: loudness,
            combinedRms: Double(combined), isConfident: true,
            rawILD: ildRaw, rawITD: itd, lagSamples: lag,
            leftRms: Double(leftRms), rightRms: Double(rightRms),
            itdConfidence: itdConfidence
        )
    }
}
