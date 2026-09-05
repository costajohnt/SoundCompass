import XCTest
@testable import SoundCompass

/// Unit tests for `FrontBackResolver`. We bypass `CoreMotion` by calling
/// `_injectForTesting(yaw:direction:)` with synthetic samples that
/// simulate the user rotating the phone while a single sound source sits
/// either in front of or behind them.
///
/// Physics recap: for a source at angle `θ` from the phone's forward axis
/// (positive = right), the measured lateral direction is `sin(θ)`.
/// CoreMotion yaw is positive for a **counter-clockwise** turn seen from
/// above (right-handed frame, z out of the screen). Turning the phone CCW
/// by `Δφ` swings its top edge left, so a world-fixed source appears at
/// `θ + Δφ` in the device frame.
///
/// * Sound in front  (θ ≈ 0):  sin(Δφ)       → direction increases with yaw
/// * Sound behind    (θ ≈ π):  sin(π + Δφ)   → direction decreases with yaw
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

        sweep(resolver: resolver, from: 0, to: yawSweep, source: thetaStart)

        // Let the async publish callbacks land.
        waitForMain()

        if case .front = resolver.resolution {
            XCTAssertGreaterThan(resolver.slope, 0.3, "front should give a clearly positive slope, got \(resolver.slope)")
        } else {
            XCTFail("Expected .front, got \(resolver.resolution)")
        }
    }

    func testBackSourceResolvesToBack() {
        let resolver = FrontBackResolver()
        // Source behind, slightly to the right. θ = π − 10°.
        let thetaStart = Double.pi - 10 * Double.pi / 180

        sweep(resolver: resolver, from: 0, to: yawSweep, source: thetaStart)

        waitForMain()

        if case .back = resolver.resolution {
            XCTAssertLessThan(resolver.slope, -0.3, "back should give a clearly negative slope, got \(resolver.slope)")
        } else {
            XCTFail("Expected .back, got \(resolver.resolution)")
        }
    }

    func testClockwiseTurnStillResolvesFront() {
        // A clockwise turn is a *negative* yaw sweep; the answer must not
        // depend on which way the user turns.
        let resolver = FrontBackResolver()
        sweep(resolver: resolver, from: 0, to: -yawSweep, source: 0.1)
        waitForMain()
        XCTAssertEqual(resolver.resolution, .front)
    }

    func testInsufficientRotationReturnsNeedsRotation() {
        let resolver = FrontBackResolver()
        // Only rotate 5° — below the 15° minimum.
        let smallSweep: Double = 5 * .pi / 180
        sweep(resolver: resolver, from: 0, to: smallSweep, source: 0.3)

        waitForMain()

        switch resolver.resolution {
        case .needsRotation:
            break
        default:
            XCTFail("Expected .needsRotation, got \(resolver.resolution)")
        }
    }

    func testResolutionLatchesAfterUserStopsTurning() {
        // After the sweep, hold the phone still long enough for the
        // sample window to contain only one yaw value. Without the latch
        // the resolver would fall back to `.needsRotation` immediately.
        let resolver = FrontBackResolver()
        sweep(resolver: resolver, from: 0, to: yawSweep, source: 0.1)
        waitForMain()
        XCTAssertEqual(resolver.resolution, .front)

        for _ in 0..<80 {
            resolver._injectForTesting(yaw: yawSweep, direction: sin(0.1 + yawSweep))
        }
        waitForMain()
        XCTAssertEqual(resolver.resolution, .front, "latched result should survive a still window")
    }

    func testLatchExpires() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let resolver = FrontBackResolver(latchDuration: 10, now: { clock })
        sweep(resolver: resolver, from: 0, to: yawSweep, source: 0.1)
        waitForMain()
        XCTAssertEqual(resolver.resolution, .front)

        // Let the window go completely still first (while the latch is
        // fresh), then jump the clock past the latch and add a few more
        // still samples: nothing in the window can re-derive the answer.
        for _ in 0..<80 {
            resolver._injectForTesting(yaw: yawSweep, direction: sin(0.1 + yawSweep))
        }
        waitForMain()
        XCTAssertEqual(resolver.resolution, .front)

        clock = clock.addingTimeInterval(11)
        for _ in 0..<5 {
            resolver._injectForTesting(yaw: yawSweep, direction: sin(0.1 + yawSweep))
        }
        waitForMain()
        if case .needsRotation = resolver.resolution {
            // expected
        } else {
            XCTFail("Expected latch to expire into .needsRotation, got \(resolver.resolution)")
        }
    }

    func testResetClearsState() {
        let resolver = FrontBackResolver()
        sweep(resolver: resolver, from: 0, to: yawSweep, source: 0.2)
        waitForMain()

        resolver._resetForTesting()

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
        source theta: Double
    ) {
        let step = (endYaw - startYaw) / Double(sampleCount - 1)
        for i in 0..<sampleCount {
            let yaw = startYaw + step * Double(i)
            // Source angle relative to the device frame. For a world-fixed
            // source at absolute angle `theta`, after the phone has turned
            // CCW by `yaw`, the apparent angle is `theta + yaw`.
            let relative = theta + yaw
            let direction = sin(relative)
            resolver._injectForTesting(yaw: yaw, direction: direction)
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
