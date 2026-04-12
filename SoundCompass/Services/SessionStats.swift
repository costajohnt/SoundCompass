import Combine
import Foundation

/// Lightweight counters describing the current listening session.
/// `SessionStats` is reset every time `AudioDirectionDetector.start()`
/// is called and updated as events stream through the pipeline. The
/// settings sheet surfaces a short summary: session duration, total
/// events, hazard count, most common label, most common direction.
final class SessionStats: ObservableObject {

    struct Snapshot: Equatable {
        var startedAt: Date?
        var endedAt: Date?
        var totalEvents: Int
        var hazardCount: Int
        var labelCounts: [String: Int]
        var directionBucketCounts: [String: Int]

        var duration: TimeInterval {
            guard let startedAt else { return 0 }
            return (endedAt ?? Date()).timeIntervalSince(startedAt)
        }

        var topLabel: String? {
            labelCounts.max(by: { $0.value < $1.value })?.key
        }

        var topDirectionBucket: String? {
            directionBucketCounts.max(by: { $0.value < $1.value })?.key
        }
    }

    @Published private(set) var snapshot: Snapshot = SessionStats.emptySnapshot()

    private static func emptySnapshot() -> Snapshot {
        Snapshot(
            startedAt: nil,
            endedAt: nil,
            totalEvents: 0,
            hazardCount: 0,
            labelCounts: [:],
            directionBucketCounts: [:]
        )
    }

    /// Called from `AudioDirectionDetector.start()` on a successful
    /// engine start.
    func begin() {
        snapshot = Self.emptySnapshot()
        snapshot.startedAt = Date()
    }

    /// Called from `AudioDirectionDetector.stop()` so the snapshot
    /// freezes at the end time.
    func end() {
        snapshot.endedAt = Date()
    }

    /// Record a detector event (either hazard or normal classifier
    /// transition). Updates all the running counters.
    func record(
        label: String,
        direction: Double,
        isHazard: Bool
    ) {
        snapshot.totalEvents += 1
        if isHazard { snapshot.hazardCount += 1 }
        snapshot.labelCounts[label, default: 0] += 1
        let bucket = DirectionLabel.label(for: direction)
        snapshot.directionBucketCounts[bucket, default: 0] += 1
    }

    /// Exports the current event list plus session metadata as a CSV
    /// string, suitable for `ShareLink` / `UIActivityViewController`.
    func csv(events: [EventHistoryStore.Event]) -> String {
        var lines: [String] = []
        lines.append("timestamp,label,rawIdentifier,direction,magnitude,hazard")
        for event in events.reversed() {
            let ts = ISO8601DateFormatter().string(from: event.timestamp)
            let rawId = event.rawIdentifier?.replacingOccurrences(of: ",", with: " ") ?? ""
            let label = event.label.replacingOccurrences(of: ",", with: " ")
            lines.append(
                "\(ts),\(label),\(rawId),\(String(format: "%.3f", event.direction)),\(String(format: "%.3f", event.magnitude)),\(event.isHazard)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
