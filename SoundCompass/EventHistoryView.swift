import SwiftUI
import UniformTypeIdentifiers

/// Scrollable, chronological list of every classifier label the detector
/// has seen during the current session. The first row is the most
/// recent. Hazard events (sirens, alarms, horns) are flagged in red so
/// you can scan the list for "what was that loud thing 20 seconds ago?".
struct EventHistoryView: View {
    @ObservedObject var store: EventHistoryStore
    @ObservedObject var stats: SessionStats
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Group {
                if store.events.isEmpty {
                    ContentUnavailableView(
                        "No events yet",
                        systemImage: "waveform.badge.magnifyingglass",
                        description: Text("Sounds the classifier identifies while SoundCompass is listening will appear here.")
                    )
                } else {
                    List {
                        Section("Session") {
                            SessionSummary(snapshot: stats.snapshot)
                        }
                        Section("Events") {
                            ForEach(store.events) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recent sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.events.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                store.clear()
                            } label: {
                                Label("Clear events", systemImage: "trash")
                            }
                            ShareLink(
                                item: EventCSV(csv: stats.csv(events: store.events)),
                                preview: SharePreview("SoundCompass events.csv", image: Image(systemName: "doc.text"))
                            ) {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// The CSV export as a `Transferable`, so no temp file is written until
/// the user actually shares (the previous version wrote one on every body
/// evaluation).
private struct EventCSV: Transferable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { item in
            Data(item.csv.utf8)
        }
        .suggestedFileName("SoundCompass events.csv")
    }
}

private struct SessionSummary: View {
    let snapshot: SessionStats.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                summaryCell(title: "Duration", value: formattedDuration)
                Spacer()
                summaryCell(title: "Events", value: "\(snapshot.totalEvents)")
                Spacer()
                summaryCell(title: "Hazards", value: "\(snapshot.hazardCount)", tint: snapshot.hazardCount > 0 ? .red : .primary)
            }
            if let topLabel = snapshot.topLabel {
                Text("Most frequent sound: \(topLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let topDirection = snapshot.topDirectionBucket {
                Text("Most frequent direction: \(topDirection)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryCell(title: LocalizedStringKey, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private var formattedDuration: String {
        let total = Int(snapshot.duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct EventRow: View {
    let event: EventHistoryStore.Event

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .medium
        return df
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: event.label)
                        .font(.body.weight(.semibold))
                    if event.isHazard {
                        Text("HAZARD")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text("\(DirectionLabel.label(for: event.direction)) · \(Int(event.magnitude * 100))% loudness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: EventRow.timeFormatter.string(from: event.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        event.isHazard ? "exclamationmark.triangle.fill" : "waveform"
    }

    private var tint: Color {
        event.isHazard ? .red : .cyan
    }
}

#Preview {
    let store = EventHistoryStore()
    store.record(label: "Siren", rawIdentifier: "siren", direction: -0.8, magnitude: 0.9, isHazard: true)
    store.record(label: "Speech", rawIdentifier: "speech", direction: 0.1, magnitude: 0.5, isHazard: false)
    let stats = SessionStats()
    stats.begin()
    stats.record(label: "Siren", direction: -0.8, isHazard: true)
    stats.record(label: "Speech", direction: 0.1, isHazard: false)
    return EventHistoryView(store: store, stats: stats, isPresented: .constant(true))
}
