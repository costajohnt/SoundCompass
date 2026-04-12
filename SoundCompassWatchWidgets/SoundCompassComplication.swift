import SwiftUI
import WidgetKit

/// A glanceable watch face complication that shows the last direction we
/// heard through the WatchConnectivity bridge. The watchOS app persists
/// its last direction in a shared App Group-less UserDefaults key and the
/// complication re-reads it on each timeline refresh.
///
/// The complication is intentionally light on work: it is not wired to
/// its own CoreMotion or microphone, just to a cached direction value
/// from the phone. When the user opens the watch app the live
/// `WatchContentView` takes over and drives the full compass.
struct SoundCompassComplication: Widget {
    let kind: String = "SoundCompassComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("SoundCompass")
        .description("Last known sound direction.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let direction: Double
    let label: String
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), direction: 0, label: "Ahead")
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 60 s; the WatchConnectivity bridge writes a
        // defaults key in SoundCompassComplicationDefaults.swift and
        // we pick it up on the next timeline refresh.
        let next = Calendar.current.date(byAdding: .second, value: 60, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> ComplicationEntry {
        let direction = UserDefaults.standard.double(forKey: "soundcompass.watch.lastDirection")
        return ComplicationEntry(
            date: Date(),
            direction: direction,
            label: DirectionLabel.label(for: direction)
        )
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: arrowSymbol)
                        .font(.title3)
                    Text(abbreviation)
                        .font(.caption2.weight(.semibold))
                }
            }
        case .accessoryInline:
            Label(entry.label, systemImage: arrowSymbol)
        case .accessoryCorner:
            Image(systemName: arrowSymbol)
                .widgetLabel(entry.label)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: arrowSymbol)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("SoundCompass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.label)
                        .font(.headline)
                }
            }
        default:
            Text(entry.label)
        }
    }

    private var arrowSymbol: String {
        switch entry.direction {
        case ..<(-0.66): return "arrow.left"
        case ..<(-0.20): return "arrow.up.left"
        case ..<(0.20):  return "arrow.up"
        case ..<(0.66):  return "arrow.up.right"
        default:         return "arrow.right"
        }
    }

    private var abbreviation: String {
        switch entry.direction {
        case ..<(-0.66): return "L"
        case ..<(-0.20): return "L"
        case ..<(0.20):  return "•"
        case ..<(0.66):  return "R"
        default:         return "R"
        }
    }
}

@main
struct SoundCompassWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SoundCompassComplication()
    }
}
