import Foundation

/// A snapshot of the direction + loudness + label that the iOS app streams
/// to the Watch companion over WatchConnectivity.
///
/// Represented as a plain struct for type-safety in Swift code, with
/// `toDictionary()` / `init?(dictionary:)` helpers that round-trip through
/// the `[String: Any]` payload shape that `WCSession` expects.
struct DirectionUpdate: Equatable {
    var direction: Double
    var magnitude: Double
    var label: String?
    var timestamp: Date
    /// `true` while the phone's hazard banner is up, so the watch can
    /// escalate its haptic. Optional in the payload for compatibility
    /// with older phone builds.
    var isHazard: Bool

    init(
        direction: Double,
        magnitude: Double,
        label: String?,
        timestamp: Date = Date(),
        isHazard: Bool = false
    ) {
        self.direction = direction
        self.magnitude = magnitude
        self.label = label
        self.timestamp = timestamp
        self.isHazard = isHazard
    }

    // MARK: - Dictionary bridging

    private enum Key {
        static let direction = "direction"
        static let magnitude = "magnitude"
        static let label = "label"
        static let timestamp = "timestamp"
        static let isHazard = "hazard"
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            Key.direction: direction,
            Key.magnitude: magnitude,
            Key.timestamp: timestamp.timeIntervalSince1970,
        ]
        if let label { dict[Key.label] = label }
        if isHazard { dict[Key.isHazard] = true }
        return dict
    }

    init?(dictionary: [String: Any]) {
        guard
            let direction = dictionary[Key.direction] as? Double,
            let magnitude = dictionary[Key.magnitude] as? Double,
            let ts = dictionary[Key.timestamp] as? TimeInterval
        else {
            return nil
        }
        self.direction = direction
        self.magnitude = magnitude
        self.label = dictionary[Key.label] as? String
        self.timestamp = Date(timeIntervalSince1970: ts)
        self.isHazard = dictionary[Key.isHazard] as? Bool ?? false
    }
}
