import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` that `HazardNotifier` uses,
/// so tests can drive the authorization state machine without the
/// real center (whose settings object cannot be constructed).
protocol HazardNotificationCenter: AnyObject {
    func requestAlertAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Bool) -> Void
    )
    func fetchAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void)
    func addRequest(_ request: UNNotificationRequest)
}

/// `HazardNotificationCenter` backed by `UNUserNotificationCenter.current()`.
final class SystemHazardNotificationCenter: HazardNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func requestAlertAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Bool) -> Void
    ) {
        center.requestAuthorization(options: options) { granted, _ in completion(granted) }
    }

    func fetchAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { completion($0.authorizationStatus) }
    }

    func addRequest(_ request: UNNotificationRequest) {
        center.add(request, withCompletionHandler: nil)
    }
}

/// Posts a local iOS notification when a hazard sound is detected while
/// the app is in the background. Foreground detection already surfaces
/// the big red hazard banner in `ContentView`, so the notification is
/// strictly a fallback for "the user is doing something else and a
/// siren just started".
///
/// Authorization is requested in the foreground, when the user starts
/// listening or turns on "Alert on hazard sounds"
/// (`requestAuthorizationIfNeeded`), and the current status is read on
/// launch and on every return to the foreground
/// (`refreshAuthorization`). Requesting lazily from `post` would put the
/// prompt up while the user is not looking and drop the very hazard the
/// notification is for, so that path is only a fallback. While a request
/// is pending, further posts are dropped instead of asking again.
///
/// The interruption level is `.timeSensitive`, which needs the
/// Time Sensitive Notifications entitlement declared in
/// `SoundCompass/SoundCompass.entitlements`; without it iOS silently
/// downgrades to `.active`. Critical alerts (`.defaultCritical`) require
/// a separate Apple-approved entitlement this app does not have, so the
/// sound is the regular default.
final class HazardNotifier {

    enum AuthState: Equatable {
        case unknown
        case requesting
        case granted
        case denied
    }

    private let center: HazardNotificationCenter
    private let onMain: (@escaping () -> Void) -> Void
    private let now: () -> Date
    private(set) var authState: AuthState = .unknown
    private var lastPostedAt: Date = .distantPast
    private let minInterval: TimeInterval = 10.0

    private static let options: UNAuthorizationOptions = [.alert, .sound, .timeSensitive]

    init(
        center: HazardNotificationCenter = SystemHazardNotificationCenter(),
        onMain: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
        now: @escaping () -> Date = { Date() }
    ) {
        self.center = center
        self.onMain = onMain
        self.now = now
        refreshAuthorization()
    }

    /// Reads the current system status so `authState` matches what the
    /// user set in iOS Settings. Leaves a pending request alone.
    func refreshAuthorization() {
        center.fetchAuthorizationStatus { [weak self] status in
            guard let self else { return }
            self.onMain {
                guard self.authState != .requesting else { return }
                switch status {
                case .authorized, .provisional, .ephemeral:
                    self.authState = .granted
                case .denied:
                    self.authState = .denied
                case .notDetermined:
                    self.authState = .unknown
                @unknown default:
                    self.authState = .unknown
                }
            }
        }
    }

    /// Shows the system prompt if the user has not answered it yet. Call
    /// from the foreground: when listening starts or hazard alerts are
    /// turned on.
    func requestAuthorizationIfNeeded() {
        guard authState == .unknown else { return }
        requestAuthorization(thenDeliver: nil)
    }

    func post(label: String, direction: Double, allowed: Bool) {
        guard allowed else { return }

        // Heavy rate-limit so a continuous siren doesn't produce dozens
        // of notifications.
        let now = self.now()
        guard now.timeIntervalSince(lastPostedAt) > minInterval else { return }

        switch authState {
        case .denied, .requesting:
            return
        case .granted:
            deliver(label: label, direction: direction)
            lastPostedAt = now
        case .unknown:
            // Fallback only: the foreground request normally ran already.
            lastPostedAt = now
            requestAuthorization(thenDeliver: (label, direction))
        }
    }

    private func requestAuthorization(thenDeliver pending: (label: String, direction: Double)?) {
        authState = .requesting
        center.requestAlertAuthorization(options: Self.options) { [weak self] granted in
            guard let self else { return }
            self.onMain {
                self.authState = granted ? .granted : .denied
                if granted, let pending {
                    self.deliver(label: pending.label, direction: pending.direction)
                    self.lastPostedAt = self.now()
                }
            }
        }
    }

    private func deliver(label: String, direction: Double) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Hazard sound detected")
        content.body = "\(label) · \(DirectionLabel.label(for: direction))"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "hazard-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        center.addRequest(request)
    }
}
