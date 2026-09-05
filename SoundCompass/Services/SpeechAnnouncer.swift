import AVFoundation
import Foundation

/// Speaks short direction announcements through the system speech
/// synthesiser so a user who cannot look at the screen can still get a
/// "voice from your left" cue through their hearing ear (or an external
/// speaker / Bluetooth headset in the other ear).
///
/// Announcements are heavily rate-limited so the app does not become a
/// nagging chatterbox:
///
/// * At most one announcement every `minInterval` seconds.
/// * Skipped when the loudness is below `loudnessThreshold`.
/// * Skipped when neither the direction (> `directionHysteresis`) nor the
///   classifier label has changed.
///
/// The announcer reports when it is speaking via `onSpeakingChanged` so
/// `AudioDirectionDetector` can mute the microphone path: the phone's own
/// speaker is 10 cm from the mics, and without the mute the classifier
/// labels every callout "speech" and the arrow points at the speaker.
final class SpeechAnnouncer: NSObject {

    var isEnabled: Bool = false

    /// Multiplier applied to `AVSpeechUtteranceDefaultSpeechRate`. Driven by
    /// `SettingsStore.speechRate`.
    var rateMultiplier: Double = 1.05

    /// Optional voice identifier from `AVSpeechSynthesisVoice.identifier`.
    /// When `nil` we fall back to the system default for the user's
    /// preferred language.
    var voiceIdentifier: String?

    /// Called on the main thread when synthesis starts (`true`) and when
    /// it finishes or is cancelled (`false`).
    var onSpeakingChanged: ((Bool) -> Void)?

    /// Test hook: receives every phrase that passes the rate limiter.
    /// When `speaksAloud` is `false` the synthesizer is not engaged.
    var onPhrase: ((String) -> Void)?
    var speaksAloud: Bool = true

    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let minInterval: TimeInterval
    private let loudnessThreshold: Double = 0.3
    private let directionHysteresis: Double = 0.3

    private var lastAnnouncement: Date = .distantPast
    private var lastDirection: Double = 0
    private var lastLabel: String?

    init(minInterval: TimeInterval = 2.0) {
        self.minInterval = minInterval
        super.init()
        synthesizer.delegate = self
    }

    func announce(direction: Double, magnitude: Double, label: String?, now: Date = Date()) {
        guard isEnabled else { return }
        guard magnitude >= loudnessThreshold else { return }
        guard now.timeIntervalSince(lastAnnouncement) > minInterval else { return }

        let directionChanged = abs(direction - lastDirection) >= directionHysteresis
        let labelChanged = label != lastLabel
        guard directionChanged || labelChanged else { return }

        let phrase = buildPhrase(direction: direction, label: label)
        onPhrase?(phrase)
        if speaksAloud {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rateMultiplier)
            utterance.volume = 0.9
            utterance.pitchMultiplier = 1.0
            if let voiceIdentifier,
               let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            }
            synthesizer.speak(utterance)
        }

        lastAnnouncement = now
        lastDirection = direction
        lastLabel = label
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func buildPhrase(direction: Double, label: String?) -> String {
        let locationWord = DirectionLabel.spokenPhrase(direction: direction)
        if let label, !label.isEmpty {
            return String(localized: "\(label.lowercased()) \(locationWord)")
        } else {
            return String(localized: "Sound from your \(locationWord)")
        }
    }

    private func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        onSpeakingChanged?(speaking)
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        setSpeaking(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        setSpeaking(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        setSpeaking(false)
    }
}
