import AVFoundation
import Combine
import Foundation
import SoundAnalysis

/// Wraps Apple's built-in sound classifier (`SNClassifierIdentifier.version1`,
/// available in iOS 15+) and publishes the top-scoring label so the UI can
/// show "speech", "dog bark", "car horn" etc. alongside the direction.
///
/// The classifier runs on a dedicated serial queue fed by the same tap
/// buffers as the DSP pipeline. Published updates happen on the main queue.
final class SoundClassifier: ObservableObject {

    @Published private(set) var topLabel: String?
    @Published private(set) var topConfidence: Double = 0
    /// Raw, un-humanized classifier identifier (e.g. "car_horn") kept so
    /// safety-critical checks like `HazardClassifier.isHazard` can match
    /// against Apple's exact labels rather than our prettified form.
    @Published private(set) var topRawIdentifier: String?

    /// Minimum confidence (0…1) required before a label is published.
    var minConfidence: Double = 0.5

    private let analysisQueue = DispatchQueue(label: "com.soundcompass.classifier", qos: .userInitiated)
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let observer = ClassifierObserver()

    init() {
        observer.onResult = { [weak self] label, confidence in
            guard let self else { return }
            guard confidence >= self.minConfidence else { return }
            DispatchQueue.main.async {
                self.topRawIdentifier = label
                self.topLabel = self.humanize(label)
                self.topConfidence = confidence
            }
        }
    }

    /// Configure the analyzer for the given input format. Safe to call
    /// repeatedly; all mutations to `streamAnalyzer` are serialized on
    /// `analysisQueue` so they can't race with `analyze` or `reset`.
    func configure(with format: AVAudioFormat) {
        analysisQueue.async { [weak self] in
            guard let self else { return }

            // Tear down any previous analyzer first.
            self.streamAnalyzer?.completeAnalysis()
            self.streamAnalyzer = nil
            self.request = nil

            do {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                request.windowDuration = CMTime(seconds: 0.975, preferredTimescale: 48_000)
                request.overlapFactor = 0.5

                let analyzer = SNAudioStreamAnalyzer(format: format)
                try analyzer.add(request, withObserver: self.observer)

                self.request = request
                self.streamAnalyzer = analyzer
            } catch {
                // If the built-in classifier isn't available on this OS
                // the app still runs; analyze() calls become no-ops.
                self.streamAnalyzer = nil
                self.request = nil
            }
        }
    }

    /// Feed a buffer to the classifier. The buffer is copied before the
    /// async dispatch because AVAudioEngine may recycle the original
    /// buffer after the tap callback returns.
    func analyze(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
        let framePosition = time.sampleTime
        analysisQueue.async { [weak self] in
            self?.streamAnalyzer?.analyze(copy, atAudioFramePosition: framePosition)
        }
    }

    /// Complete the current analysis and clear the published label. The
    /// teardown is serialized with any in-flight `analyze` calls.
    func reset() {
        analysisQueue.async { [weak self] in
            self?.streamAnalyzer?.completeAnalysis()
        }
        DispatchQueue.main.async { [weak self] in
            self?.topLabel = nil
            self?.topRawIdentifier = nil
            self?.topConfidence = 0
        }
    }

    /// Turn Apple's underscore-snake identifiers ("car_horn") into a
    /// friendly label ("Car horn").
    private func humanize(_ identifier: String) -> String {
        let spaced = identifier.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

/// Private observer that forwards the top classification for each result.
private final class ClassifierObserver: NSObject, SNResultsObserving {
    var onResult: ((String, Double) -> Void)?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard
            let classification = result as? SNClassificationResult,
            let top = classification.classifications.first
        else { return }
        onResult?(top.identifier, top.confidence)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
