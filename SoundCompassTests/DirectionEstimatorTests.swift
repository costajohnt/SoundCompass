import XCTest
@testable import SoundCompass

final class DirectionEstimatorTests: XCTestCase {

    func testCenteredSignalIsStraightAhead() {
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: frameCount)
        let noise = TestSignals.whiteNoise(count: frameCount, seed: 1)

        let estimate = noise.withUnsafeBufferPointer { lBuf in
            noise.withUnsafeBufferPointer { rBuf in
                estimator.estimate(
                    left: lBuf.baseAddress!,
                    right: rBuf.baseAddress!,
                    frameCount: frameCount
                )
            }
        }

        XCTAssertTrue(estimate.isConfident)
        XCTAssertEqual(estimate.direction, 0, accuracy: 0.1)
        XCTAssertGreaterThan(estimate.magnitude, 0)
    }

    func testQuietSignalNotConfident() {
        let frameCount = 2048
        let estimator = DirectionEstimator(
            sampleRate: 48_000,
            noiseFloor: 0.01,
            frameCount: frameCount
        )
        let quiet = [Float](repeating: 0, count: frameCount)

        let estimate = quiet.withUnsafeBufferPointer { buf in
            estimator.estimate(
                left: buf.baseAddress!,
                right: buf.baseAddress!,
                frameCount: frameCount
            )
        }

        XCTAssertFalse(estimate.isConfident)
        XCTAssertEqual(estimate.direction, 0)
    }

    func testDelayedRightChannelMeansSoundFromLeft() {
        // right[n] = left[n - τ] → sound from LEFT → direction should be negative.
        let frameCount = 2048
        let tau = 6
        let estimator = DirectionEstimator(
            sampleRate: 48_000,
            maxLagSamples: 32,
            frameCount: frameCount
        )
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 2)
        let (left, right) = TestSignals.delayedPair(
            source: source,
            tau: tau,
            frameCount: frameCount
        )

        let estimate = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                estimator.estimate(
                    left: l.baseAddress!,
                    right: r.baseAddress!,
                    frameCount: frameCount
                )
            }
        }

        XCTAssertTrue(estimate.isConfident)
        XCTAssertLessThan(estimate.direction, -0.05,
                          "Expected negative (left) direction, got \(estimate.direction)")
    }

    func testLouderLeftChannelMeansSoundFromLeft() {
        // Pure ILD test: same signal in both channels, but left 2x louder.
        // Should pull the direction negative even though ITD says zero.
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: frameCount)
        let noise = TestSignals.whiteNoise(count: frameCount, seed: 3)
        let left = noise.map { $0 * 2.0 }
        let right = noise

        let estimate = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                estimator.estimate(
                    left: l.baseAddress!,
                    right: r.baseAddress!,
                    frameCount: frameCount
                )
            }
        }

        XCTAssertTrue(estimate.isConfident)
        XCTAssertLessThan(estimate.direction, -0.05,
                          "Expected negative (left) direction from ILD, got \(estimate.direction)")
    }

    func testDelayedLeftChannelMeansSoundFromRight() {
        let frameCount = 2048
        let tau = 4
        let estimator = DirectionEstimator(
            sampleRate: 48_000,
            maxLagSamples: 32,
            frameCount: frameCount
        )
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 4)
        let (right, left) = TestSignals.delayedPair(
            source: source,
            tau: tau,
            frameCount: frameCount
        )

        let estimate = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                estimator.estimate(
                    left: l.baseAddress!,
                    right: r.baseAddress!,
                    frameCount: frameCount
                )
            }
        }

        XCTAssertTrue(estimate.isConfident)
        XCTAssertGreaterThan(estimate.direction, 0.05,
                             "Expected positive (right) direction, got \(estimate.direction)")
    }
}
