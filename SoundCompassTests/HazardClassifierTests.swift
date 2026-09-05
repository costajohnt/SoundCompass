import SoundAnalysis
import XCTest
@testable import SoundCompass

final class HazardClassifierTests: XCTestCase {

    func testKnownHazardsAreFlagged() {
        let hazards = [
            "siren", "fire_alarm", "smoke_alarm", "car_horn",
            "air_horn", "gunshot", "alarm", "reversing_beeps",
        ]
        for id in hazards {
            XCTAssertTrue(
                HazardClassifier.isHazard(identifier: id),
                "expected \(id) to be flagged as hazard"
            )
        }
    }

    func testKeywordRulesCatchSpecificVariants() {
        for id in ["police_siren", "ambulance_siren", "car_alarm", "smoke_detector", "backing_up_beeper", "emergency_vehicle"] {
            XCTAssertTrue(HazardClassifier.isHazard(identifier: id), "expected \(id) to match a keyword rule")
        }
    }

    func testMusicalHornsAreExcluded() {
        XCTAssertFalse(HazardClassifier.isHazard(identifier: "french_horn"))
        XCTAssertFalse(HazardClassifier.isHazard(identifier: "english_horn"))
    }

    func testCasingIsIgnored() {
        XCTAssertTrue(HazardClassifier.isHazard(identifier: "SIREN"))
        XCTAssertTrue(HazardClassifier.isHazard(identifier: "Car_Horn"))
    }

    func testBenignSoundsAreNotHazards() {
        let benign = ["speech", "cat", "dog_bark", "applause", "laughter", "music"]
        for id in benign {
            XCTAssertFalse(
                HazardClassifier.isHazard(identifier: id),
                "did not expect \(id) to be flagged as hazard"
            )
        }
    }

    func testNilAndEmptyAreNotHazards() {
        XCTAssertFalse(HazardClassifier.isHazard(identifier: nil))
        XCTAssertFalse(HazardClassifier.isHazard(identifier: ""))
    }

    func testFriendlyLabelHumanizes() {
        XCTAssertEqual(HazardClassifier.friendlyLabel(identifier: "car_horn"), "Car Horn")
        XCTAssertEqual(HazardClassifier.friendlyLabel(identifier: "smoke_alarm"), "Smoke Alarm")
    }

    // MARK: - Against the real model

    /// Every curated identifier must be one Apple's built-in classifier
    /// actually emits; otherwise it is dead weight that looks like
    /// coverage. Skips if the model is unavailable on this simulator.
    func testCuratedIdentifiersExistInBuiltInClassifier() throws {
        let known = try knownClassifications()
        let unknown = HazardClassifier.hazardIdentifiers.filter { !known.contains($0) }.sorted()
        XCTAssertTrue(
            unknown.isEmpty,
            "Curated hazard identifiers not emitted by SNClassifierIdentifier.version1: \(unknown)"
        )
    }

    /// The keyword rules must actually reach the model's hazard classes,
    /// and must not sweep in obvious non-hazards. The failure message
    /// prints the matched set so the list can be reviewed from CI logs.
    func testKeywordRulesMatchRealHazardClasses() throws {
        let known = try knownClassifications()
        let matched = known.filter { HazardClassifier.isHazard(identifier: $0) }.sorted()
        XCTAssertTrue(matched.contains("siren"), "expected 'siren' in matched set: \(matched)")
        XCTAssertGreaterThanOrEqual(matched.count, 5, "expected several hazard classes, got: \(matched)")
        for instrument in ["french_horn", "english_horn"] where known.contains(instrument) {
            XCTAssertFalse(matched.contains(instrument), "\(instrument) must not be a hazard: \(matched)")
        }
        let benign = ["speech", "music", "laughter", "applause", "dog_bark"]
        for id in benign where known.contains(id) {
            XCTAssertFalse(matched.contains(id), "\(id) must not be a hazard")
        }
    }

    private func knownClassifications() throws -> Set<String> {
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let known = Set(request.knownClassifications)
            if known.isEmpty {
                throw XCTSkip("Built-in classifier reports no classifications on this simulator")
            }
            return known
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            throw XCTSkip("Built-in classifier unavailable: \(error)")
        }
    }
}
