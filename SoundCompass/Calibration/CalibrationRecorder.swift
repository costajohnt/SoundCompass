import AVFoundation
import Accelerate
import Combine
import Foundation

/// A fixed-duration stereo PCM recording captured by
/// `CalibrationRecorder`, decoded into two Swift float arrays so the
/// offline DSP pipeline can walk them without fighting `AVAudioFile`.
struct CalibrationClip: Equatable {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    /// `-1` when the capture came from the mirrored (front) data source,
    /// so the processor can put its trace in user space exactly like the
    /// live detector does.
    var directionSign: Double = 1

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(left.count) / sampleRate
    }
}

/// Records a short stereo clip through `AVAudioEngine` without touching
/// the main detector. The recorder runs its own engine so the user can
/// kick off a calibration capture while still having the detector
/// running (or not).
///
/// This is an *offline* calibration helper: the recorded samples are
/// held in memory and handed to `CalibrationProcessor` for a one-shot
/// pass through the DSP pipeline. There is no playback path — the
/// goal is to visualize how the DSP sees a known sound, not to play it
/// back verbatim.
final class CalibrationRecorder: ObservableObject {

    enum State: Equatable {
        case idle
        case recording(remaining: TimeInterval)
        case finished
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var clip: CalibrationClip?

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let appendQueue = DispatchQueue(label: "com.soundcompass.calibration.append")
    private var leftBuffer: [Float] = []
    private var rightBuffer: [Float] = []
    private var countdownTimer: Timer?
    private var targetDuration: TimeInterval = 5.0
    private var directionSign: Double = 1

    /// Start a capture of `duration` seconds. The clip is published on
    /// `self.clip` once it finishes.
    func startRecording(duration: TimeInterval = 5.0) {
        guard case .idle = state else { return }

        targetDuration = duration
        leftBuffer.removeAll(keepingCapacity: true)
        rightBuffer.removeAll(keepingCapacity: true)
        clip = nil

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.state = .failed(String(localized: "Microphone access denied."))
                    return
                }
                do {
                    // Same configuration as the live detector, so the
                    // trace is not mirrored relative to the compass.
                    let selection = try AudioSessionConfigurator.configureForStereoCapture(self.session)
                    self.directionSign = selection.directionSign
                    try self.installTap()
                    try self.engine.start()
                    self.state = .recording(remaining: duration)
                    self.startCountdown()
                } catch {
                    self.state = .failed(String(localized: "Could not start recording: \(error.localizedDescription)"))
                }
            }
        }
    }

    func cancel() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .idle
    }

    private func installTap() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "SoundCompass.CalibrationRecorder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "The microphone did not report a usable audio format. Try again.")]
            )
        }
        guard format.channelCount >= 2 else {
            throw NSError(
                domain: "SoundCompass.CalibrationRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "This input only provides mono audio. Disconnect any headset and try again.")]
            )
        }

        // Pre-allocate so the append queue does not grow the arrays
        // incrementally.
        let capacity = Int(targetDuration * format.sampleRate) + 4096
        leftBuffer.reserveCapacity(capacity)
        rightBuffer.reserveCapacity(capacity)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            // The tap block runs on a non-real-time engine thread, so the
            // two Array copies here are acceptable; appends are serialized
            // on `appendQueue` so `finish()` can drain them safely.
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let left = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
            let right = Array(UnsafeBufferPointer(start: channelData[1], count: frames))
            self.appendQueue.async {
                self.leftBuffer.append(contentsOf: left)
                self.rightBuffer.append(contentsOf: right)
            }
        }
    }

    private func startCountdown() {
        let start = Date()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= self.targetDuration {
                timer.invalidate()
                self.finish()
            } else {
                self.state = .recording(remaining: self.targetDuration - elapsed)
            }
        }
    }

    private func finish() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let format = engine.inputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let sign = directionSign

        // Wait for any in-flight appends to drain before reading buffers.
        appendQueue.async { [weak self] in
            guard let self else { return }
            let clip = CalibrationClip(
                left: self.leftBuffer,
                right: self.rightBuffer,
                sampleRate: sampleRate,
                directionSign: sign
            )
            DispatchQueue.main.async {
                self.clip = clip
                self.state = .finished
            }
        }
    }
}
