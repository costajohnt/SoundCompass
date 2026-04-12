import XCTest
@testable import SoundCompass

/// "Smoke" tests: instantiate every non-trivial `ObservableObject` and
/// DSP primitive to make sure init paths don't crash, don't hang, and
/// end up in a sensible default state. These tests catch the kind of
/// breakage that only shows up at runtime — a missing inline default,
/// a Combine pipeline that subscribes before its source is set, an
/// exclusive-access violation like the one we fixed in GCCPHAT.
final class InitSmokeTests: XCTestCase {

    func testSettingsStoreInitHasSaneDefaults() {
        let defaults = UserDefaults(suiteName: "SoundCompassSmoke")!
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.sensitivity, .medium)
        XCTAssertEqual(store.hapticStrength, .light)
        XCTAssertEqual(store.hearingEar, .unspecified)
        XCTAssertEqual(store.theme, .dark)
        XCTAssertTrue(store.hazardAlerts)
        XCTAssertFalse(store.speechEnabled)
        XCTAssertFalse(store.passthroughEnabled)
    }

    func testAudioDirectionDetectorInitializesWithoutCrashing() {
        let detector = AudioDirectionDetector()
        XCTAssertFalse(detector.isRunning)
        XCTAssertEqual(detector.direction, 0)
        XCTAssertEqual(detector.magnitude, 0)
        XCTAssertFalse(detector.isHazardActive)
        XCTAssertEqual(detector.frontBackResolution, .unknown)
    }

    func testDirectionEstimatorSmallFrameCount() {
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: 64)
        let zero = [Float](repeating: 0, count: 64)
        let estimate = zero.withUnsafeBufferPointer { buf in
            estimator.estimate(
                left: buf.baseAddress!,
                right: buf.baseAddress!,
                frameCount: 64
            )
        }
        XCTAssertFalse(estimate.isConfident)
    }

    func testSubbandEstimatorHandlesMinimumFrameCount() {
        let sub = SubbandDirectionEstimator(
            sampleRate: 48_000,
            frameCount: 256,
            bands: SubbandDirectionEstimator.defaultBands()
        )
        let noise = TestSignals.whiteNoise(count: 256, seed: 1)
        let results = noise.withUnsafeBufferPointer { buf in
            sub.estimate(
                left: buf.baseAddress!,
                right: buf.baseAddress!,
                frameCount: 256
            )
        }
        XCTAssertEqual(results.count, SubbandDirectionEstimator.defaultBands().count)
    }

    func testFrontBackResolverInitialState() {
        let resolver = FrontBackResolver()
        XCTAssertEqual(resolver.resolution, .unknown)
        XCTAssertEqual(resolver.yawRangeDegrees, 0, accuracy: 0.0001)
        XCTAssertEqual(resolver.slope, 0, accuracy: 0.0001)
    }

    func testEventHistoryStoreStartsEmpty() {
        let store = EventHistoryStore()
        XCTAssertTrue(store.events.isEmpty)
    }

    func testSessionStatsStartsZero() {
        let stats = SessionStats()
        XCTAssertEqual(stats.snapshot.totalEvents, 0)
        XCTAssertEqual(stats.snapshot.hazardCount, 0)
        XCTAssertNil(stats.snapshot.topLabel)
    }
}
