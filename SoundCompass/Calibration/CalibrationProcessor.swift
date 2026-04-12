import Foundation

/// One window's worth of the calibration trace — a timestamp, the
/// smoothed direction, and the loudness. `CalibrationView` renders
/// an array of these as a line chart.
struct CalibrationSample: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let direction: Double
    let magnitude: Double
}

/// Walks a `CalibrationClip` through `DirectionEstimator` in overlapping
/// windows so you can see how the DSP sees a known sound offline — no
/// device required.
enum CalibrationProcessor {
    static func process(
        clip: CalibrationClip,
        frameCount: Int = 2048,
        overlap: Double = 0.5
    ) -> [CalibrationSample] {
        guard clip.left.count == clip.right.count, clip.left.count > 0 else { return [] }
        guard frameCount > 0, overlap >= 0, overlap < 1 else { return [] }

        let step = max(1, Int(Double(frameCount) * (1 - overlap)))
        let estimator = DirectionEstimator(sampleRate: clip.sampleRate, frameCount: frameCount)

        var samples: [CalibrationSample] = []
        var index = 0
        var id = 0

        // Exponential smoother over windows so the trace matches what the
        // live UI would show, not the raw per-window estimates.
        var smoothedDirection: Double = 0
        var smoothedMagnitude: Double = 0
        let blend = 0.25

        while index + frameCount <= clip.left.count {
            let estimate = clip.left.withUnsafeBufferPointer { lBuf in
                clip.right.withUnsafeBufferPointer { rBuf in
                    estimator.estimate(
                        left: lBuf.baseAddress!.advanced(by: index),
                        right: rBuf.baseAddress!.advanced(by: index),
                        frameCount: frameCount
                    )
                }
            }

            if estimate.isConfident {
                smoothedDirection = smoothedDirection * (1 - blend) + estimate.direction * blend
            } else {
                smoothedDirection *= 0.9
            }
            smoothedMagnitude = smoothedMagnitude * 0.6 + estimate.magnitude * 0.4

            let time = Double(index) / clip.sampleRate
            samples.append(CalibrationSample(
                id: id,
                time: time,
                direction: smoothedDirection,
                magnitude: smoothedMagnitude
            ))
            id += 1
            index += step
        }

        return samples
    }
}
