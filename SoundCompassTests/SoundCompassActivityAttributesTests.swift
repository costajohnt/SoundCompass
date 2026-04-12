import ActivityKit
import XCTest
@testable import SoundCompass

final class SoundCompassActivityAttributesTests: XCTestCase {

    func testContentStateEquality() {
        let a = SoundCompassActivityAttributes.ContentState(
            direction: 0.5,
            magnitude: 0.3,
            label: "Right",
            classifierLabel: "Car horn"
        )
        let b = SoundCompassActivityAttributes.ContentState(
            direction: 0.5,
            magnitude: 0.3,
            label: "Right",
            classifierLabel: "Car horn"
        )
        XCTAssertEqual(a, b)
    }

    func testContentStateCodableRoundTrip() throws {
        let original = SoundCompassActivityAttributes.ContentState(
            direction: -0.42,
            magnitude: 0.81,
            label: "Left",
            classifierLabel: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            SoundCompassActivityAttributes.ContentState.self,
            from: data
        )
        XCTAssertEqual(decoded, original)
    }

    func testAttributesCarryTitle() {
        let attrs = SoundCompassActivityAttributes(title: "SoundCompass")
        XCTAssertEqual(attrs.title, "SoundCompass")
    }
}
