import Foundation

/// The exponential smoother that turns per-frame `DirectionEstimate`s into
/// the direction and loudness the UI shows.
///
/// Extracted from `AudioDirectionDetector` so the live pipeline, the
/// offline `CalibrationProcessor`, and the unit tests all run the *same*
/// arithmetic — previously the calibration trace hard-coded its own blend
/// constants and diverged from what the compass actually displayed.
///
/// Semantics:
/// * A confident estimate blends into `direction` with weight
///   `directionBlend` (larger = snappier).
/// * A non-confident estimate (below the noise floor, or a muted frame)
///   decays `direction` toward center by `idleDecay` per frame so the
///   arrow settles instead of freezing on the last value.
/// * `magnitude` always blends toward the incoming loudness, confident or
///   not, so the loudness bar follows silence too.
struct DirectionSmoother: Equatable {

    private(set) var direction: Double = 0
    private(set) var magnitude: Double = 0

    /// Per-frame multiplier applied to `direction` when no confident
    /// estimate arrives. `0.9` reaches ~10% of the starting value after
    /// 22 frames (about one second at the ~23 Hz DSP rate).
    var idleDecay: Double = 0.9

    init(direction: Double = 0, magnitude: Double = 0, idleDecay: Double = 0.9) {
        self.direction = direction
        self.magnitude = magnitude
        self.idleDecay = idleDecay
    }

    mutating func update(
        estimate: DirectionEstimate,
        directionBlend: Double,
        magnitudeBlend: Double
    ) {
        if estimate.isConfident {
            direction = direction * (1 - directionBlend) + estimate.direction * directionBlend
        } else {
            direction *= idleDecay
        }
        magnitude = magnitude * (1 - magnitudeBlend) + estimate.magnitude * magnitudeBlend
    }

    /// Mono input (or a muted frame): no direction is possible, only
    /// loudness. Decays the arrow and follows the loudness.
    mutating func updateLoudnessOnly(_ loudness: Double, magnitudeBlend: Double = 0.4) {
        direction *= idleDecay
        magnitude = magnitude * (1 - magnitudeBlend) + loudness * magnitudeBlend
    }

    mutating func reset() {
        direction = 0
        magnitude = 0
    }
}
