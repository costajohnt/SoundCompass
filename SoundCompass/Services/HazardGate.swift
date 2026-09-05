import Foundation

/// Edge-triggered hazard state machine, extracted from
/// `AudioDirectionDetector` so it can be unit-tested.
///
/// A hazard *sound* is whatever the classifier currently labels as one
/// (see `HazardClassifier`). The gate turns that per-frame boolean into
/// a banner state with hysteresis: it rises immediately, and it falls
/// only when the sound has faded (`magnitude < clearBelow`) or the
/// classifier no longer reports a hazard label at all. Because
/// `SoundClassifier` now expires stale labels, "no longer reports" is
/// reachable, which is what stops a siren from re-arming the banner for
/// every later loud sound.
struct HazardGate: Equatable {

    enum Transition: Equatable {
        /// Nothing changed.
        case none
        /// A hazard just started — fire haptics, log, notify.
        case began
        /// The banner should come down.
        case ended
    }

    private(set) var isActive = false

    /// Loudness below which an active hazard is considered over.
    var clearBelow: Double = 0.15

    init(clearBelow: Double = 0.15) {
        self.clearBelow = clearBelow
    }

    mutating func update(isHazardSound: Bool, magnitude: Double) -> Transition {
        switch (isActive, isHazardSound) {
        case (false, true):
            isActive = true
            return .began
        case (true, true):
            return magnitude < clearBelow ? end() : .none
        case (true, false):
            return end()
        case (false, false):
            return .none
        }
    }

    mutating func reset() {
        isActive = false
    }

    private mutating func end() -> Transition {
        isActive = false
        return .ended
    }
}
