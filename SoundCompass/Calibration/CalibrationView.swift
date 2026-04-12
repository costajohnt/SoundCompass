import Charts
import SwiftUI

/// Calibration screen surfaced from the Settings sheet. Records five
/// seconds of stereo audio, runs it through the offline DSP pipeline,
/// and renders the resulting direction trace as a line chart so users
/// (or contributors) can see how the app sees a known sound without
/// having to stare at the live compass.
struct CalibrationView: View {
    @StateObject private var recorder = CalibrationRecorder()
    @State private var samples: [CalibrationSample] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    intro

                    stateCard

                    if !samples.isEmpty {
                        chart
                        summary
                    }

                    controls
                }
                .padding(24)
            }
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: recorder.clip) { _, newClip in
            guard let clip = newClip else {
                samples = []
                return
            }
            samples = CalibrationProcessor.process(clip: clip)
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Offline trace")
                .font(.headline)
            Text("Record five seconds of a known sound — a clap on your left, a kettle on your right, someone saying your name from behind — and SoundCompass will run the recording through its DSP pipeline and show you how the estimated direction evolved over time. No audio leaves the phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateCard: some View {
        let (icon, title, detail, tint) = stateCopy()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Direction over time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(samples) { sample in
                LineMark(
                    x: .value("Time", sample.time),
                    y: .value("Direction", sample.direction)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.cyan)

                AreaMark(
                    x: .value("Time", sample.time),
                    yStart: .value("Floor", 0),
                    yEnd: .value("Magnitude", sample.magnitude)
                )
                .foregroundStyle(.cyan.opacity(0.15))
            }
            .chartYScale(domain: -1.05 ... 1.05)
            .chartYAxis {
                AxisMarks(position: .leading, values: [-1, -0.5, 0, 0.5, 1]) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(labelForAxis(d))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)))
                        .font(.caption2)
                    AxisGridLine()
                }
            }
            .frame(height: 220)
        }
    }

    private var summary: some View {
        let maxMagnitude = samples.map(\.magnitude).max() ?? 0
        let avgDirection = samples.map(\.direction).reduce(0, +) / Double(max(samples.count, 1))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                summaryCell(label: "Peak loudness", value: String(format: "%.0f%%", maxMagnitude * 100))
                summaryCell(label: "Average direction", value: DirectionLabel.label(for: avgDirection))
                summaryCell(label: "Samples", value: "\(samples.count)")
            }
        }
    }

    private func summaryCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private var controls: some View {
        let isRecording: Bool
        if case .recording = recorder.state { isRecording = true } else { isRecording = false }

        return Button {
            if isRecording {
                recorder.cancel()
            } else {
                recorder.startRecording()
            }
        } label: {
            Label(
                isRecording ? "Cancel recording" : "Record 5 seconds",
                systemImage: isRecording ? "stop.circle.fill" : "record.circle"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecording ? .red : .cyan)
        .controlSize(.large)
    }

    // MARK: - Helpers

    private func stateCopy() -> (String, String, String, Color) {
        switch recorder.state {
        case .idle:
            return (
                "record.circle",
                "Ready",
                "Tap Record to capture five seconds of stereo audio.",
                .cyan
            )
        case .recording(let remaining):
            return (
                "waveform",
                "Recording…",
                String(format: "%.1fs remaining", remaining),
                .orange
            )
        case .finished:
            return (
                "checkmark.circle.fill",
                "Done",
                "Run through the offline DSP; trace is below.",
                .green
            )
        case .failed(let reason):
            return (
                "exclamationmark.triangle.fill",
                "Failed",
                reason,
                .yellow
            )
        }
    }

    private func labelForAxis(_ value: Double) -> String {
        switch value {
        case ..<(-0.75): return "Far L"
        case ..<(-0.25): return "L"
        case ..<(0.25):  return "0"
        case ..<(0.75):  return "R"
        default:         return "Far R"
        }
    }
}

#Preview {
    CalibrationView()
}
