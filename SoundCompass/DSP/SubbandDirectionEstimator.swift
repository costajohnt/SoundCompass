import Foundation

/// Runs a `DirectionEstimator` per frequency band so the app can tell which
/// category of sound (traffic rumble, speech, alarms, hiss) dominated a
/// given window and where *each* band came from.
///
/// Each band is carved out with a streaming `BiquadBandpass` applied
/// independently to the left and right channels, after which the usual
/// ILD + GCC-PHAT machinery runs on the filtered signal.
final class SubbandDirectionEstimator {

    struct Band: Equatable {
        let name: String
        let lowHz: Double
        let highHz: Double
    }

    struct BandResult: Equatable {
        let band: Band
        let direction: Double
        let magnitude: Double
    }

    let bands: [Band]
    let frameCount: Int
    let sampleRate: Double

    private let estimators: [DirectionEstimator]
    private let leftFilters: [BiquadBandpass]
    private let rightFilters: [BiquadBandpass]

    private var leftScratch: [Float]
    private var rightScratch: [Float]

    init(sampleRate: Double, frameCount: Int, bands: [Band]) {
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        // Drop bands whose top edge sits too close to Nyquist for the
        // biquad (`BiquadBandpass` preconditions `sampleRate > 2 * highHz`).
        // Low-rate input routes are reachable in practice — a Bluetooth HFP
        // mic runs at 16/24 kHz — and must degrade to fewer bands, not trap.
        let usable = bands.filter { $0.highHz < 0.45 * sampleRate }
        self.bands = usable

        self.estimators = usable.map { _ in
            DirectionEstimator(sampleRate: sampleRate, frameCount: frameCount)
        }
        self.leftFilters = usable.map {
            BiquadBandpass(sampleRate: sampleRate, lowHz: $0.lowHz, highHz: $0.highHz)
        }
        self.rightFilters = usable.map {
            BiquadBandpass(sampleRate: sampleRate, lowHz: $0.lowHz, highHz: $0.highHz)
        }
        self.leftScratch = [Float](repeating: 0, count: frameCount)
        self.rightScratch = [Float](repeating: 0, count: frameCount)
    }

    /// Compute per-band direction + magnitude for the given stereo window.
    /// Returns one result per configured band, in the order the bands were
    /// supplied at init time.
    func estimate(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) -> [BandResult] {
        let frameCount = min(frameCount, self.frameCount)

        var results: [BandResult] = []
        results.reserveCapacity(bands.count)

        for i in bands.indices {
            leftScratch.withUnsafeMutableBufferPointer { lBuf in
                leftFilters[i].process(input: left, output: lBuf.baseAddress!, count: frameCount)
            }
            rightScratch.withUnsafeMutableBufferPointer { rBuf in
                rightFilters[i].process(input: right, output: rBuf.baseAddress!, count: frameCount)
            }

            let estimate = leftScratch.withUnsafeBufferPointer { lBuf in
                rightScratch.withUnsafeBufferPointer { rBuf in
                    estimators[i].estimate(
                        left: lBuf.baseAddress!,
                        right: rBuf.baseAddress!,
                        frameCount: frameCount
                    )
                }
            }

            results.append(BandResult(
                band: bands[i],
                direction: estimate.direction,
                magnitude: estimate.combinedRms
            ))
        }

        return results
    }

    /// Flush each band's filter memory — useful after start/stop.
    func reset() {
        leftFilters.forEach { $0.reset() }
        rightFilters.forEach { $0.reset() }
    }
}

extension SubbandDirectionEstimator {
    /// A sensible default for general-purpose environmental listening:
    /// low rumble, speech, alert/alarm range, and bright high frequencies.
    static func defaultBands() -> [Band] {
        [
            Band(name: "Low",    lowHz: 100,  highHz: 500),
            Band(name: "Speech", lowHz: 500,  highHz: 3000),
            Band(name: "Alert",  lowHz: 3000, highHz: 8000),
            Band(name: "High",   lowHz: 8000, highHz: 16000),
        ]
    }
}
