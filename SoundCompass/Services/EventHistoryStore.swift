import Combine
import Foundation

/// A bounded log of notable direction events. The detector pushes an
/// entry every time the classifier produces a new label above the
/// confidence threshold so the user can flip through a "what was that?"
/// timeline if they missed something.
///
/// The history is in-memory only — there is no persistence across
/// launches, which keeps privacy leakage to zero.
final class EventHistoryStore: ObservableObject {

    struct Event: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let label: String
        let rawIdentifier: String?
        let direction: Double
        let magnitude: Double
        let isHazard: Bool
    }

    @Published private(set) var events: [Event] = []

    private let maxEvents: Int
    private var lastRawIdentifier: String?
    private var lastTimestamp: Date = .distantPast
    private let minInterval: TimeInterval = 0.8

    init(maxEvents: Int = 50) {
        self.maxEvents = maxEvents
    }

    /// Records an event. Consecutive events with the same identifier
    /// within `minInterval` are coalesced so a continuous sound doesn't
    /// flood the timeline.
    func record(
        label: String,
        rawIdentifier: String?,
        direction: Double,
        magnitude: Double,
        isHazard: Bool
    ) {
        let now = Date()
        if rawIdentifier == lastRawIdentifier,
           now.timeIntervalSince(lastTimestamp) < minInterval {
            return
        }

        lastTimestamp = now
        lastRawIdentifier = rawIdentifier

        let event = Event(
            timestamp: now,
            label: label,
            rawIdentifier: rawIdentifier,
            direction: direction,
            magnitude: magnitude,
            isHazard: isHazard
        )

        // Prepend so the most recent event shows at the top of the list.
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    func clear() {
        events.removeAll()
        lastRawIdentifier = nil
        lastTimestamp = .distantPast
    }
}
