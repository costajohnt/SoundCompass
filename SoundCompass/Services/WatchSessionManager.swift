import Combine
import Foundation
import WatchConnectivity

/// Streams direction updates from the iPhone app to the Watch companion.
///
/// * When the watch is actively in the foreground, the manager uses
///   `WCSession.sendMessage(_:replyHandler:errorHandler:)` for the lowest
///   possible latency.
/// * When it isn't, it falls back to `updateApplicationContext(_:)` so the
///   latest value is still delivered the next time the watch wakes up.
///
/// Updates are rate-limited to ~6 per second so we don't saturate the IPC
/// channel with tap callbacks. A hazard transition bypasses the rate
/// limit so the watch can escalate its haptic without delay.
final class WatchSessionManager: NSObject, ObservableObject {

    @Published private(set) var isPaired: Bool = false
    @Published private(set) var isReachable: Bool = false

    private let session: WCSession = .default
    private let queue = DispatchQueue(label: "com.soundcompass.watchsession")
    private var lastSent: Date = .distantPast
    private var lastHazard = false
    private let minInterval: TimeInterval = 0.15

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Send a direction update. Safe to call from any thread; internally
    /// hops onto a private queue for rate limiting and delivery.
    func send(direction: Double, magnitude: Double, label: String?, isHazard: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.session.activationState == .activated else { return }

            let now = Date()
            let hazardChanged = isHazard != self.lastHazard
            guard hazardChanged || now.timeIntervalSince(self.lastSent) > self.minInterval else { return }
            self.lastSent = now
            self.lastHazard = isHazard

            let update = DirectionUpdate(
                direction: direction,
                magnitude: magnitude,
                label: label,
                timestamp: now,
                isHazard: isHazard
            )

            if self.session.isReachable {
                self.session.sendMessage(update.toDictionary(), replyHandler: nil) { _ in
                    // Best-effort delivery; ignore transient failures.
                }
            } else {
                try? self.session.updateApplicationContext(update.toDictionary())
            }
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            #if os(iOS)
            self.isPaired = session.isPaired
            #endif
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so a new watch pairing can take over.
        WCSession.default.activate()
    }
    #endif
}
