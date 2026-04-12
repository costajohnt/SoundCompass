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
    private var leftBuffer: [Float] = []
    private var rightBuffer: [Float] = []
    private var countdownTimer: Timer?
    private var targetDuration: TimeInterval = 5.0

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
                    self.state = .failed("Microphone access denied.")
                    return
                }
                do {
                    try self.configureSession()
                    try self.installTap()
                    try self.engine.start()
                    self.state = .recording(remaining: duration)
                    self.startCountdown()
                } catch {
                    self.state = .failed("Could not start recording: \(error.localizedDescription)")
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

    private func configureSession() throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothHFP, .defaultToSpeaker])
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtIn)
            if let stereoSource = builtIn.dataSources?.first(where: {
                $0.supportedPolarPatterns?.contains(.stereo) ?? false
            }) {
                try stereoSource.setPreferredPolarPattern(.stereo)
                try builtIn.setPreferredDataSource(stereoSource)
            }
        }
        try session.setActive(true, options: [])
    }

    private func installTap() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount >= 2 else {
            throw NSError(
                domain: "SoundCompass.CalibrationRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "This input only provides mono audio. Disconnect any headset and try again."]
            )
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.append(buffer: buffer)
        }
    }

    private func append(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let left = channelData[0]
        let right = channelData[1]

        // Copy into the growing buffers.
        leftBuffer.append(contentsOf: UnsafeBufferPointer(start: left, count: frames))
        rightBuffer.append(contentsOf: UnsafeBufferPointer(start: right, count: frames))
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

        // Take a copy to freeze the clip.
        let clip = CalibrationClip(
            left: leftBuffer,
            right: rightBuffer,
            sampleRate: sampleRate
        )
        self.clip = clip
        self.state = .finished
    }
}
