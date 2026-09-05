import Foundation

/// A second-order IIR bandpass filter in transposed direct form II.
///
/// Coefficients follow the Audio EQ Cookbook (RBJ) formulas for a constant
/// 0 dB peak gain bandpass. The filter's state (`z1`, `z2`) is preserved
/// across `process(...)` calls so it can operate on streaming audio.
final class BiquadBandpass {

    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0

    private var z1: Float = 0
    private var z2: Float = 0

    init(sampleRate: Double, lowHz: Double, highHz: Double) {
        setCoefficients(sampleRate: sampleRate, lowHz: lowHz, highHz: highHz)
    }

    func reset() {
        z1 = 0
        z2 = 0
    }

    /// Filters `count` samples from `input` into `output`. Input and output
    /// may be the same buffer.
    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        // Transposed direct form II:
        //   y[n] = b0 x[n] + z1
        //   z1   = b1 x[n] - a1 y[n] + z2
        //   z2   = b2 x[n] - a2 y[n]
        var s1 = z1
        var s2 = z2
        for i in 0..<count {
            let x = input[i]
            let y = b0 * x + s1
            s1 = b1 * x - a1 * y + s2
            s2 = b2 * x - a2 * y
            output[i] = y
        }
        z1 = s1
        z2 = s2
    }

    private func setCoefficients(sampleRate: Double, lowHz: Double, highHz: Double) {
        precondition(lowHz > 0 && highHz > lowHz, "invalid bandpass edges")
        precondition(sampleRate > 2 * highHz, "Nyquist violation")

        // Geometric center; Q derived so the -3 dB points land on
        // lowHz/highHz (approximately, in the narrow-band limit).
        let centerHz = sqrt(lowHz * highHz)
        let bandwidth = highHz - lowHz
        let q = max(centerHz / bandwidth, 0.25)

        let omega = 2 * Double.pi * centerHz / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)

        let b0d =  alpha
        let b1d =  0.0
        let b2d = -alpha
        let a0d =  1 + alpha
        let a1d = -2 * cosOmega
        let a2d =  1 - alpha

        self.b0 = Float(b0d / a0d)
        self.b1 = Float(b1d / a0d)
        self.b2 = Float(b2d / a0d)
        self.a1 = Float(a1d / a0d)
        self.a2 = Float(a2d / a0d)
    }
}

/// A steeper band limiter for the ILD measurement path: a second-order
/// Butterworth high-pass at `lowHz` cascaded with a second-order
/// Butterworth low-pass at `highHz` (RBJ cookbook, transposed direct
/// form II). The single-biquad `BiquadBandpass` has 6 dB/octave skirts,
/// which lets a 200 Hz rumble leak ~15 dB into a 1–8 kHz band; this
/// cascade attenuates it by ~28 dB, which is what makes the band-limited
/// level comparison actually ignore low-frequency energy.
final class BiquadBandLimiter {

    private struct Stage {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var z1: Float = 0, z2: Float = 0

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }

        mutating func reset() {
            z1 = 0
            z2 = 0
        }
    }

    private var highpass = Stage()
    private var lowpass = Stage()

    init(sampleRate: Double, lowHz: Double, highHz: Double) {
        precondition(lowHz > 0 && highHz > lowHz, "invalid band edges")
        precondition(sampleRate > 2 * highHz, "Nyquist violation")
        let q = 1.0 / 2.0.squareRoot()  // Butterworth

        // High-pass at lowHz.
        do {
            let omega = 2 * Double.pi * lowHz / sampleRate
            let alpha = sin(omega) / (2 * q)
            let c = cos(omega)
            let a0 = 1 + alpha
            highpass.b0 = Float(((1 + c) / 2) / a0)
            highpass.b1 = Float((-(1 + c)) / a0)
            highpass.b2 = Float(((1 + c) / 2) / a0)
            highpass.a1 = Float((-2 * c) / a0)
            highpass.a2 = Float((1 - alpha) / a0)
        }

        // Low-pass at highHz.
        do {
            let omega = 2 * Double.pi * highHz / sampleRate
            let alpha = sin(omega) / (2 * q)
            let c = cos(omega)
            let a0 = 1 + alpha
            lowpass.b0 = Float(((1 - c) / 2) / a0)
            lowpass.b1 = Float((1 - c) / a0)
            lowpass.b2 = Float(((1 - c) / 2) / a0)
            lowpass.a1 = Float((-2 * c) / a0)
            lowpass.a2 = Float((1 - alpha) / a0)
        }
    }

    func reset() {
        highpass.reset()
        lowpass.reset()
    }

    /// Filters `count` samples from `input` into `output`. Input and output
    /// may be the same buffer.
    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        var hp = highpass
        var lp = lowpass
        for i in 0..<count {
            output[i] = lp.process(hp.process(input[i]))
        }
        highpass = hp
        lowpass = lp
    }
}
