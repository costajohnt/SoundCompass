import AVFoundation
import SwiftUI

/// The user-facing settings sheet. Opened from the gear button in the
/// header.
struct SettingsSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Binding var isPresented: Bool
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = true
    @State private var showHelp: Bool = false
    @State private var showCalibration: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sensitivity", selection: $settings.sensitivity) {
                        ForEach(SettingsStore.Sensitivity.allCases) { option in
                            Text(verbatim: option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(verbatim: settings.sensitivity.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Responsiveness")
                } footer: {
                    Text("Controls how quickly the arrow follows new sounds vs. how much it smooths out jitter.")
                }

                Section {
                    Picker("Hearing ear", selection: $settings.hearingEar) {
                        ForEach(SettingsStore.HearingEar.allCases) { option in
                            Text(verbatim: option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Which ear hears?")
                } footer: {
                    Text("When audio passthrough is on, SoundCompass sends the room audio to this ear. Leave it unspecified to hear it in both.")
                }

                Section {
                    Toggle("Stream through good ear (CROS)", isOn: $settings.passthroughEnabled)
                } header: {
                    Text("Audio passthrough")
                } footer: {
                    Text("With headphones connected, SoundCompass routes the phone's stereo microphone audio into the ear you hear with, so you get some sense of sounds from your deaf side. Works with wired, USB-C, AirPlay and Bluetooth headphones — never through the phone's speaker. Bluetooth adds a noticeable delay; wired headphones are best.")
                }

                Section {
                    Toggle("Alert on hazard sounds", isOn: $settings.hazardAlerts)
                } header: {
                    Text("Safety")
                } footer: {
                    Text("When a siren, alarm, horn, or reversing beep is detected, the arrow jumps straight to the latest direction (no smoothing), a red banner appears, the phone plays a strong haptic pattern, and a paired Apple Watch taps once firmly. Recommended on.")
                }

                Section("Haptics") {
                    Picker("Haptic strength", selection: $settings.hapticStrength) {
                        ForEach(SettingsStore.HapticStrength.allCases) { option in
                            Text(verbatim: option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Speech") {
                    Toggle("Speak direction", isOn: $settings.speechEnabled)
                    if settings.speechEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Speech rate")
                                Spacer()
                                Text(verbatim: speechRateLabel)
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospacedDigit())
                            }
                            Slider(value: $settings.speechRate, in: 0.5...1.8, step: 0.1)
                        }

                        Picker("Voice", selection: voiceBinding) {
                            Text("System default").tag(String?.none)
                            ForEach(availableVoices, id: \.identifier) { voice in
                                Text(verbatim: voice.name).tag(String?.some(voice.identifier))
                            }
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(SettingsStore.Theme.allCases) { option in
                            Text(verbatim: option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Show DSP stats", isOn: $settings.showDebugStats)
                    Toggle("Measure ILD in 1–8 kHz band", isOn: $settings.ildHighBand)
                    Button("Calibration trace…") { showCalibration = true }
                    if settings.ildGain != nil {
                        Button("Reset ILD calibration") { settings.ildGain = nil }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text(ildFooter)
                }

                Section {
                    Button("Help & FAQ") { showHelp = true }
                    Button("Show walkthrough again") {
                        hasSeenOnboarding = false
                        isPresented = false
                    }
                    Link(
                        "Apple's SSD hearing resources",
                        destination: URL(string: "https://support.apple.com/guide/iphone/hearing-devices-iph75bda3f2e/ios")!
                    )
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpSheet(isPresented: $showHelp)
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationView()
                    .environmentObject(settings)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var speechRateLabel: String {
        String(format: "%.1f×", settings.speechRate)
    }

    private var ildFooter: LocalizedStringKey {
        let gain = settings.ildGain ?? DirectionEstimator.defaultIldGain
        let source = settings.ildGain == nil ? String(localized: "default") : String(localized: "calibrated")
        return "ILD gain \(gain, specifier: "%.1f") (\(source)). The band toggle restricts the level comparison to frequencies where the phone's beams actually diverge; it is experimental until measured on more devices. The DSP stats toggle also writes a per-frame CSV trace to the app's Documents folder."
    }

    /// Voices filtered to the user's preferred language so the picker
    /// isn't 150+ entries long.
    private var availableVoices: [AVSpeechSynthesisVoice] {
        let preferred = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice
            .speechVoices()
            .filter { $0.language.hasPrefix(preferred) }
            .sorted { $0.name < $1.name }
    }

    /// Binding that maps the optional String? identifier through the
    /// Picker (which requires a Hashable tag).
    private var voiceBinding: Binding<String?> {
        Binding(
            get: { settings.speechVoiceIdentifier },
            set: { settings.speechVoiceIdentifier = $0 }
        )
    }
}

#Preview {
    SettingsSheet(isPresented: .constant(true))
        .environmentObject(SettingsStore())
}
