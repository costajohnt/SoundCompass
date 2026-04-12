import CoreHaptics
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var detector: AudioDirectionDetector
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var hapticEngine: CHHapticEngine?
    @State private var lastHapticTime: Date = .distantPast
    @State private var showOnboarding: Bool = false
    @State private var showSettings: Bool = false
    @State private var showHistory: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.08, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Group {
                if hSizeClass == .regular {
                    regularLayout
                } else {
                    compactLayout
                }
            }
        }
        .onAppear {
            prepareHaptics()
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: detector.direction) { _, newValue in
            triggerHaptic(for: newValue, magnitude: detector.magnitude)
        }
        .onChange(of: detector.isHazardActive) { wasActive, isActive in
            // Edge-trigger the rich hazard haptic *and* a VoiceOver
            // announcement on the rising edge. The announcement has
            // high priority so it interrupts anything VoiceOver is
            // currently reading.
            if !wasActive && isActive {
                triggerHazardHaptic()
                announceHazardToVoiceOver()
            }
        }
        .onChange(of: hasSeenOnboarding) { _, newValue in
            // Re-opened from the "Show walkthrough again" button in settings.
            if !newValue { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet(isPresented: $showOnboarding)
                .onDisappear { hasSeenOnboarding = true }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showHistory) {
            EventHistoryView(
                store: detector.eventHistory,
                stats: detector.sessionStats,
                isPresented: $showHistory
            )
        }
    }

    // MARK: - Layouts

    /// Phone (compact horizontal size class) — everything stacks
    /// vertically in a single ScrollView.
    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                CompassView(
                    direction: detector.direction,
                    magnitude: detector.magnitude
                )
                .padding(.horizontal, 16)
                directionReadout
                if detector.isHazardActive { hazardBanner }
                if detector.isRunning { frontBackBanner }
                if let label = detector.classifierLabel {
                    classifierChip(label: label, confidence: detector.classifierConfidence)
                }
                if !detector.bandResults.isEmpty { bandGrid }
                if settings.showDebugStats {
                    DebugStatsView(detector: detector)
                        .padding(.horizontal, 24)
                }
                if detector.isMono { monoWarning }
                if let error = detector.lastError {
                    errorBanner(text: error)
                }
                Spacer(minLength: 0)
                controlButton
            }
            .padding(.vertical, 32)
        }
    }

    /// iPad / regular horizontal size class — compass on the left, all
    /// of the cards on the right in a scrollable column. Centered in a
    /// 900 pt wide container so it doesn't sprawl on a 13" iPad.
    ///
    /// The HStack needs an explicit `maxHeight: .infinity` so the
    /// ScrollView column gets an actual bounded size to scroll inside;
    /// without it the HStack collapses to its intrinsic height and the
    /// ScrollView renders 0 pt tall.
    private var regularLayout: some View {
        VStack(spacing: 16) {
            header
                .padding(.top, 24)

            HStack(alignment: .top, spacing: 32) {
                VStack(spacing: 20) {
                    CompassView(
                        direction: detector.direction,
                        magnitude: detector.magnitude
                    )
                    .frame(maxWidth: 420)
                    directionReadout
                    if detector.isHazardActive { hazardBanner }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    VStack(spacing: 20) {
                        if detector.isRunning { frontBackBanner }
                        if let label = detector.classifierLabel {
                            classifierChip(label: label, confidence: detector.classifierConfidence)
                        }
                        if !detector.bandResults.isEmpty { bandGrid }
                        if settings.showDebugStats {
                            DebugStatsView(detector: detector)
                                .padding(.horizontal, 8)
                        }
                        if detector.isMono { monoWarning }
                        if let error = detector.lastError {
                            errorBanner(text: error)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 900, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlButton
                .frame(maxWidth: 420)
                .padding(.bottom, 24)
        }
    }

    private var monoWarning: some View {
        warningBanner(
            icon: "exclamationmark.triangle.fill",
            text: "This microphone only provides mono audio. Direction cannot be estimated — try the built-in mic instead of a headset."
        )
    }

    private func errorBanner(text: String) -> some View {
        Group {
            if text.contains("denied") {
                permissionDeniedBanner(text: text)
            } else {
                warningBanner(icon: "mic.slash.fill", text: text)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Recent sounds")

            VStack(spacing: 6) {
                Text("SoundCompass")
                    .font(.title.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                Text("Hold your phone flat, screen up, pointing forward.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
    }

    /// A loud red banner that appears when `HazardClassifier.isHazard`
    /// matches the current classifier label. Designed to be
    /// unambiguous at a glance and to over-ride all visual weight
    /// against the rest of the screen.
    private var hazardBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(detector.hazardLabel ?? "Hazard sound")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Detected \(DirectionLabel.label(for: detector.direction).lowercased()).")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
        )
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var directionReadout: some View {
        let label = DirectionLabel.label(for: detector.direction)
        let degrees = Int((detector.direction * 90).rounded())
        let loudnessPct = Int(detector.magnitude * 100)
        return VStack(spacing: 4) {
            Text(label)
                .font(.title3.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
            Text("\(degrees > 0 ? "+" : "")\(degrees)°  ·  \(loudnessPct)% loudness")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current direction")
        .accessibilityValue("\(label), \(degrees) degrees, \(loudnessPct) percent loudness")
    }

    private func classifierChip(label: String, confidence: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundStyle(.cyan)
            Text(label)
                .font(.callout.weight(.semibold))
                .fontDesign(.rounded)
            Text("\(Int(confidence * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detected sound")
        .accessibilityValue("\(label), \(Int(confidence * 100)) percent confidence")
    }

    /// Live reflection of `FrontBackResolver.resolution`. While the user
    /// hasn't rotated the phone enough we show a gentle "turn your body"
    /// prompt; once the resolver has enough data we promote the banner to
    /// a green "in front" / "behind you" result.
    private var frontBackBanner: some View {
        let (icon, tint, title, detail) = frontBackCopy()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: detector.frontBackResolution)
        .accessibilityElement(children: .combine)
    }

    private func frontBackCopy() -> (icon: String, tint: Color, title: String, detail: String) {
        if !detector.frontBackResolver.isMotionAvailable {
            return (
                "gyroscope",
                .yellow,
                "Motion sensor unavailable",
                "Front/back disambiguation needs device motion data, which isn't available on this device. Arrow direction is otherwise accurate."
            )
        }
        switch detector.frontBackResolution {
        case .unknown:
            return (
                "arrow.triangle.2.circlepath",
                .cyan,
                "Front or back?",
                "Turn your body slowly — I'll tell you if the sound is actually in front of you or behind."
            )
        case .needsRotation(let degrees):
            return (
                "arrow.triangle.2.circlepath",
                .cyan,
                "Keep rotating… \(Int(degrees))°",
                "Sweep another \(max(0, 15 - Int(degrees)))° so I can tell front from back."
            )
        case .front:
            return (
                "arrow.up.circle.fill",
                .green,
                "Sound is in front of you",
                "Rotation-confirmed."
            )
        case .back:
            return (
                "arrow.down.circle.fill",
                .orange,
                "Sound is behind you",
                "Rotation-confirmed. The on-screen compass mirrors the true direction."
            )
        }
    }

    private var bandGrid: some View {
        let dominantName = detector.dominantBandName
        return VStack(alignment: .leading, spacing: 8) {
            Text("Frequency bands")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                ForEach(detector.bandResults, id: \.band.name) { result in
                    BandRow(
                        result: result,
                        isDominant: result.band.name == dominantName
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func warningBanner(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.yellow)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    /// Specialized permission-denied banner with a button that deep-links
    /// into the iOS Settings app so users can grant microphone access
    /// without hunting for SoundCompass in the long list of apps.
    private func permissionDeniedBanner(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.yellow)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: "arrow.up.forward.app")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var controlButton: some View {
        Button {
            if detector.isRunning {
                detector.stop()
            } else {
                detector.start()
            }
        } label: {
            Label(
                detector.isRunning ? "Stop listening" : "Start listening",
                systemImage: detector.isRunning ? "stop.circle.fill" : "mic.circle.fill"
            )
            .font(.title3.weight(.semibold))
            .fontDesign(.rounded)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                detector.isRunning ? Color.red.opacity(0.85) : Color.blue.opacity(0.9),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .accessibilityHint(detector.isRunning
            ? "Stops the microphone and the sound direction estimator."
            : "Starts listening to nearby sounds and estimates where they come from."
        )
    }

    // MARK: - Haptics

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            hapticEngine = nil
        }
    }

    /// Posts a `UIAccessibility.Notification.announcement` so VoiceOver
    /// users hear "<Sound> detected <direction>" the moment a hazard is
    /// flagged. This is on top of the visual red banner and the rich
    /// haptic — all three channels fire in parallel for safety-critical
    /// sounds.
    private func announceHazardToVoiceOver() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let label = detector.hazardLabel ?? "Hazard sound"
        let direction = DirectionLabel.spokenPhrase(direction: detector.direction)
        let phrase = "\(label) detected \(direction)"
        UIAccessibility.post(notification: .announcement, argument: phrase)
    }

    /// Attention-grabbing haptic pattern for hazard events. A short
    /// continuous buzz followed by three sharp transient taps, all at
    /// maximum intensity — deliberately more intense than the regular
    /// per-frame direction haptic so the user can tell them apart.
    private func triggerHazardHaptic() {
        guard settings.hapticStrength != .off else { return }
        guard let engine = hapticEngine else { return }

        let buzz = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
            ],
            relativeTime: 0,
            duration: 0.25
        )
        let tapTimes: [Double] = [0.30, 0.45, 0.60]
        let taps = tapTimes.map { t in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: t
            )
        }
        do {
            let pattern = try CHHapticPattern(events: [buzz] + taps, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Haptics are advisory; ignore failures.
        }
    }

    private func triggerHaptic(for direction: Double, magnitude: Double) {
        guard settings.hapticStrength != .off else { return }
        guard magnitude > 0.35 else { return }
        guard Date().timeIntervalSince(lastHapticTime) > 0.25 else { return }
        guard let engine = hapticEngine else { return }

        let floor = settings.hapticStrength.intensity
        let intensity = Float(min(1.0, magnitude)) * floor
        let sharpness = Float(min(1.0, abs(direction)))
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            lastHapticTime = Date()
        } catch {
            // Haptics are advisory; ignore failures.
        }
    }
}

/// A single row of the frequency-band grid.
private struct BandRow: View {
    let result: SubbandDirectionEstimator.BandResult
    let isDominant: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(result.band.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(isDominant ? .white : .white.opacity(0.7))
                .frame(width: 52, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(isDominant ? Color.cyan : Color.white.opacity(0.4))
                        .frame(width: proxy.size.width * CGFloat(result.magnitude))
                }
            }
            .frame(height: 6)

            Text(arrow(for: result.direction))
                .font(.caption.weight(.bold))
                .foregroundStyle(isDominant ? .cyan : .white.opacity(0.6))
                .frame(width: 24, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func arrow(for direction: Double) -> String {
        switch direction {
        case ..<(-0.66): return "←←"
        case ..<(-0.20): return "←"
        case ..<(0.20):  return "·"
        case ..<(0.66):  return "→"
        default:         return "→→"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioDirectionDetector())
}
