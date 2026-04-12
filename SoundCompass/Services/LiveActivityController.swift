import ActivityKit
import Combine
import Foundation

/// Starts, updates, and ends the SoundCompass Live Activity (Dynamic
/// Island + Lock Screen) as the detector's direction changes. Throttles
/// updates so we don't churn ActivityKit more than a few times a second.
///
/// Live Activities are an iOS 16.1+ feature. When unsupported the entire
/// controller becomes a no-op and the app still runs normally.
final class LiveActivityController {

    private var activity: Activity<SoundCompassActivityAttributes>?
    private var lastUpdate: Date = .distantPast
    private let minInterval: TimeInterval = 0.3

    func start() {
        guard activity == nil else { return }

        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else { return }

        let attributes = SoundCompassActivityAttributes(title: "SoundCompass")
        let state = SoundCompassActivityAttributes.ContentState(
            direction: 0,
            magnitude: 0,
            label: "Listening…",
            classifierLabel: nil
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func update(
        direction: Double,
        magnitude: Double,
        label: String,
        classifierLabel: String?
    ) {
        guard let activity else { return }
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) > minInterval else { return }
        lastUpdate = now

        let state = SoundCompassActivityAttributes.ContentState(
            direction: direction,
            magnitude: magnitude,
            label: label,
            classifierLabel: classifierLabel
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func stop() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        lastUpdate = .distantPast
    }
}
