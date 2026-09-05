import Foundation

/// Small helper that turns a numeric direction value into a localised
/// string label. Shared by the iOS UI, the watchOS UI, the accessibility
/// value on `CompassView`, and `SpeechAnnouncer`.
///
/// The strings are looked up through `String(localized:)` so that views
/// which receive them as `String` values (and would otherwise render them
/// verbatim) still get the user's language.
enum DirectionLabel {

    /// Short human label for a direction in `[-1, 1]`.
    static func label(for direction: Double) -> String {
        switch direction {
        case ..<(-0.66): return String(localized: "Far left")
        case ..<(-0.20): return String(localized: "Left")
        case ..<(0.20):  return String(localized: "Straight ahead")
        case ..<(0.66):  return String(localized: "Right")
        default:         return String(localized: "Far right")
        }
    }

    /// Speech-friendly form used by `SpeechAnnouncer`.
    static func spokenPhrase(direction: Double) -> String {
        switch direction {
        case ..<(-0.66): return String(localized: "far left")
        case ..<(-0.20): return String(localized: "left")
        case ..<(0.20):  return String(localized: "ahead")
        case ..<(0.66):  return String(localized: "right")
        default:         return String(localized: "far right")
        }
    }

    /// Accessibility value string combining direction and loudness.
    static func accessibilityValue(direction: Double, magnitude: Double) -> String {
        let bucket = spokenPhrase(direction: direction)
        let loudness = Int((magnitude * 100).rounded())
        return String(localized: "Sound \(bucket), loudness \(loudness) percent")
    }
}
