import Foundation

/// One window's worth of the calibration trace — a timestamp, the
/// smoothed direction, the loudness, and the raw level-difference cue.
/// `CalibrationView` renders an array of these as a line chart.
struct CalibrationSample: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let direction: Double
    let magnitude: Double
    /// Raw `(R−L)/(R+L)` for the window, in user space (sign applied),
    /// before gain. `0` for windows below the noise floor.
    let rawILD: Double
    let isConfident: Bool
}

/// Walks a `CalibrationClip` through `DirectionEstimator` in overlapping
/// windows so you can see how the DSP sees a known sound offline — no
/// device required. Uses the same `DirectionSmoother` as the live pipeline
/// so the trace matches what the compass would have shown.
enum CalibrationProcessor {

    /// Target deflection a "hard side" calibration recording should map
    /// to. 0.85 leaves headroom so louder / closer sources still register
    /// as further out instead of railing at ±1.
    static let calibrationTargetDeflection = 0.85

    /// Bounds for a suggested gain, so a bad recording (silence, or a
    /// source dead ahead) cannot store something absurd.
    static let ildGainRange: ClosedRange<Double> = 2...40

    static func process(
        clip: CalibrationClip,
        frameCount: Int = 2048,
        overlap: Double = 0.5,
        ildGain: Double = DirectionEstimator.defaultIldGain,
        ildBandHz: ClosedRange<Double>? = nil,
        directionBlend: Double = SettingsStore.Sensitivity.medium.directionBlend,
        magnitudeBlend: Double = SettingsStore.Sensitivity.medium.magnitudeBlend
    ) -> [CalibrationSample] {
        guard clip.left.count == clip.right.count, clip.left.count > 0 else { return [] }
        guard frameCount > 0, overlap >= 0, overlap < 1 else { return [] }

        let step = max(1, Int(Double(frameCount) * (1 - overlap)))
        let estimator = DirectionEstimator(
            sampleRate: clip.sampleRate,
            frameCount: frameCount,
            ildGain: ildGain,
            ildBandHz: ildBandHz
        )
        let sign = clip.directionSign

        var samples: [CalibrationSample] = []
        var smoother = DirectionSmoother()
        var index = 0
        var id = 0

        while index + frameCount <= clip.left.count {
            var estimate = clip.left.withUnsafeBufferPointer { lBuf in
                clip.right.withUnsafeBufferPointer { rBuf in
                    estimator.estimate(
                        left: lBuf.baseAddress!.advanced(by: index),
                        right: rBuf.baseAddress!.advanced(by: index),
                        frameCount: frameCount
                    )
                }
            }
            estimate.direction *= sign
            smoother.update(
                estimate: estimate,
                directionBlend: directionBlend,
                magnitudeBlend: magnitudeBlend
            )

            let time = Double(index) / clip.sampleRate
            samples.append(CalibrationSample(
                id: id,
                time: time,
                direction: smoother.direction,
                magnitude: smoother.magnitude,
                rawILD: estimate.rawILD * sign,
                isConfident: estimate.isConfident
            ))
            id += 1
            index += step
        }

        return samples
    }

    /// Derives an `ildGain` from a recording of a source held hard to one
    /// side: takes the 90th percentile of |raw ILD| over confident windows
    /// as "this device's full-scale level difference" and solves
    /// `tanh(gain · (p90 − deadZone)) = target`. Returns `nil` when the
    /// recording has too few confident windows to say anything.
    static func suggestedIldGain(
        from samples: [CalibrationSample],
        target: Double = calibrationTargetDeflection
    ) -> Double? {
        let magnitudes = samples.filter(\.isConfident).map { abs($0.rawILD) }.sorted()
        guard magnitudes.count >= 8 else { return nil }
        let p90 = magnitudes[Int(Double(magnitudes.count - 1) * 0.9)]
        let effective = p90 - DirectionEstimator.ildDeadZone
        guard effective > 0.002 else { return nil }
        let gain = atanh(target) / effective
        return min(max(gain, ildGainRange.lowerBound), ildGainRange.upperBound)
    }
}
