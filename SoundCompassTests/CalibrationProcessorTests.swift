import XCTest
@testable import SoundCompass

final class CalibrationProcessorTests: XCTestCase {

    func testEmptyClipReturnsNoSamples() {
        let clip = CalibrationClip(left: [], right: [], sampleRate: 48_000)
        XCTAssertEqual(CalibrationProcessor.process(clip: clip), [])
    }

    func testProducesSamplesAcrossWindows() {
        // Two seconds of mono white noise copied into both channels.
        let sampleRate: Double = 48_000
        let totalSamples = Int(sampleRate * 2)
        let noise = TestSignals.whiteNoise(count: totalSamples, seed: 7)
        let clip = CalibrationClip(left: noise, right: noise, sampleRate: sampleRate)

        let samples = CalibrationProcessor.process(clip: clip, frameCount: 2048, overlap: 0.5)

        // We expect roughly 2 s / (1024 samples / 48 kHz) = ~93 windows.
        XCTAssertGreaterThan(samples.count, 80)
        XCTAssertLessThan(samples.count, 100)

        // Monotonic timestamps.
        for (i, sample) in samples.enumerated() where i > 0 {
            XCTAssertGreaterThan(sample.time, samples[i - 1].time)
        }
    }

    func testDelayedRightTracesNegativeDirection() {
        // Construct a one-second clip where the right channel lags the
        // left by τ samples — that's a sound from the LEFT.
        let sampleRate: Double = 48_000
        let tau = 8
        let length = Int(sampleRate)
        let source = TestSignals.whiteNoise(count: length + 64, seed: 11)
        let (left, right) = TestSignals.delayedPair(
            source: source,
            tau: tau,
            frameCount: length
        )
        let clip = CalibrationClip(left: left, right: right, sampleRate: sampleRate)

        let samples = CalibrationProcessor.process(clip: clip)

        // Ignore the first few windows while the exponential smoother
        // catches up; the steady-state direction should be negative.
        let steady = samples.suffix(20)
        let avg = steady.map(\.direction).reduce(0, +) / Double(steady.count)
        XCTAssertLessThan(avg, -0.05,
                          "Expected negative steady-state direction, got \(avg)")
    }
}
