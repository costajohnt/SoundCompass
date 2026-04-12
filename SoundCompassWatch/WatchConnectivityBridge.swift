import Combine
import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

/// Receives direction updates from the iPhone app and publishes them to
/// the SwiftUI Watch view. The iPhone side lives in
/// `WatchSessionManager`.
final class WatchConnectivityBridge: NSObject, ObservableObject {

    @Published private(set) var direction: Double = 0
    @Published private(set) var magnitude: Double = 0
    @Published private(set) var label: String?
    @Published private(set) var lastUpdate: Date?

    private let session: WCSession = .default

    // Widget reload throttle — only reload when the direction label changes.
    private var lastWidgetLabel: String?

    // Haptic feedback throttle. The watch plays a short tap whenever a
    // loud sound arrives from a direction that's meaningfully different
    // from the last tap so the user gets a wrist cue even if they're not
    // looking at the screen.
    private var lastHapticDirection: Double = 0
    private var lastHapticAt: Date = .distantPast
    private let hapticMinInterval: TimeInterval = 0.6
    private let hapticMinMagnitude: Double = 0.5
    private let hapticMinDelta: Double = 0.35

    override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Returns `true` if we haven't heard from the phone for more than
    /// `threshold` seconds, so the UI can show a "stale" state.
    func isStale(threshold: TimeInterval = 2.0) -> Bool {
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > threshold
    }

    private func apply(_ payload: [String: Any]) {
        guard let update = DirectionUpdate(dictionary: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.direction = update.direction
            self.magnitude = update.magnitude
            self.label = update.label
            self.lastUpdate = Date()

            // Persist for the complication so it has a value to show on
            // its next timeline refresh. Both the watch app and the
            // SoundCompassWatchWidgets extension read this key.
            UserDefaults.standard.set(update.direction, forKey: "soundcompass.watch.lastDirection")

            // Only reload widget timelines when the direction label
            // actually changes to avoid excessive reload requests.
            let newLabel = DirectionLabel.label(for: update.direction)
            if newLabel != self.lastWidgetLabel {
                self.lastWidgetLabel = newLabel
                WidgetCenter.shared.reloadAllTimelines()
            }

            self.maybePlayHaptic(update: update)
        }
    }

    /// Play a short haptic tap on the wrist when a loud sound comes from
    /// a meaningfully different direction than the last time we tapped.
    /// Throttled to at most ~1.5 Hz so the watch doesn't become a
    /// vibration factory.
    private func maybePlayHaptic(update: DirectionUpdate) {
        guard update.magnitude >= hapticMinMagnitude else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHapticAt) > hapticMinInterval else { return }
        guard abs(update.direction - lastHapticDirection) >= hapticMinDelta else { return }

        // Pick a haptic flavor that matches the lateral position — a
        // directionUp tick for "straight ahead", a notification for
        // anything off-center.
        let type: WKHapticType
        switch update.direction {
        case ..<(-0.20):
            type = .directionUp
        case ..<(0.20):
            type = .click
        default:
            type = .directionDown
        }
        WKInterfaceDevice.current().play(type)
        lastHapticAt = now
        lastHapticDirection = update.direction
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        apply(applicationContext)
    }
}
