import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island rendering for the SoundCompass Live
/// Activity. The `ContentState` is produced by `LiveActivityController`
/// inside the iOS app target.
struct SoundCompassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoundCompassActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("SoundCompass", systemImage: "mic.circle.fill")
                        .foregroundStyle(.cyan)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.magnitude * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.center) {
                    MiniCompass(direction: context.state.direction)
                        .frame(height: 40)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        if let classifierLabel = context.state.classifierLabel {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.4))
                            Text(classifierLabel)
                                .font(.footnote)
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: "mic.circle.fill")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text(compactLabel(for: context.state.direction))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: compactSymbol(for: context.state.direction))
                    .foregroundStyle(.cyan)
            }
        }
    }

    private func compactLabel(for direction: Double) -> String {
        let degrees = Int((direction * 90).rounded())
        return "\(degrees > 0 ? "+" : "")\(degrees)°"
    }

    private func compactSymbol(for direction: Double) -> String {
        switch direction {
        case ..<(-0.66): return "arrow.left"
        case ..<(-0.20): return "arrow.up.left"
        case ..<(0.20):  return "arrow.up"
        case ..<(0.66):  return "arrow.up.right"
        default:         return "arrow.right"
        }
    }
}

/// The Lock Screen banner layout.
private struct LockScreenView: View {
    let state: SoundCompassActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            MiniCompass(direction: state.direction)
                .frame(width: 60, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.label)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                if let classifierLabel = state.classifierLabel {
                    Text(classifierLabel)
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
                ProgressView(value: state.magnitude)
                    .tint(.cyan)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

/// A tiny version of the compass half-dial for the Dynamic Island and
/// Lock Screen layouts — we can't reuse the full `CompassView` here
/// because the widget runtime doesn't have access to the iOS target's
/// module and `Shared/CompassView.swift` pulls in symbols we don't
/// want in the widget binary.
private struct MiniCompass: View {
    let direction: Double

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height)
            let radius = min(proxy.size.width / 2, proxy.size.height)
            let angle = Angle.degrees(270 + max(-1, min(1, direction)) * 90)
            let tip = CGPoint(
                x: center.x + radius * CGFloat(cos(angle.radians)),
                y: center.y + radius * CGFloat(sin(angle.radians))
            )
            ZStack {
                Path { path in
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(360),
                        clockwise: false
                    )
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 2)

                Path { path in
                    path.move(to: center)
                    path.addLine(to: tip)
                }
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                Circle()
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5)
                    .position(tip)
            }
        }
    }
}
