import AVFoundation
import Combine
import Foundation
import SoundAnalysis

/// Pure bookkeeping for "what is the current classifier label", separated
/// from `SoundClassifier` so the expiry rules can be unit-tested.
///
/// Rules:
/// * A result at or above `minConfidence` becomes the current label and
///   refreshes its timestamp.
/// * A result *below* the threshold clears the label: the classifier has
///   looked at fresh audio and no longer hears that sound.
/// * A label older than `maxAge` with no refresh is cleared by
///   `expire(now:)` even if no new result arrived (analysis stalled).
///
/// Before this existed the label was set once and never cleared, so a
/// single "siren" re-armed the hazard banner for every later loud sound.
struct ClassifierLabelTracker: Equatable {

    struct Snapshot: Equatable {
        var rawIdentifier: String?
        var label: String?
        var confidence: Double
    }

    var minConfidence: Double
    var maxAge: TimeInterval

    private(set) var current = Snapshot(rawIdentifier: nil, label: nil, confidence: 0)
    private(set) var lastConfidentAt: Date = .distantPast

    init(minConfidence: Double = 0.5, maxAge: TimeInterval = 2.5) {
        self.minConfidence = minConfidence
        self.maxAge = maxAge
    }

    /// Returns `true` when the snapshot changed.
    @discardableResult
    mutating func ingest(identifier: String, confidence: Double, now: Date) -> Bool {
        if confidence >= minConfidence {
            lastConfidentAt = now
            let next = Snapshot(
                rawIdentifier: identifier,
                label: ClassifierLabelTracker.humanize(identifier),
                confidence: confidence
            )
            guard next != current else { return false }
            current = next
            return true
        }
        return clear()
    }

    /// Clears a label that has not been refreshed within `maxAge`.
    @discardableResult
    mutating func expire(now: Date) -> Bool {
        guard current.rawIdentifier != nil else { return false }
        guard now.timeIntervalSince(lastConfidentAt) > maxAge else { return false }
        return clear()
    }

    @discardableResult
    mutating func clear() -> Bool {
        guard current.rawIdentifier != nil || current.confidence != 0 else { return false }
        current = Snapshot(rawIdentifier: nil, label: nil, confidence: 0)
        return true
    }

    /// Turn Apple's underscore-snake identifiers ("car_horn") into a
    /// friendly label ("Car horn").
    static func humanize(_ identifier: String) -> String {
        let spaced = identifier.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

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
    var minConfidence: Double {
        get { tracker.minConfidence }
        set { tracker.minConfidence = newValue }
    }

    private let analysisQueue = DispatchQueue(label: "com.soundcompass.classifier", qos: .userInitiated)
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let observer = ClassifierObserver()

    /// Main-thread only.
    private var tracker = ClassifierLabelTracker()

    init() {
        observer.onResult = { [weak self] label, confidence in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.tracker.ingest(identifier: label, confidence: confidence, now: Date()) {
                    self.publish()
                }
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
                Log.classifier.error("Built-in classifier unavailable: \(error.localizedDescription, privacy: .public)")
                self.streamAnalyzer = nil
                self.request = nil
            }
        }
    }

    /// Feed a buffer to the classifier. The buffer is dispatched to the
    /// analysis queue by reference, exactly as Apple's SoundAnalysis
    /// sample code does: AVAudioEngine hands the tap a fresh buffer
    /// object per callback, so holding it briefly is safe, and copying it
    /// would allocate on the audio thread.
    func analyze(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        let framePosition = time.sampleTime
        analysisQueue.async { [weak self] in
            self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: framePosition)
        }
    }

    /// Drop a label that has not been refreshed recently. Call from the
    /// main thread on every DSP update.
    func expireStaleLabel(now: Date = Date()) {
        if tracker.expire(now: now) {
            publish()
        }
    }

    /// Complete the current analysis and clear the published label. The
    /// teardown is serialized with any in-flight `analyze` calls.
    func reset() {
        analysisQueue.async { [weak self] in
            self?.streamAnalyzer?.completeAnalysis()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tracker.clear()
            self.publish()
        }
    }

    private func publish() {
        let snapshot = tracker.current
        topRawIdentifier = snapshot.rawIdentifier
        topLabel = snapshot.label
        topConfidence = snapshot.confidence
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

    func request(_ request: SNRequest, didFailWithError error: Error) {
        Log.classifier.error("Classification failed: \(error.localizedDescription, privacy: .public)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
