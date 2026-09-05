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

    // MARK: - Realistic device-scale ILD

    /// Builds a stereo pair with an exact raw ILD of `ild` (both channels
    /// share the same noise so GCC-PHAT sees zero lag, as on a device).
    private func pair(ild: Double, frameCount: Int, seed: UInt64) -> (left: [Float], right: [Float]) {
        let noise = TestSignals.whiteNoise(count: frameCount, seed: seed)
        // (R−L)/(R+L) = ild  with  L + R = 2  →  R = 1 + ild, L = 1 − ild
        let left = noise.map { $0 * Float(1 - ild) }
        let right = noise.map { $0 * Float(1 + ild) }
        return (left, right)
    }

    private func run(_ estimator: DirectionEstimator, _ left: [Float], _ right: [Float], frameCount: Int) -> DirectionEstimate {
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                estimator.estimate(left: l.baseAddress!, right: r.baseAddress!, frameCount: frameCount)
            }
        }
    }

    func testDeviceScaleHardSideILDDeflectsMostOfTheWay() {
        // iPhone 16 Pro measurement: a hard-side source gives |ILD| ≈ 0.08.
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: frameCount)
        let (left, right) = pair(ild: 0.08, frameCount: frameCount, seed: 31)
        let estimate = run(estimator, left, right, frameCount: frameCount)
        XCTAssertEqual(estimate.rawILD, 0.08, accuracy: 0.002)
        XCTAssertGreaterThan(estimate.direction, 0.6, "0.08 raw ILD should read as clearly right, got \(estimate.direction)")
        XCTAssertLessThan(estimate.direction, 0.95, "0.08 raw ILD should not rail at +1")
    }

    func testAmbientWobbleStaysNearCenter() {
        // Ambient jitter on a device is |ILD| ≈ 0.01–0.02 with no source.
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: frameCount)
        let (left, right) = pair(ild: -0.015, frameCount: frameCount, seed: 32)
        let estimate = run(estimator, left, right, frameCount: frameCount)
        XCTAssertEqual(estimate.direction, 0, accuracy: 0.1, "ambient-scale ILD should stay near center, got \(estimate.direction)")
    }

    func testCalibratedGainChangesDeflection() {
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, frameCount: frameCount)
        let (left, right) = pair(ild: 0.05, frameCount: frameCount, seed: 33)
        let before = run(estimator, left, right, frameCount: frameCount).direction
        estimator.ildGain = 30
        let after = run(estimator, left, right, frameCount: frameCount).direction
        XCTAssertGreaterThan(after, before)
    }

    func testITDDisabledEstimatorIgnoresDelay() {
        // Pure delay, no level difference: with ITD off the estimate must
        // be centred and report zero lag/confidence.
        let frameCount = 2048
        let estimator = DirectionEstimator(sampleRate: 48_000, maxLagSamples: 32, frameCount: frameCount, usesITD: false)
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 34)
        let (left, right) = TestSignals.delayedPair(source: source, tau: 6, frameCount: frameCount)
        let estimate = run(estimator, left, right, frameCount: frameCount)
        XCTAssertTrue(estimate.isConfident)
        XCTAssertEqual(estimate.lagSamples, 0)
        XCTAssertEqual(estimate.itdConfidence, 0)
        XCTAssertEqual(estimate.direction, 0, accuracy: 0.05)
    }

    func testBandLimitedILDIgnoresLowFrequencyLevelDifference() {
        // A loud 200 Hz tone only in the left channel plus identical
        // broadband noise in both. Broadband ILD sees a big left bias;
        // the 1–8 kHz band ILD should be near zero.
        let frameCount = 2048
        let sampleRate = 48_000.0
        let noise = TestSignals.whiteNoise(count: frameCount, seed: 35)
        let rumble = TestSignals.sine(count: frameCount, frequency: 200, sampleRate: sampleRate, amplitude: 0.5)
        var left = noise
        for i in 0..<frameCount { left[i] += rumble[i] }
        let right = noise

        let broadband = DirectionEstimator(sampleRate: sampleRate, frameCount: frameCount)
        let banded = DirectionEstimator(sampleRate: sampleRate, frameCount: frameCount, ildBandHz: 1_000...8_000)

        // Two passes so the streaming band filters settle.
        _ = run(banded, left, right, frameCount: frameCount)
        let wide = run(broadband, left, right, frameCount: frameCount)
        let narrow = run(banded, left, right, frameCount: frameCount)

        XCTAssertLessThan(wide.rawILD, -0.2, "broadband ILD should be dominated by the rumble, got \(wide.rawILD)")
        XCTAssertEqual(narrow.rawILD, 0, accuracy: 0.05, "band-limited ILD should ignore the rumble, got \(narrow.rawILD)")
        XCTAssertEqual(narrow.leftRms, wide.leftRms, accuracy: 1e-6, "loudness must stay broadband")
        XCTAssertNotEqual(narrow.ildLeftRms, narrow.leftRms)
    }

    func testBandAboveNyquistIsDroppedNotTrapped() {
        // 16 kHz route: a 1–8 kHz request is clamped under Nyquist.
        let estimator = DirectionEstimator(sampleRate: 16_000, frameCount: 1024, ildBandHz: 1_000...8_000)
        XCTAssertNotNil(estimator.ildBandHz)
        XCTAssertLessThan(estimator.ildBandHz!.upperBound, 8_000)
        let noise = TestSignals.whiteNoise(count: 1024, seed: 36)
        let estimate = run(estimator, noise, noise, frameCount: 1024)
        XCTAssertTrue(estimate.isConfident)
    }
}
