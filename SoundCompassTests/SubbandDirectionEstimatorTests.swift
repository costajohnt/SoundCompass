import XCTest
@testable import SoundCompass

final class SubbandDirectionEstimatorTests: XCTestCase {

    func testSpeechBandDominatesFor1kHzSine() {
        let sampleRate = 48_000.0
        let frameCount = 2048
        let bands: [SubbandDirectionEstimator.Band] = [
            .init(name: "Low",    lowHz: 100,  highHz: 500),
            .init(name: "Speech", lowHz: 500,  highHz: 3000),
            .init(name: "High",   lowHz: 3000, highHz: 10000),
        ]
        let subband = SubbandDirectionEstimator(
            sampleRate: sampleRate,
            frameCount: frameCount,
            bands: bands
        )

        // Run a couple of iterations so the IIR filters reach steady state.
        let sine = TestSignals.sine(
            count: frameCount,
            frequency: 1000,
            sampleRate: sampleRate,
            amplitude: 0.6
        )

        var results: [SubbandDirectionEstimator.BandResult] = []
        for _ in 0..<4 {
            results = sine.withUnsafeBufferPointer { l in
                sine.withUnsafeBufferPointer { r in
                    subband.estimate(
                        left: l.baseAddress!,
                        right: r.baseAddress!,
                        frameCount: frameCount
                    )
                }
            }
        }

        let dominant = results.max(by: { $0.magnitude < $1.magnitude })
        XCTAssertEqual(dominant?.band.name, "Speech",
                       "Expected Speech band to dominate a 1 kHz sine")
    }

    func testHighBandDominatesFor6kHzSine() {
        let sampleRate = 48_000.0
        let frameCount = 2048
        let bands: [SubbandDirectionEstimator.Band] = [
            .init(name: "Low",    lowHz: 100,  highHz: 500),
            .init(name: "Speech", lowHz: 500,  highHz: 3000),
            .init(name: "High",   lowHz: 3000, highHz: 10000),
        ]
        let subband = SubbandDirectionEstimator(
            sampleRate: sampleRate,
            frameCount: frameCount,
            bands: bands
        )

        let sine = TestSignals.sine(
            count: frameCount,
            frequency: 6000,
            sampleRate: sampleRate,
            amplitude: 0.6
        )

        var results: [SubbandDirectionEstimator.BandResult] = []
        for _ in 0..<4 {
            results = sine.withUnsafeBufferPointer { l in
                sine.withUnsafeBufferPointer { r in
                    subband.estimate(
                        left: l.baseAddress!,
                        right: r.baseAddress!,
                        frameCount: frameCount
                    )
                }
            }
        }

        let dominant = results.max(by: { $0.magnitude < $1.magnitude })
        XCTAssertEqual(dominant?.band.name, "High",
                       "Expected High band to dominate a 6 kHz sine")
    }

    func testBandResultShapeMatchesBands() {
        let sampleRate = 48_000.0
        let frameCount = 1024
        let bands = SubbandDirectionEstimator.defaultBands()
        let subband = SubbandDirectionEstimator(
            sampleRate: sampleRate,
            frameCount: frameCount,
            bands: bands
        )
        let noise = TestSignals.whiteNoise(count: frameCount, seed: 5)
        let results = noise.withUnsafeBufferPointer { buf in
            subband.estimate(
                left: buf.baseAddress!,
                right: buf.baseAddress!,
                frameCount: frameCount
            )
        }

        XCTAssertEqual(results.count, bands.count)
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result.band, bands[i])
        }
    }
}
