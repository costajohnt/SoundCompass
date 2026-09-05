import XCTest
@testable import SoundCompass

final class HazardGateTests: XCTestCase {

    func testRisingEdgeFiresOnce() {
        var gate = HazardGate()
        XCTAssertEqual(gate.update(isHazardSound: true, magnitude: 0.8), .began)
        XCTAssertEqual(gate.update(isHazardSound: true, magnitude: 0.8), .none)
        XCTAssertTrue(gate.isActive)
    }

    func testEndsWhenSoundFades() {
        var gate = HazardGate(clearBelow: 0.15)
        _ = gate.update(isHazardSound: true, magnitude: 0.8)
        XCTAssertEqual(gate.update(isHazardSound: true, magnitude: 0.1), .ended)
        XCTAssertFalse(gate.isActive)
    }

    func testEndsWhenLabelGoesAway() {
        var gate = HazardGate()
        _ = gate.update(isHazardSound: true, magnitude: 0.8)
        XCTAssertEqual(gate.update(isHazardSound: false, magnitude: 0.8), .ended)
    }

    func testDoesNotReArmOnLoudNonHazard() {
        // The bug this guards: after a siren faded, a stale label used to
        // re-fire the banner on the next loud sound of any kind.
        var gate = HazardGate()
        _ = gate.update(isHazardSound: true, magnitude: 0.8)
        _ = gate.update(isHazardSound: true, magnitude: 0.05)   // faded → ended
        XCTAssertEqual(gate.update(isHazardSound: false, magnitude: 0.9), .none)
        XCTAssertFalse(gate.isActive)
    }

    func testQuietFramesWithoutHazardAreNoOps() {
        var gate = HazardGate()
        XCTAssertEqual(gate.update(isHazardSound: false, magnitude: 0.0), .none)
        XCTAssertEqual(gate.update(isHazardSound: false, magnitude: 0.9), .none)
    }
}
