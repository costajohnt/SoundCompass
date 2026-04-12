import AppIntents
import SwiftUI

/// Lightweight bridge between `AppIntent.perform()` and the running
/// `AudioDirectionDetector`. The detector is a `@StateObject` owned by the
/// app scene so we can't access it directly from a Codable intent; instead
/// we stash a weak reference here the first time `SoundCompassApp` wires
/// things up.
///
/// Access is serialized through `registryQueue` so intent invocations
/// running on background queues can't race with `register(_:)` calls
/// from the main actor during app launch.
enum IntentBroker {
    private static let registryQueue = DispatchQueue(label: "com.soundcompass.intentbroker")
    private static weak var currentDetector: AudioDirectionDetector?

    static func register(_ detector: AudioDirectionDetector) {
        registryQueue.sync { currentDetector = detector }
    }

    static var detector: AudioDirectionDetector? {
        registryQueue.sync { currentDetector }
    }
}

/// Start listening via Siri or the Shortcuts app.
///
/// "Hey Siri, start SoundCompass" → microphone permission prompt if needed
/// → detector starts. The intent opens the app so the broker has a
/// detector to talk to; if you would rather run the intent purely in the
/// background, stand up a shared singleton detector and drop
/// `openAppWhenRun = true`.
struct StartListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Start listening"
    static var description = IntentDescription(
        "Starts SoundCompass and begins estimating where nearby sounds come from."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            IntentBroker.detector?.start()
        }
        return .result()
    }
}

/// Stops the detector via Siri or Shortcuts.
struct StopListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop listening"
    static var description = IntentDescription(
        "Stops the SoundCompass microphone and the direction estimator."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            IntentBroker.detector?.stop()
        }
        return .result()
    }
}

/// Speaks the current direction back to the user. Useful when you can't
/// (or don't want to) look at the screen: "Hey Siri, where is the sound?"
struct AnnounceDirectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Announce current direction"
    static var description = IntentDescription(
        "Speaks the most recent sound direction estimate out loud."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let phrase = await MainActor.run { () -> String in
            guard let detector = IntentBroker.detector, detector.isRunning else {
                return "SoundCompass is not listening right now."
            }
            let word = DirectionLabel.spokenPhrase(direction: detector.direction)
            return "Sound from your \(word)."
        }
        return .result(dialog: IntentDialog(stringLiteral: phrase))
    }
}

/// Registers the above intents as Siri-suggested shortcuts on first launch
/// so they show up in the Shortcuts gallery without the user having to
/// go hunt for them.
struct SoundCompassShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Start listening with \(.applicationName)",
            ],
            shortTitle: "Start listening",
            systemImageName: "mic.circle.fill"
        )
        AppShortcut(
            intent: StopListeningIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop listening with \(.applicationName)",
            ],
            shortTitle: "Stop listening",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: AnnounceDirectionIntent(),
            phrases: [
                "Where is the sound in \(.applicationName)",
                "What direction with \(.applicationName)",
            ],
            shortTitle: "Announce direction",
            systemImageName: "speaker.wave.2.fill"
        )
    }
}
