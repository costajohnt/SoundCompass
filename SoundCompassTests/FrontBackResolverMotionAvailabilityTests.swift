import CoreMotion
import XCTest
@testable import SoundCompass

/// Verifies how `FrontBackResolver` handles the case where CoreMotion
/// is not available. We can't swap `CMMotionManager` for a stub
/// without a protocol, but we can observe that construction,
/// `start()`, and `stop()` don't crash on the unit-test simulator
/// (which typically reports `.isDeviceMotionAvailable == false`).
final class FrontBackResolverMotionAvailabilityTests: XCTestCase {

    func testStartWithoutCoreMotionCapabilityIsSafe() {
        let motion = CMMotionManager()
        let resolver = FrontBackResolver(motion: motion)
        // start() is a no-op when isDeviceMotionAvailable is false on
        // the simulator, but we want to make sure it doesn't crash and
        // leaves the resolver in an unknown state.
        resolver.start()
        XCTAssertEqual(resolver.resolution, .unknown)
    }

    func testStopIsIdempotent() {
        let resolver = FrontBackResolver()
        resolver.stop()
        resolver.stop()
        // Just has to not crash.
    }

    func testResetClearsAccumulatedState() {
        let resolver = FrontBackResolver()
        #if DEBUG
        resolver._injectForTesting(yaw: 0, direction: 0.1)
        resolver._injectForTesting(yaw: 0.5, direction: -0.3)
        #endif
        resolver.reset()
        XCTAssertEqual(resolver.resolution, .unknown)
        XCTAssertEqual(resolver.yawRangeDegrees, 0, accuracy: 0.0001)
    }
}
