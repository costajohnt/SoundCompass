import XCTest
@testable import SoundCompass

/// Unit tests for `FrontBackResolver`. We bypass `CoreMotion` by calling
/// `_injectForTesting(yaw:direction:)` with synthetic samples that
/// simulate the user rotating the phone while a single sound source sits
/// either in front of or behind them.
///
/// Physics recap: for a source at angle `θ` from the phone's forward axis,
/// the measured lateral direction is `sin(θ)`. When the user yaws the
/// phone by `Δφ`, the source moves in the device frame to `θ − Δφ`.
///
/// * Sound in front  (θ ≈ 0):  sin(−Δφ)  → direction decreases with yaw
/// * Sound behind    (θ ≈ π):  sin(π − Δφ) = sin(Δφ)  → direction
///                                                       increases with yaw
///
/// The resolver fits a linear regression of `direction` on `yaw`; the
/// sign of the slope distinguishes front from back.
final class FrontBackResolverTests: XCTestCase {

    /// How many samples we sweep through for each test.
    private let sampleCount = 40

    /// Total yaw rotation in radians (well above the 15° minimum).
    private let yawSweep: Double = 30 * .pi / 180

    func testFrontSourceResolvesToFront() {
        let resolver = FrontBackResolver()
        // Source slightly to the right of forward so the initial direction
        // is nonzero. θ = +10°.
        let thetaStart = 10 * Double.pi / 180

        sweep(resolver: resolver, from: 0, to: yawSweep, source: thetaStart, front: true)

        // Let the async publish callbacks land.
        waitForMain()

        if case .front = resolver.resolution {
            XCTAssertLessThan(resolver.slope, -0.3, "front should give a clearly negative slope, got \(resolver.slope)")
        } else {
            XCTFail("Expected .front, got \(resolver.resolution)")
        }
    }

    func testBackSourceResolvesToBack() {
        let resolver = FrontBackResolver()
        // Source behind, slightly to the right. θ = π − 10°.
        let thetaStart = Double.pi - 10 * Double.pi / 180

        sweep(resolver: resolver, from: 0, to: yawSweep, source: thetaStart, front: false)

        waitForMain()

        if case .back = resolver.resolution {
            XCTAssertGreaterThan(resolver.slope, 0.3, "back should give a clearly positive slope, got \(resolver.slope)")
        } else {
            XCTFail("Expected .back, got \(resolver.resolution)")
        }
    }

    func testInsufficientRotationReturnsNeedsRotation() {
        let resolver = FrontBackResolver()
        // Only rotate 5° — below the 15° minimum.
        let smallSweep: Double = 5 * .pi / 180
        sweep(resolver: resolver, from: 0, to: smallSweep, source: 0.3, front: true)

        waitForMain()

        switch resolver.resolution {
        case .needsRotation:
            break
        default:
            XCTFail("Expected .needsRotation, got \(resolver.resolution)")
        }
    }

    func testResetClearsState() {
        let resolver = FrontBackResolver()
        sweep(resolver: resolver, from: 0, to: yawSweep, source: 0.2, front: true)
        waitForMain()

        resolver.reset()

        XCTAssertEqual(resolver.resolution, .unknown)
        XCTAssertEqual(resolver.yawRangeDegrees, 0, accuracy: 0.0001)
        XCTAssertEqual(resolver.slope, 0, accuracy: 0.0001)
    }

    // MARK: - Helpers

    /// Pushes `sampleCount` synthetic samples into the resolver that
    /// simulate a sound source being fixed in world space while the
    /// phone rotates in yaw from `startYaw` to `endYaw`.
    private func sweep(
        resolver: FrontBackResolver,
        from startYaw: Double,
        to endYaw: Double,
        source theta: Double,
        front: Bool
    ) {
        let step = (endYaw - startYaw) / Double(sampleCount - 1)
        for i in 0..<sampleCount {
            let yaw = startYaw + step * Double(i)
            // Source angle relative to the device frame. For a world-fixed
            // source at absolute angle `theta`, after the phone has rotated
            // by `yaw`, the apparent angle is `theta − yaw`.
            let relative = theta - yaw
            let direction = sin(relative)
            resolver._injectForTesting(yaw: yaw, direction: direction)
            _ = front  // unused flag kept for future assertions
        }
    }

    /// The resolver publishes via `DispatchQueue.main.async`; tests run
    /// on the main queue, so we need to drain it to see the update.
    private func waitForMain() {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
