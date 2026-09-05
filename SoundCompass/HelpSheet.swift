import SwiftUI

/// In-app help / FAQ surfaced from the Settings sheet. Keeps the
/// onboarding short and lets users re-read the tricky bits (front/back
/// ambiguity, stereo-mic requirement) on demand without resetting the
/// onboarding flag.
struct HelpSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HelpSection(
                        title: "How does SoundCompass know where a sound is?",
                        content: """
                        Modern iPhones have several microphones, and iOS combines them into a \
                        stereo picture of the room. When a sound comes from your left, the left \
                        channel of that picture is a little louder than the right. SoundCompass \
                        measures that level difference many times a second and turns it into \
                        the arrow. Expect it to tell left from centre from right reliably; the \
                        exact angle is an estimate.
                        """
                    )

                    HelpSection(
                        title: "Why does the arrow sometimes flip?",
                        content: """
                        A two-microphone array cannot tell front from back on its own — a sound \
                        in front and a mirror-image sound behind produce the same left/right cue. \
                        If you rotate your body a few degrees, SoundCompass watches the direction \
                        change with your yaw and commits to "in front of you" or "behind you".
                        """
                    )

                    HelpSection(
                        title: "It thinks everything is mono. What's wrong?",
                        content: """
                        You're probably connected to a Bluetooth or wired headset, which only \
                        delivers a single channel to the app. Disconnect it and use the built-in \
                        mic instead. You'll see a yellow banner when SoundCompass detects a mono \
                        input.
                        """
                    )

                    HelpSection(
                        title: "Does any of my audio leave the phone?",
                        content: """
                        No. SoundCompass does all of its processing on-device. Nothing is sent \
                        to any server. The sound classifier is Apple's built-in model that also \
                        runs locally.
                        """
                    )

                    HelpSection(
                        title: "How should I hold the phone?",
                        content: """
                        Flat on your palm, screen facing up, the top edge of the phone pointing \
                        the way you're facing. The compass dial on screen is calibrated for that \
                        orientation — hold it like a real compass.
                        """
                    )

                    HelpSection(
                        title: "The arrow is jittery.",
                        content: """
                        Open Settings and set Sensitivity to "Calm". That increases the smoothing \
                        so the arrow moves more slowly. "Snappy" does the opposite — faster, less \
                        stable — and "Balanced" is the default.
                        """
                    )

                    HelpSection(
                        title: "Can I use the watch without the phone?",
                        content: """
                        Not yet. The Apple Watch companion is a mirror: the phone does the audio \
                        processing and sends direction updates to the watch over WatchConnectivity. \
                        Standalone watch processing is on the roadmap.
                        """
                    )
                }
                .padding(24)
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct HelpSection: View {
    let title: LocalizedStringKey
    let content: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HelpSheet(isPresented: .constant(true))
}
