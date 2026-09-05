import Foundation

/// A lookup over Apple's built-in `SNClassifySoundRequest` identifiers.
/// Some sounds are *safety critical* — sirens, alarms, horns, reversing
/// beeps — and the app should react to those immediately (bypassing the
/// usual exponential smoother) and escalate the feedback. Everything
/// else gets the normal path.
///
/// Matching is two-layered:
///
/// 1. A curated set of exact `version1` identifiers.
/// 2. Keyword rules over the identifier, so the many specific classes
///    Apple ships (`police_siren`, `ambulance_siren`, `car_alarm`, …)
///    are caught without listing every one, and so a renamed identifier
///    in a future model version does not silently drop a hazard.
///
/// `HazardClassifierTests` validates the curated set against
/// `SNClassifySoundRequest.knownClassifications` on the simulator, so an
/// identifier that Apple does not actually emit fails CI instead of
/// sitting dead in the list.
enum HazardClassifier {

    /// Exact `version1` identifiers that should trigger the hazard path.
    /// Every entry here is confirmed against `knownClassifications` by
    /// `HazardClassifierTests` (CI run 33980885237 showed the model has
    /// no `fire_alarm`, `car_alarm`, `doorbell`, `explosion` or
    /// `reversing_beeps` classes, so those live only in the keyword rules
    /// in case a future model version adds them).
    static let hazardIdentifiers: Set<String> = [
        "siren",
        "civil_defense_siren",
        "police_siren",
        "ambulance_siren",
        "fire_engine_siren",
        "emergency_vehicle",
        "car_horn",
        "air_horn",
        "train_horn",
        "alarm_clock",
        "smoke_detector",
        "glass_breaking",
        "gunshot_gunfire",
    ]

    /// Substrings that mark an identifier as a hazard.
    static let hazardKeywords: [String] = [
        "siren",
        "alarm",
        "horn",
        "gunshot",
        "gunfire",
        "explosion",
        "glass_break",
        "reversing",
        "backing_up",
        "smoke_detector",
        "emergency",
    ]

    /// Identifiers that contain a keyword but are not hazards — musical
    /// instruments, mostly.
    static let keywordExclusions: Set<String> = [
        "french_horn",
        "english_horn",
        "horn_section",
        "shofar",
    ]

    /// Returns `true` when the classifier identifier matches a known
    /// hazard sound.
    static func isHazard(identifier: String?) -> Bool {
        guard let identifier, !identifier.isEmpty else { return false }
        let id = identifier.lowercased()
        if hazardIdentifiers.contains(id) { return true }
        if keywordExclusions.contains(id) { return false }
        return hazardKeywords.contains { id.contains($0) }
    }

    /// A friendly label for the banner.
    static func friendlyLabel(identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
