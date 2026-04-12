import XCTest
@testable import SoundCompass

final class GCCPHATTests: XCTestCase {

    func testIdenticalSignalsReturnZeroLag() {
        let frameCount = 1024
        let gcc = GCCPHAT(frameCount: frameCount)
        let signal = TestSignals.whiteNoise(count: frameCount, seed: 1)

        let (lag, peak) = signal.withUnsafeBufferPointer { buf in
            gcc.estimateLag(
                left: buf.baseAddress!,
                right: buf.baseAddress!,
                frameCount: frameCount,
                maxLag: 32
            )
        }

        XCTAssertEqual(lag, 0)
        XCTAssertGreaterThan(peak, 0)
    }

    func testDelayedRightReturnsPositiveLag() {
        // right[n] = left[n - τ]  →  sound reached LEFT first  →  positive lag.
        let frameCount = 1024
        let tau = 5
        let gcc = GCCPHAT(frameCount: frameCount)
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 2)
        let (left, right) = TestSignals.delayedPair(source: source, tau: tau, frameCount: frameCount)

        let (lag, _) = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                gcc.estimateLag(
                    left: l.baseAddress!,
                    right: r.baseAddress!,
                    frameCount: frameCount,
                    maxLag: 32
                )
            }
        }

        XCTAssertEqual(lag, tau)
    }

    func testDelayedLeftReturnsNegativeLag() {
        // Swap the pair so the left channel is the delayed one  →  sound on the right.
        let frameCount = 1024
        let tau = 7
        let gcc = GCCPHAT(frameCount: frameCount)
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 3)
        let (right, left) = TestSignals.delayedPair(source: source, tau: tau, frameCount: frameCount)

        let (lag, _) = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                gcc.estimateLag(
                    left: l.baseAddress!,
                    right: r.baseAddress!,
                    frameCount: frameCount,
                    maxLag: 32
                )
            }
        }

        XCTAssertEqual(lag, -tau)
    }

    func testNoiseResilience() {
        // Add independent broadband noise to both channels and check that
        // the true lag still dominates the correlation.
        let frameCount = 2048
        let tau = 6
        let gcc = GCCPHAT(frameCount: frameCount)
        let source = TestSignals.whiteNoise(count: frameCount + 32, seed: 10)
        let noiseL = TestSignals.whiteNoise(count: frameCount, seed: 11)
        let noiseR = TestSignals.whiteNoise(count: frameCount, seed: 12)
        var (left, right) = TestSignals.delayedPair(source: source, tau: tau, frameCount: frameCount)
        for i in 0..<frameCount {
            left[i]  += noiseL[i] * 0.3
            right[i] += noiseR[i] * 0.3
        }

        let (lag, _) = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                gcc.estimateLag(
                    left: l.baseAddress!,
                    right: r.baseAddress!,
                    frameCount: frameCount,
                    maxLag: 32
                )
            }
        }

        // PHAT can land on ±1 sample of the true lag under uncorrelated noise.
        XCTAssertLessThanOrEqual(
            abs(lag - tau),
            1,
            "GCC-PHAT should tolerate 30% uncorrelated noise, got lag \(lag) (expected \(tau))"
        )
    }
}
