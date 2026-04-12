import Foundation

/// A lightweight lookup over Apple's built-in `SNClassifySoundRequest`
/// identifiers. Some sounds are *safety critical* — sirens, alarms,
/// reversing beeps — and the app should react to those immediately
/// (bypassing the usual exponential smoother) and escalate the feedback
/// (louder haptic, spoken alert that doesn't obey the normal
/// rate-limit). Everything else gets the normal path.
///
/// `isHazard(identifier:)` is a pure function so it's trivial to unit
/// test and to expand as we learn which classifier labels the user
/// community actually encounters.
enum HazardClassifier {

    /// Identifiers that should trigger the hazard path. These are the
    /// raw strings emitted by `.version1` — underscores not spaces.
    static let hazardIdentifiers: Set<String> = [
        "siren",
        "emergency_vehicle",
        "fire_alarm",
        "smoke_detector_fire_alarm",
        "smoke_alarm",
        "carbon_monoxide_detector",
        "vehicle_horn_car_horn_honking",
        "vehicle_horn",
        "car_horn",
        "truck_horn",
        "train_horn",
        "air_horn",
        "alarm",
        "alarm_clock",
        "doorbell",
        "glass_breaking",
        "explosion",
        "gunshot_gunfire",
        "gunshot",
        "backing_up_beep",
        "reversing_beep",
        "police_car_siren",
    ]

    /// Returns `true` when the classifier identifier matches a known
    /// hazard sound.
    static func isHazard(identifier: String?) -> Bool {
        guard let identifier, !identifier.isEmpty else { return false }
        return hazardIdentifiers.contains(identifier.lowercased())
    }

    /// A friendly label for the banner.
    static func friendlyLabel(identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
