import XCTest
@testable import SoundCompass

final class DirectionUpdateTests: XCTestCase {

    func testRoundTripPreservesValues() {
        let original = DirectionUpdate(
            direction: -0.42,
            magnitude: 0.67,
            label: "Car horn",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let dict = original.toDictionary()
        let decoded = DirectionUpdate(dictionary: dict)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.direction, original.direction)
        XCTAssertEqual(decoded?.magnitude, original.magnitude)
        XCTAssertEqual(decoded?.label, original.label)
        XCTAssertEqual(
            decoded?.timestamp.timeIntervalSince1970 ?? 0,
            original.timestamp.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testRoundTripWithoutLabel() {
        let original = DirectionUpdate(direction: 0.3, magnitude: 0.5, label: nil)
        let decoded = DirectionUpdate(dictionary: original.toDictionary())
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.label)
    }

    func testMalformedDictionaryReturnsNil() {
        XCTAssertNil(DirectionUpdate(dictionary: [:]))
        XCTAssertNil(DirectionUpdate(dictionary: ["direction": 0.0]))
        XCTAssertNil(DirectionUpdate(dictionary: ["direction": 0.0, "magnitude": 0.0]))
    }
}
