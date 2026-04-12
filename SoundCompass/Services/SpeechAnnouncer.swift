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
final class SpeechAnnouncer {

    var isEnabled: Bool = false

    /// Multiplier applied to `AVSpeechUtteranceDefaultSpeechRate`. Driven by
    /// `SettingsStore.speechRate`.
    var rateMultiplier: Double = 1.05

    /// Optional voice identifier from `AVSpeechSynthesisVoice.identifier`.
    /// When `nil` we fall back to the system default for the user's
    /// preferred language.
    var voiceIdentifier: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let minInterval: TimeInterval = 2.0
    private let loudnessThreshold: Double = 0.3
    private let directionHysteresis: Double = 0.3

    private var lastAnnouncement: Date = .distantPast
    private var lastDirection: Double = 0
    private var lastLabel: String?

    func announce(direction: Double, magnitude: Double, label: String?) {
        guard isEnabled else { return }
        guard magnitude >= loudnessThreshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnnouncement) > minInterval else { return }

        let directionChanged = abs(direction - lastDirection) >= directionHysteresis
        let labelChanged = label != lastLabel
        guard directionChanged || labelChanged else { return }

        let phrase = buildPhrase(direction: direction, label: label)
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rateMultiplier)
        utterance.volume = 0.9
        utterance.pitchMultiplier = 1.0
        if let voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)

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
            return "\(label.lowercased()) \(locationWord)"
        } else {
            return "Sound from your \(locationWord)"
        }
    }
}
