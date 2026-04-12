import Foundation

/// Deterministic signal generators shared by the DSP test suite.
enum TestSignals {

    /// Deterministic white-noise-ish signal based on a linear congruential
    /// PRNG so test runs are reproducible.
    static func whiteNoise(count: Int, seed: UInt64 = 0xC0FFEE) -> [Float] {
        var state = seed | 1  // avoid zero state
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            // Extract a 53-bit fraction and map to [-0.3, 0.3].
            let frac = Double(state >> 11) / Double(1 << 53)
            out[i] = Float((frac - 0.5) * 0.6)
        }
        return out
    }

    /// A pure sine wave at `frequency` Hz sampled at `sampleRate` Hz.
    static func sine(
        count: Int,
        frequency: Double,
        sampleRate: Double,
        amplitude: Float = 0.5,
        phase: Double = 0
    ) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let step = 2 * Double.pi * frequency / sampleRate
        for i in 0..<count {
            out[i] = amplitude * Float(sin(step * Double(i) + phase))
        }
        return out
    }

    /// Returns a `(left, right)` pair built from `source` such that the
    /// right channel is delayed by `tau` samples relative to the left —
    /// i.e. a sound that arrived at the left microphone first.
    static func delayedPair(
        source: [Float],
        tau: Int,
        frameCount: Int
    ) -> (left: [Float], right: [Float]) {
        precondition(source.count >= frameCount + abs(tau) + 16,
                     "source not long enough for the requested delay")
        let left  = Array(source[tau ..< tau + frameCount])
        let right = Array(source[0 ..< frameCount])
        return (left, right)
    }
}
