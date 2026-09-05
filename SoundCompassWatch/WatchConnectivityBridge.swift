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
    @Published private(set) var isHazard: Bool = false

    private let session: WCSession = .default

    /// WidgetKit grants a small daily reload budget (a few dozen), so the
    /// complication is refreshed at most once per `widgetReloadInterval`
    /// and once more when a hazard starts. The written defaults value is
    /// always current; only the visible refresh is throttled.
    private var lastWidgetReload: Date = .distantPast
    private let widgetReloadInterval: TimeInterval = 5 * 60

    // Haptic feedback throttle. The watch plays a short tap whenever a
    // loud sound arrives from a direction that's meaningfully different
    // from the last tap so the user gets a wrist cue even if they're not
    // looking at the screen.
    private var lastHapticDirection: Double = 0
    private var lastHapticAt: Date = .distantPast
    private var lastHazardHapticAt: Date = .distantPast
    private let hapticMinInterval: TimeInterval = 0.6
    private let hazardHapticMinInterval: TimeInterval = 3.0
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
    func isStale(threshold: TimeInterval = 2.0, now: Date = Date()) -> Bool {
        guard let lastUpdate else { return true }
        return now.timeIntervalSince(lastUpdate) > threshold
    }

    private func apply(_ payload: [String: Any]) {
        guard let update = DirectionUpdate(dictionary: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hazardBegan = update.isHazard && !self.isHazard
            self.direction = update.direction
            self.magnitude = update.magnitude
            self.label = update.label
            self.isHazard = update.isHazard
            self.lastUpdate = Date()

            // Persist for the complication in the shared App Group so it
            // has a value to show on its next timeline refresh.
            let store = SharedDefaults.store
            store.set(update.direction, forKey: SharedDefaults.lastDirectionKey)
            store.set(Date().timeIntervalSince1970, forKey: SharedDefaults.lastUpdateKey)

            let now = Date()
            if hazardBegan || now.timeIntervalSince(self.lastWidgetReload) > self.widgetReloadInterval {
                self.lastWidgetReload = now
                WidgetCenter.shared.reloadAllTimelines()
            }

            if hazardBegan {
                self.playHazardHaptic(now: now)
            } else {
                self.maybePlayHaptic(update: update, now: now)
            }
        }
    }

    /// One firm notification tap when the phone's hazard banner comes up.
    private func playHazardHaptic(now: Date) {
        guard now.timeIntervalSince(lastHazardHapticAt) > hazardHapticMinInterval else { return }
        WKInterfaceDevice.current().play(.notification)
        lastHazardHapticAt = now
        lastHapticAt = now
        lastHapticDirection = direction
    }

    /// Play a short haptic tap on the wrist when a loud sound comes from
    /// a meaningfully different direction than the last time we tapped.
    /// Throttled to at most ~1.5 Hz so the watch doesn't become a
    /// vibration factory.
    private func maybePlayHaptic(update: DirectionUpdate, now: Date) {
        guard update.magnitude >= hapticMinMagnitude else { return }
        guard now.timeIntervalSince(lastHapticAt) > hapticMinInterval else { return }
        guard abs(update.direction - lastHapticDirection) >= hapticMinDelta else { return }

        // Pick a haptic flavor that matches the lateral position — a
        // directionUp tick for "left", a click for "straight ahead", a
        // directionDown tick for "right".
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
