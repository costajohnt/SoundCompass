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

    init(
        direction: Double,
        magnitude: Double,
        label: String?,
        timestamp: Date = Date()
    ) {
        self.direction = direction
        self.magnitude = magnitude
        self.label = label
        self.timestamp = timestamp
    }

    // MARK: - Dictionary bridging

    private enum Key {
        static let direction = "direction"
        static let magnitude = "magnitude"
        static let label = "label"
        static let timestamp = "timestamp"
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            Key.direction: direction,
            Key.magnitude: magnitude,
            Key.timestamp: timestamp.timeIntervalSince1970,
        ]
        if let label { dict[Key.label] = label }
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
    }
}
