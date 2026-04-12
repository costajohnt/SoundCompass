import SwiftUI

/// Developer-only panel surfaced by flipping *Show DSP stats* in settings.
/// Renders a compact grid of internal DSP state: smoothed direction,
/// loudness, current classifier guess, front/back resolver slope, yaw
/// sweep distance. Not localised.
struct DebugStatsView: View {
    @ObservedObject var detector: AudioDirectionDetector

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DSP STATS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
                .kerning(1)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row(label: "direction", value: String(format: "%+.3f", detector.direction))
                row(label: "magnitude", value: String(format: "%.3f", detector.magnitude))
                row(label: "approx dB", value: approximateDB)
                row(label: "band",      value: detector.dominantBandName ?? "–")
                row(label: "label",     value: detector.classifierLabel ?? "–")
                row(label: "raw id",    value: detector.classifierRawIdentifier ?? "–")
                row(label: "confidence", value: String(format: "%.0f%%", detector.classifierConfidence * 100))
                row(label: "hazard",    value: detector.isHazardActive ? "YES" : "no")
                row(label: "yaw sweep", value: String(format: "%.1f°", detector.yawRangeDegrees))
                row(label: "resolver",  value: resolverDescription)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white.opacity(0.85))
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func row(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .foregroundStyle(.white)
        }
    }

    private var resolverDescription: String {
        switch detector.frontBackResolution {
        case .unknown: return "unknown"
        case .needsRotation(let deg): return String(format: "need +%.0f°", max(0, 15 - deg))
        case .front: return "FRONT"
        case .back:  return "BACK"
        }
    }

    /// Very rough dB SPL estimate. The detector's `magnitude` is a scaled
    /// RMS float in `[0, 1]`; we turn that into an approximate dB value
    /// by treating 1.0 as 94 dB SPL (the iPhone's sensitivity figure) and
    /// letting 0 asymptote to negative infinity. This is for the debug
    /// panel only — it is **not** a calibrated sound-level meter.
    private var approximateDB: String {
        guard detector.magnitude > 1e-4 else { return "–" }
        let db = 94 + 20 * log10(max(detector.magnitude, 1e-4))
        return String(format: "%.0f dB SPL*", db)
    }
}
