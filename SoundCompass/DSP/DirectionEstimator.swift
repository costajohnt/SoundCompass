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
}

/// Pure-Swift direction estimator that fuses interaural level and time
/// difference cues into a single direction value in `[-1, 1]`.
///
/// `DirectionEstimator` has no dependency on AVFoundation so it can be
/// exercised from unit tests with synthetic buffers.
final class DirectionEstimator {

    /// Maximum lag, in samples, searched for the interaural time difference.
    /// At 48 kHz the physical ITD between the iPhone's top and bottom mics
    /// is only a handful of samples, but we search a wider window to remain
    /// robust to sensor noise and multi-path.
    let maxLagSamples: Int

    /// Sample rate of the incoming audio.
    let sampleRate: Double

    /// Total RMS (left + right) below which direction is clamped to 0.
    let noiseFloor: Float

    /// Frame count the estimator was initialised for. Buffers passed to
    /// `estimate(...)` must not exceed this.
    let frameCount: Int

    private let gccPhat: GCCPHAT

    init(
        sampleRate: Double,
        maxLagSamples: Int = 48,
        noiseFloor: Float = 0.003,
        frameCount: Int = 2048
    ) {
        self.sampleRate = sampleRate
        self.maxLagSamples = maxLagSamples
        self.noiseFloor = noiseFloor
        self.frameCount = frameCount
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

        // Interaural level difference in [-1, 1] (negative = left louder).
        let ild = Double((rightRms - leftRms) / combined)

        // Interaural time difference via GCC-PHAT. Positive lag means the
        // left channel led in time → sound is on the left → direction < 0.
        let (lag, _) = gccPhat.estimateLag(
            left: left,
            right: right,
            frameCount: frameCount,
            maxLag: maxLagSamples
        )
        let itd = -Double(lag) / Double(maxLagSamples)

        // Weighted blend. ITD is more reliable for broadband transients so
        // it gets the larger share; ILD picks up steady-state sounds that
        // have poor correlation peaks.
        let raw = ild * 0.4 + itd * 0.6
        let clamped = max(-1.0, min(1.0, raw))

        return DirectionEstimate(direction: clamped, magnitude: loudness, combinedRms: Double(combined), isConfident: true)
    }
}
