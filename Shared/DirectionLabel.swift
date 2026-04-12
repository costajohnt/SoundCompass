import Foundation

/// Small helper that turns a numeric direction value into a localisable
/// string label. Shared by the iOS UI, the watchOS UI, the accessibility
/// value on `CompassView`, and `SpeechAnnouncer`.
enum DirectionLabel {

    /// Short human label for a direction in `[-1, 1]`.
    static func label(for direction: Double) -> String {
        switch direction {
        case ..<(-0.66): return "Far left"
        case ..<(-0.20): return "Left"
        case ..<(0.20):  return "Straight ahead"
        case ..<(0.66):  return "Right"
        default:         return "Far right"
        }
    }

    /// Speech-friendly form used by `SpeechAnnouncer`.
    static func spokenPhrase(direction: Double) -> String {
        switch direction {
        case ..<(-0.66): return "far left"
        case ..<(-0.20): return "left"
        case ..<(0.20):  return "ahead"
        case ..<(0.66):  return "right"
        default:         return "far right"
        }
    }

    /// Accessibility value string combining direction and loudness.
    static func accessibilityValue(direction: Double, magnitude: Double) -> String {
        let bucket: String
        switch direction {
        case ..<(-0.66): bucket = "far left"
        case ..<(-0.20): bucket = "left"
        case ..<(0.20):  bucket = "ahead"
        case ..<(0.66):  bucket = "right"
        default:         bucket = "far right"
        }
        let loudness = Int((magnitude * 100).rounded())
        return "Sound \(bucket), loudness \(loudness) percent"
    }
}
