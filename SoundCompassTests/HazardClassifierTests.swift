import XCTest
@testable import SoundCompass

final class HazardClassifierTests: XCTestCase {

    func testKnownHazardsAreFlagged() {
        let hazards = [
            "siren", "fire_alarm", "smoke_alarm", "car_horn",
            "air_horn", "gunshot", "alarm", "reversing_beep",
        ]
        for id in hazards {
            XCTAssertTrue(
                HazardClassifier.isHazard(identifier: id),
                "expected \(id) to be flagged as hazard"
            )
        }
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
}
