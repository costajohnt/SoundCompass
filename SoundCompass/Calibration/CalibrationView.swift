import Charts
import SwiftUI

/// Calibration screen surfaced from the Settings sheet. Records five
/// seconds of stereo audio, runs it through the offline DSP pipeline with
/// the *current* settings (gain, ILD band, sensitivity), and renders the
/// resulting direction trace as a line chart.
///
/// It is also the place where the per-device ILD gain gets set: record a
/// sound held hard to one side, tap **Use as calibration**, and the 90th
/// percentile of the measured level difference becomes this phone's
/// full-scale deflection.
struct CalibrationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var recorder = CalibrationRecorder()
    @State private var samples: [CalibrationSample] = []
    @State private var suggestedGain: Double?
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
                        calibrationCard
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
            reprocess(clip: newClip)
        }
        .onChange(of: settings.ildHighBand) { _, _ in
            reprocess(clip: recorder.clip)
        }
        .onChange(of: settings.ildGain) { _, _ in
            reprocess(clip: recorder.clip)
        }
    }

    private func reprocess(clip: CalibrationClip?) {
        guard let clip else {
            samples = []
            suggestedGain = nil
            return
        }
        samples = CalibrationProcessor.process(
            clip: clip,
            ildGain: settings.ildGain ?? DirectionEstimator.defaultIldGain,
            ildBandHz: settings.ildHighBand ? SettingsStore.highBandILDRange : nil,
            directionBlend: settings.sensitivity.directionBlend,
            magnitudeBlend: settings.sensitivity.magnitudeBlend
        )
        suggestedGain = CalibrationProcessor.suggestedIldGain(from: samples)
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
        let copy = stateCopy()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: copy.icon)
                .font(.title3)
                .foregroundStyle(copy.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.title).font(.headline)
                copy.detail
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(copy.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(copy.tint.opacity(0.25), lineWidth: 1)
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
                            Text(verbatim: labelForAxis(d))
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
        let confident = samples.filter(\.isConfident).map { abs($0.rawILD) }
        let peakILD = confident.max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Text("Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                summaryCell(label: "Peak loudness", value: String(format: "%.0f%%", maxMagnitude * 100))
                summaryCell(label: "Average direction", value: DirectionLabel.label(for: avgDirection))
                summaryCell(label: "Peak |ILD|", value: String(format: "%.3f", peakILD))
            }
        }
    }

    /// Turns the recording into a stored per-device gain.
    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use as calibration")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let suggestedGain {
                Text("If this recording was a sound held hard to one side at about a metre, storing it sets this phone's full-scale level difference. Suggested ILD gain: \(suggestedGain, specifier: "%.1f") (current \(settings.ildGain ?? DirectionEstimator.defaultIldGain, specifier: "%.1f")).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    settings.ildGain = suggestedGain
                } label: {
                    Label("Store as this device's ILD gain", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            } else {
                Text("Not enough confident windows in this recording to derive a gain. Record again with a louder, sustained sound held to one side.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryCell(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
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

    private struct StateCopy {
        let icon: String
        let title: LocalizedStringKey
        let detail: Text
        let tint: Color
    }

    private func stateCopy() -> StateCopy {
        switch recorder.state {
        case .idle:
            return StateCopy(
                icon: "record.circle",
                title: "Ready",
                detail: Text("Tap Record to capture five seconds of stereo audio."),
                tint: .cyan
            )
        case .recording(let remaining):
            return StateCopy(
                icon: "waveform",
                title: "Recording…",
                detail: Text("\(remaining, specifier: "%.1f")s remaining"),
                tint: .orange
            )
        case .finished:
            return StateCopy(
                icon: "checkmark.circle.fill",
                title: "Done",
                detail: Text("Run through the offline DSP; trace is below."),
                tint: .green
            )
        case .failed(let reason):
            return StateCopy(
                icon: "exclamationmark.triangle.fill",
                title: "Failed",
                detail: Text(verbatim: reason),
                tint: .yellow
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
        .environmentObject(SettingsStore())
}
