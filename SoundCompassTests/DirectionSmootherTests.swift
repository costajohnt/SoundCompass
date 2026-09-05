import XCTest
@testable import SoundCompass

final class DirectionSmootherTests: XCTestCase {

    private func estimate(direction: Double, magnitude: Double, confident: Bool = true) -> DirectionEstimate {
        DirectionEstimate(direction: direction, magnitude: magnitude, combinedRms: magnitude / 8, isConfident: confident)
    }

    func testConfidentEstimateBlendsTowardTarget() {
        var smoother = DirectionSmoother()
        smoother.update(estimate: estimate(direction: 1, magnitude: 1), directionBlend: 0.25, magnitudeBlend: 0.4)
        XCTAssertEqual(smoother.direction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(smoother.magnitude, 0.4, accuracy: 1e-9)
        smoother.update(estimate: estimate(direction: 1, magnitude: 1), directionBlend: 0.25, magnitudeBlend: 0.4)
        XCTAssertEqual(smoother.direction, 0.4375, accuracy: 1e-9)
    }

    func testNonConfidentEstimateDecaysDirectionButFollowsLoudness() {
        var smoother = DirectionSmoother(direction: 0.8, magnitude: 0.5)
        smoother.update(estimate: estimate(direction: 0, magnitude: 0, confident: false), directionBlend: 0.25, magnitudeBlend: 0.4)
        XCTAssertEqual(smoother.direction, 0.72, accuracy: 1e-9)
        XCTAssertEqual(smoother.magnitude, 0.3, accuracy: 1e-9)
    }

    func testLoudnessOnlyUpdateDecaysDirection() {
        var smoother = DirectionSmoother(direction: -0.5, magnitude: 0)
        smoother.updateLoudnessOnly(1.0, magnitudeBlend: 0.5)
        XCTAssertEqual(smoother.direction, -0.45, accuracy: 1e-9)
        XCTAssertEqual(smoother.magnitude, 0.5, accuracy: 1e-9)
    }

    func testHazardBlendLandsAlmostImmediately() {
        var smoother = DirectionSmoother()
        smoother.update(estimate: estimate(direction: -1, magnitude: 1), directionBlend: 0.9, magnitudeBlend: 0.4)
        XCTAssertEqual(smoother.direction, -0.9, accuracy: 1e-9)
    }

    func testResetZeroes() {
        var smoother = DirectionSmoother(direction: 0.3, magnitude: 0.3)
        smoother.reset()
        XCTAssertEqual(smoother.direction, 0)
        XCTAssertEqual(smoother.magnitude, 0)
    }
}
