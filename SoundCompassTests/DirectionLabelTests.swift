import XCTest
@testable import SoundCompass

final class DirectionLabelTests: XCTestCase {

    func testLabelBuckets() {
        XCTAssertEqual(DirectionLabel.label(for: -1.0), "Far left")
        XCTAssertEqual(DirectionLabel.label(for: -0.7), "Far left")
        XCTAssertEqual(DirectionLabel.label(for: -0.4), "Left")
        XCTAssertEqual(DirectionLabel.label(for:  0.0), "Straight ahead")
        XCTAssertEqual(DirectionLabel.label(for:  0.4), "Right")
        XCTAssertEqual(DirectionLabel.label(for:  1.0), "Far right")
    }

    func testSpokenPhraseBuckets() {
        XCTAssertEqual(DirectionLabel.spokenPhrase(direction: -0.9), "far left")
        XCTAssertEqual(DirectionLabel.spokenPhrase(direction: -0.3), "left")
        XCTAssertEqual(DirectionLabel.spokenPhrase(direction:  0.0), "ahead")
        XCTAssertEqual(DirectionLabel.spokenPhrase(direction:  0.4), "right")
        XCTAssertEqual(DirectionLabel.spokenPhrase(direction:  0.9), "far right")
    }

    func testAccessibilityValueMentionsBothDirectionAndLoudness() {
        let value = DirectionLabel.accessibilityValue(direction: -0.8, magnitude: 0.5)
        XCTAssertTrue(value.contains("far left"))
        XCTAssertTrue(value.contains("50"))
    }
}
