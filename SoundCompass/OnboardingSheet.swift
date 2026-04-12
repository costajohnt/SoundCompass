import SwiftUI

/// First-launch walkthrough. Gated by `@AppStorage("hasSeenOnboarding")`
/// in `ContentView`, shown once then never again.
struct OnboardingSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.cyan)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Welcome to SoundCompass")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("A few things to know before you start.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 20) {
                    OnboardingRow(
                        icon: "hand.raised.fill",
                        title: "Hold the phone flat",
                        text: "Rest it on your palm, screen facing up, top edge pointing the way you're facing. The compass is calibrated for that orientation."
                    )
                    OnboardingRow(
                        icon: "mic.fill",
                        title: "Microphone access",
                        text: "SoundCompass uses the phone's built-in stereo microphone array. No audio ever leaves your device."
                    )
                    OnboardingRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Front and back can look the same",
                        text: "A two-microphone array cannot tell whether a sound is in front of you or behind you. If the arrow feels wrong, turn your body 90° — the direction will swing as you rotate, which confirms where the sound really is."
                    )
                    OnboardingRow(
                        icon: "earbuds",
                        title: "Use the built-in mic, not a headset",
                        text: "Bluetooth and wired headsets deliver a single mono channel, so direction cannot be estimated. SoundCompass will warn you if it detects a mono input."
                    )
                }
                .padding(.horizontal, 8)

                Button {
                    isPresented = false
                } label: {
                    Text("Got it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.cyan)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }
}

private struct OnboardingRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.cyan)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingSheet(isPresented: .constant(true))
}
