import SwiftUI

/// A visual compass shared between the iOS app and the watchOS companion.
///
/// The view draws a half-dial in front of the user and rotates an arrow
/// along it based on `direction` (`-1` = hard left, `+1` = hard right). The
/// arrow's length and color intensity track `magnitude`, so quiet sounds
/// fade toward the center and loud sounds light up the rim.
struct CompassView: View {
    /// Normalized direction in `[-1, 1]`.
    let direction: Double
    /// Normalized loudness in `[0, 1]`.
    let magnitude: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.78)
            let radius = size * 0.42

            ZStack {
                dial(center: center, radius: radius)
                tickMarks(center: center, radius: radius)
                directionArrow(center: center, radius: radius)
                centerDot(at: center)
            }
        }
        .aspectRatio(1.1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Sound direction compass")
        .accessibilityValue(DirectionLabel.accessibilityValue(direction: direction, magnitude: magnitude))
    }

    // MARK: - Pieces

    private func dial(center: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(360),
                clockwise: false
            )
        }
        .stroke(
            LinearGradient(
                colors: [.blue.opacity(0.35), .cyan.opacity(0.7), .blue.opacity(0.35)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 6, lineCap: .round)
        )
    }

    private func tickMarks(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<9, id: \.self) { idx in
            let angle = Angle.degrees(180 + Double(idx) * 22.5)
            let inner = radius - 12
            let outer = radius + 4
            Path { path in
                path.move(to: point(center: center, radius: inner, angle: angle))
                path.addLine(to: point(center: center, radius: outer, angle: angle))
            }
            .stroke(Color.white.opacity(idx == 4 ? 0.9 : 0.35), lineWidth: idx == 4 ? 3 : 2)
        }
    }

    private func directionArrow(center: CGPoint, radius: CGFloat) -> some View {
        // Map direction [-1, 1] onto the 180°–360° upper arc:
        //   direction = -1 → 180° (hard left)
        //   direction =  0 → 270° (straight ahead, top of the dial)
        //   direction = +1 → 360° (hard right)
        let clamped = max(-1.0, min(1.0, direction))
        let angle = Angle.degrees(270 + clamped * 90)

        let length = radius * (0.45 + CGFloat(magnitude) * 0.55)
        let tip = point(center: center, radius: length, angle: angle)

        let color = Color(
            hue: 0.58 - 0.58 * magnitude, // blue → red as it gets loud
            saturation: 0.8,
            brightness: 0.95
        )

        return ZStack {
            Path { path in
                path.move(to: center)
                path.addLine(to: tip)
            }
            .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))

            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .position(tip)
                .shadow(color: color.opacity(0.8), radius: 10)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: direction)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: magnitude)
    }

    private func centerDot(at center: CGPoint) -> some View {
        Circle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 8, height: 8)
            .position(center)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        let r = Double(radius)
        return CGPoint(
            x: center.x + CGFloat(r * cos(angle.radians)),
            y: center.y + CGFloat(r * sin(angle.radians))
        )
    }
}

#Preview {
    CompassView(direction: -0.4, magnitude: 0.7)
        .padding()
        .background(Color.black)
}
