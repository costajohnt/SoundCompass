import Foundation
import UserNotifications

/// Posts a local iOS notification when a hazard sound is detected while
/// the app is in the background. Foreground detection already surfaces
/// the big red hazard banner in `ContentView`, so the notification is
/// strictly a fallback for "the user is doing something else and a
/// siren just started".
///
/// `HazardNotifier` requests authorization lazily the first time a
/// hazard is posted; if the user denies it, the class silently becomes
/// a no-op for the rest of the session.
///
/// The interruption level is `.timeSensitive`, which needs the
/// Time Sensitive Notifications entitlement declared in
/// `SoundCompass/SoundCompass.entitlements`; without it iOS silently
/// downgrades to `.active`. Critical alerts (`.defaultCritical`) require
/// a separate Apple-approved entitlement this app does not have, so the
/// sound is the regular default.
final class HazardNotifier {

    private let center = UNUserNotificationCenter.current()
    private var authState: AuthState = .unknown
    private var lastPostedAt: Date = .distantPast
    private let minInterval: TimeInterval = 10.0

    private enum AuthState {
        case unknown
        case granted
        case denied
    }

    func post(label: String, direction: Double, allowed: Bool) {
        guard allowed else { return }

        // Heavy rate-limit so a continuous siren doesn't produce dozens
        // of notifications.
        let now = Date()
        guard now.timeIntervalSince(lastPostedAt) > minInterval else { return }

        switch authState {
        case .denied:
            return
        case .granted:
            deliver(label: label, direction: direction)
            lastPostedAt = now
        case .unknown:
            center.requestAuthorization(options: [.alert, .sound, .timeSensitive]) { [weak self] granted, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.authState = granted ? .granted : .denied
                    if granted {
                        self.deliver(label: label, direction: direction)
                        self.lastPostedAt = Date()
                    }
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
        center.add(request, withCompletionHandler: nil)
    }
}
