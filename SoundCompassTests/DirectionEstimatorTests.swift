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
        // Pure delay carries no level difference, so only the additive ITD
        // term contributes: 0.35 · (4/32) ≈ +0.044. Assert sign with margin.
        XCTAssertGreaterThan(estimate.direction, 0.03,
                             "Expected positive (right) direction, got \(estimate.direction)")
    }

    func testUncorrelatedNoiseStaysCentered() {
        // Independent noise in each channel at equal level: the GCC-PHAT
        // peak is meaningless, so the confidence gate must keep the random
        // lag from steering the arrow. Before confidence weighting, the
        // spurious lag carried a fixed share of the blend and produced a
        // large random deflection here.
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: frameCount)
        let left = TestSignals.whiteNoise(count: frameCount, seed: 21)
        let right = TestSignals.whiteNoise(count: frameCount, seed: 22)

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
        XCTAssertLessThan(estimate.itdConfidence, 0.3,
                          "Uncorrelated channels should produce a weak correlation peak")
        XCTAssertEqual(estimate.direction, 0, accuracy: 0.12,
                       "Equal-level uncorrelated noise should stay near center, got \(estimate.direction)")
    }

    func testLagRailedAtWindowEdgeIsIgnored() {
        // A delay equal to the full search window is the signature of a
        // spurious correlation match; the estimator must zero its ITD
        // confidence rather than report a hard-left/right direction.
        let frameCount = 2048
        let maxLag = 8
        let estimator = DirectionEstimator(
            sampleRate: 48_000,
            maxLagSamples: maxLag,
            frameCount: frameCount
        )
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 23)
        let (left, right) = TestSignals.delayedPair(
            source: source,
            tau: maxLag,
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

        XCTAssertEqual(estimate.itdConfidence, 0,
                       "Lag railed at ±maxLag must be rejected, got confidence \(estimate.itdConfidence)")
    }
}
