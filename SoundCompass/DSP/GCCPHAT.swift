import Accelerate
import Foundation

/// Generalized Cross-Correlation with Phase Transform (GCC-PHAT) based
/// interaural time-difference estimator.
///
/// GCC-PHAT computes a cross-spectrum between the two channels, whitens it
/// by dividing each frequency bin by its own magnitude, and then inverse
/// FFTs to a time-domain correlation whose peak is considerably sharper and
/// more reverberation-resistant than plain cross-correlation.
///
/// The implementation is allocation-free after `init(frameCount:)`: the
/// input buffers are copied into zero-padded split-complex scratch vectors
/// and everything after that runs in place.
///
/// **Thread safety:** This class is **not** thread-safe. Each instance
/// owns mutable scratch buffers that are overwritten during
/// `estimateLag`. Do not call `estimateLag` concurrently on the same
/// instance. Each `DirectionEstimator` owns its own `GCCPHAT` instance.
final class GCCPHAT {

    /// The zero-padded FFT size used internally. Always a power of two and
    /// at least `2 * frameCount` so the correlation is linear rather than
    /// circular.
    let fftSize: Int

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private var leftReal: [Float]
    private var leftImag: [Float]
    private var rightReal: [Float]
    private var rightImag: [Float]
    private var crossReal: [Float]
    private var crossImag: [Float]

    init(frameCount: Int) {
        precondition(frameCount > 0, "frameCount must be positive")
        let minSize = max(frameCount * 2, 64)
        let log2 = Int(ceil(Foundation.log2(Double(minSize))))
        self.log2n = vDSP_Length(log2)
        self.fftSize = 1 << log2

        guard let setup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("GCCPHAT: vDSP_create_fftsetup failed for size \(fftSize)")
        }
        self.fftSetup = setup

        self.leftReal  = [Float](repeating: 0, count: fftSize)
        self.leftImag  = [Float](repeating: 0, count: fftSize)
        self.rightReal = [Float](repeating: 0, count: fftSize)
        self.rightImag = [Float](repeating: 0, count: fftSize)
        self.crossReal = [Float](repeating: 0, count: fftSize)
        self.crossImag = [Float](repeating: 0, count: fftSize)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Estimates the integer sample lag that best aligns `left` and `right`
    /// using a PHAT-weighted cross-correlation.
    ///
    /// Convention: a **positive** lag means the left channel leads in time
    /// (the sound reached the left microphone first, so the source is on
    /// the left); a negative lag means the source is on the right. This
    /// matches the `sum_n right[n] · left[n - k]` formulation.
    ///
    /// - Parameters:
    ///   - left: pointer to `frameCount` float samples (left channel).
    ///   - right: pointer to `frameCount` float samples (right channel).
    ///   - frameCount: number of samples available in each buffer; must be
    ///     `≤ fftSize`.
    ///   - maxLag: search window `[-maxLag, +maxLag]`.
    /// - Returns: `(lag, peak)` where `peak` is the normalized correlation
    ///   value at the chosen lag (usable as a confidence score).
    func estimateLag(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int,
        maxLag: Int
    ) -> (lag: Int, peak: Float) {
        let n = min(frameCount, fftSize)

        // Zero the scratch buffers and copy the real input into the real
        // parts. The imaginary parts are always zero for a real signal.
        for i in 0..<fftSize {
            leftReal[i]  = i < n ? left[i]  : 0
            rightReal[i] = i < n ? right[i] : 0
            leftImag[i]  = 0
            rightImag[i] = 0
        }

        return leftReal.withUnsafeMutableBufferPointer  { lR in
        leftImag.withUnsafeMutableBufferPointer          { lI in
        rightReal.withUnsafeMutableBufferPointer         { rR in
        rightImag.withUnsafeMutableBufferPointer         { rI in
        crossReal.withUnsafeMutableBufferPointer         { xR in
        crossImag.withUnsafeMutableBufferPointer         { xI in
            var leftSplit  = DSPSplitComplex(realp: lR.baseAddress!, imagp: lI.baseAddress!)
            var rightSplit = DSPSplitComplex(realp: rR.baseAddress!, imagp: rI.baseAddress!)
            var crossSplit = DSPSplitComplex(realp: xR.baseAddress!, imagp: xI.baseAddress!)

            // Forward FFTs in place.
            vDSP_fft_zip(fftSetup, &leftSplit,  1, log2n, FFTDirection(kFFTDirection_Forward))
            vDSP_fft_zip(fftSetup, &rightSplit, 1, log2n, FFTDirection(kFFTDirection_Forward))

            // Cross-spectrum. `vDSP_zvmul` with conjugate flag -1 conjugates
            // its *first* operand, so this computes X = conj(R) · L, whose
            // inverse transform is c[k] = Σ l[n + k] · r[n]. That peaks at
            // k = −τ when right[n] = left[n − τ] (left leads), which is why
            // the scan below returns `-bestLag` to honour the documented
            // "positive lag = left leads" convention. The buffer is a
            // dedicated output because Swift's exclusive-access rule forbids
            // aliasing the same `&var` as both input and output.
            vDSP_zvmul(&rightSplit, 1, &leftSplit, 1, &crossSplit, 1, vDSP_Length(fftSize), -1)

            // PHAT normalization: X[k] /= |X[k]|
            for i in 0..<fftSize {
                let re = xR[i]
                let im = xI[i]
                let mag = sqrtf(re * re + im * im)
                if mag > 1e-9 {
                    xR[i] = re / mag
                    xI[i] = im / mag
                }
            }

            // Inverse FFT. vDSP's IFFT is unnormalized, but we only care
            // about the arg-max of the result so the overall scale is
            // irrelevant.
            vDSP_fft_zip(fftSetup, &crossSplit, 1, log2n, FFTDirection(kFFTDirection_Inverse))

            // Scan [-maxLag, +maxLag]. Positive lags live at indices
            // 1..fftSize/2-1, negative lags wrap into fftSize/2+1..fftSize-1.
            let cappedLag = min(maxLag, fftSize / 2 - 1)
            var bestLag = 0
            var bestValue: Float = -.greatestFiniteMagnitude

            for lag in -cappedLag...cappedLag {
                let idx = (lag + fftSize) % fftSize
                let value = xR[idx]
                if value > bestValue {
                    bestValue = value
                    bestLag = lag
                }
            }
            return (-bestLag, bestValue)
        }}}}}}
    }
}
