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

    func testMirroredClipIsPutInUserSpace() {
        // Same recording, but tagged as coming from the mirrored front
        // source: the trace must flip sign.
        let sampleRate: Double = 48_000
        let length = Int(sampleRate)
        let noise = TestSignals.whiteNoise(count: length, seed: 12)
        let left = noise.map { $0 * 0.9 }
        let right = noise
        let back = CalibrationClip(left: left, right: right, sampleRate: sampleRate, directionSign: 1)
        let front = CalibrationClip(left: left, right: right, sampleRate: sampleRate, directionSign: -1)

        let backAvg = CalibrationProcessor.process(clip: back).suffix(20).map(\.direction).reduce(0, +)
        let frontAvg = CalibrationProcessor.process(clip: front).suffix(20).map(\.direction).reduce(0, +)
        XCTAssertGreaterThan(backAvg, 0.5)
        XCTAssertLessThan(frontAvg, -0.5)
    }

    func testSuggestedGainMapsRecordedILDToTarget() throws {
        // A recording whose raw ILD is a steady 0.06 should yield a gain
        // that maps (0.06 − deadZone) to the target deflection.
        let sampleRate: Double = 48_000
        let length = Int(sampleRate)
        let noise = TestSignals.whiteNoise(count: length, seed: 13)
        let ild = 0.06
        let left = noise.map { $0 * Float(1 - ild) }
        let right = noise.map { $0 * Float(1 + ild) }
        let clip = CalibrationClip(left: left, right: right, sampleRate: sampleRate)

        let samples = CalibrationProcessor.process(clip: clip)
        let gain = try XCTUnwrap(CalibrationProcessor.suggestedIldGain(from: samples))
        let expected = atanh(CalibrationProcessor.calibrationTargetDeflection) / (ild - DirectionEstimator.ildDeadZone)
        XCTAssertEqual(gain, expected, accuracy: expected * 0.1)

        // Re-running with that gain should put the steady state near the target.
        let calibrated = CalibrationProcessor.process(clip: clip, ildGain: gain)
        let steady = calibrated.suffix(20).map(\.direction).reduce(0, +) / 20
        XCTAssertEqual(steady, CalibrationProcessor.calibrationTargetDeflection, accuracy: 0.1)
    }

    func testSuggestedGainIsNilForSilence() {
        let clip = CalibrationClip(left: [Float](repeating: 0, count: 48_000), right: [Float](repeating: 0, count: 48_000), sampleRate: 48_000)
        let samples = CalibrationProcessor.process(clip: clip)
        XCTAssertNil(CalibrationProcessor.suggestedIldGain(from: samples))
    }
}
