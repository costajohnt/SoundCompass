import Combine
import Foundation
import SwiftUI

/// User-facing configuration for SoundCompass. Backed by `UserDefaults`
/// through `@AppStorage` so values survive across launches with no extra
/// persistence code.
///
/// `SettingsStore` is an `ObservableObject` so the SwiftUI settings sheet
/// can bind directly to its properties, and so `AudioDirectionDetector`
/// can subscribe via Combine to the settings that affect DSP behavior.
final class SettingsStore: ObservableObject {

    // MARK: - Enumerations

    enum Sensitivity: String, CaseIterable, Identifiable {
        case low
        case medium
        case high

        var id: String { rawValue }

        var label: String {
            switch self {
            case .low:    return "Calm"
            case .medium: return "Balanced"
            case .high:   return "Snappy"
            }
        }

        var description: String {
            switch self {
            case .low:
                return "Smoothest, slowest to react. Good for background monitoring."
            case .medium:
                return "Default balance between responsiveness and stability."
            case .high:
                return "Jumps to new directions immediately. Good for brief, loud sounds."
            }
        }

        /// Weight of the new sample when blending into the smoothed value.
        /// Larger = more responsive / less smoothed.
        var directionBlend: Double {
            switch self {
            case .low:    return 0.15
            case .medium: return 0.25
            case .high:   return 0.45
            }
        }

        /// Same idea for magnitude.
        var magnitudeBlend: Double {
            switch self {
            case .low:    return 0.30
            case .medium: return 0.40
            case .high:   return 0.60
            }
        }
    }

    /// Which ear the user hears with. Drives the haptic arm and the
    /// future passthrough panner. `.unspecified` means the user hasn't
    /// chosen yet; the UI treats that as symmetrical behavior.
    enum HearingEar: String, CaseIterable, Identifiable {
        case unspecified
        case left
        case right

        var id: String { rawValue }

        var label: String {
            switch self {
            case .unspecified: return "Not specified"
            case .left:        return "Left"
            case .right:       return "Right"
            }
        }
    }

    /// Color scheme override. The app's visual design is dark-theme
    /// first, but `.system` lets users who prefer light mode override.
    enum Theme: String, CaseIterable, Identifiable {
        case system
        case dark
        case light

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .dark:   return "Dark"
            case .light:  return "Light"
            }
        }
    }

    enum HapticStrength: String, CaseIterable, Identifiable {
        case off
        case light
        case strong

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off:    return "Off"
            case .light:  return "Light"
            case .strong: return "Strong"
            }
        }

        /// Floor intensity (0…1) passed to `CHHapticEvent`.
        var intensity: Float {
            switch self {
            case .off:    return 0
            case .light:  return 0.45
            case .strong: return 1.0
            }
        }
    }

    // MARK: - Published state

    @Published var sensitivity: Sensitivity {
        didSet { defaults.set(sensitivity.rawValue, forKey: Keys.sensitivity) }
    }

    @Published var hapticStrength: HapticStrength {
        didSet { defaults.set(hapticStrength.rawValue, forKey: Keys.haptics) }
    }

    @Published var speechEnabled: Bool {
        didSet { defaults.set(speechEnabled, forKey: Keys.speech) }
    }

    @Published var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Keys.speechRate) }
    }

    @Published var showDebugStats: Bool {
        didSet { defaults.set(showDebugStats, forKey: Keys.debug) }
    }

    @Published var hearingEar: HearingEar {
        didSet { defaults.set(hearingEar.rawValue, forKey: Keys.hearingEar) }
    }

    @Published var hazardAlerts: Bool {
        didSet { defaults.set(hazardAlerts, forKey: Keys.hazardAlerts) }
    }

    @Published var speechVoiceIdentifier: String? {
        didSet { defaults.set(speechVoiceIdentifier, forKey: Keys.voice) }
    }

    @Published var passthroughEnabled: Bool {
        didSet { defaults.set(passthroughEnabled, forKey: Keys.passthrough) }
    }

    @Published var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sensitivity = Sensitivity(
            rawValue: defaults.string(forKey: Keys.sensitivity) ?? Sensitivity.medium.rawValue
        ) ?? .medium
        self.hapticStrength = HapticStrength(
            rawValue: defaults.string(forKey: Keys.haptics) ?? HapticStrength.light.rawValue
        ) ?? .light
        self.speechEnabled = defaults.bool(forKey: Keys.speech)
        let storedRate = defaults.double(forKey: Keys.speechRate)
        self.speechRate = storedRate == 0 ? 1.0 : storedRate
        self.showDebugStats = defaults.bool(forKey: Keys.debug)
        self.hearingEar = HearingEar(
            rawValue: defaults.string(forKey: Keys.hearingEar) ?? HearingEar.unspecified.rawValue
        ) ?? .unspecified
        // Hazard alerts default to ON — they're safety-critical, and the
        // user can turn them off in settings if they find them too jumpy.
        if defaults.object(forKey: Keys.hazardAlerts) == nil {
            self.hazardAlerts = true
        } else {
            self.hazardAlerts = defaults.bool(forKey: Keys.hazardAlerts)
        }
        self.speechVoiceIdentifier = defaults.string(forKey: Keys.voice)
        self.passthroughEnabled = defaults.bool(forKey: Keys.passthrough)
        self.theme = Theme(
            rawValue: defaults.string(forKey: Keys.theme) ?? Theme.dark.rawValue
        ) ?? .dark
    }

    // MARK: - Keys

    private enum Keys {
        static let sensitivity  = "soundcompass.settings.sensitivity"
        static let haptics      = "soundcompass.settings.haptics"
        static let speech       = "soundcompass.settings.speech"
        static let speechRate   = "soundcompass.settings.speechRate"
        static let debug        = "soundcompass.settings.debug"
        static let hearingEar   = "soundcompass.settings.hearingEar"
        static let hazardAlerts = "soundcompass.settings.hazardAlerts"
        static let voice        = "soundcompass.settings.voice"
        static let passthrough  = "soundcompass.settings.passthrough"
        static let theme        = "soundcompass.settings.theme"
    }
}
