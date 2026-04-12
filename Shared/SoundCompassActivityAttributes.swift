import ActivityKit
import Foundation

/// Shared `ActivityAttributes` definition used by the iOS app (to start
/// and update the Live Activity) and the `SoundCompassWidgets` extension
/// (to render it). Lives in `Shared/` so both targets compile against
/// the exact same type.
///
/// The attributes themselves are static per-activity (just the bundle
/// display name) and the changing state lives in `ContentState`. The
/// iOS app calls `Activity.update(_:)` whenever the smoothed direction
/// or loudness changes significantly.
struct SoundCompassActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Normalized lateral direction in `[-1, 1]`.
        public var direction: Double
        /// Normalized loudness in `[0, 1]`.
        public var magnitude: Double
        /// Human-friendly direction label ("Left", "Right", …).
        public var label: String
        /// Optional classifier guess ("Speech", "Car horn", …).
        public var classifierLabel: String?

        public init(
            direction: Double,
            magnitude: Double,
            label: String,
            classifierLabel: String?
        ) {
            self.direction = direction
            self.magnitude = magnitude
            self.label = label
            self.classifierLabel = classifierLabel
        }
    }

    public var title: String

    public init(title: String) {
        self.title = title
    }
}
