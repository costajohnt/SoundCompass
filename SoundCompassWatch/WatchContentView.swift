import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge

    var body: some View {
        VStack(spacing: 4) {
            CompassView(
                direction: bridge.direction,
                magnitude: bridge.magnitude
            )
            .frame(maxHeight: 110)

            VStack(spacing: 2) {
                Text(DirectionLabel.label(for: bridge.direction))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)

                if let label = bridge.label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if bridge.lastUpdate == nil {
                    Text("Waiting for phone…")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                } else if bridge.isStale() {
                    Text("No signal")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchConnectivityBridge())
}
