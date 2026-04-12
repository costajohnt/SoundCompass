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
