import AVFoundation
import Foundation

/// Contralateral-routing-of-signal (CROS) style audio passthrough.
///
/// For a single-sided deaf user, the useful configuration is:
///
/// 1. Stereo microphones on the phone capture the room.
/// 2. We route that stereo signal into `AVAudioEngine.mainMixerNode`.
/// 3. We pan the mixer hard toward whichever ear the user hears with
///    (as configured in `SettingsStore.hearingEar`).
/// 4. We play it out of headphones so the user hears the entire room
///    through their working ear, including sounds that originated on
///    their deaf side.
///
/// Safety rails:
///
/// * Passthrough only engages when the current audio route terminates
///   in **headphones / Bluetooth / AirPlay** — never on the internal
///   speaker, to avoid creating a mic-to-speaker feedback loop.
/// * The class exposes `handleRouteChange()` so `AudioDirectionDetector`
///   can notify it when `AVAudioSession.routeChangeNotification` fires.
/// * The class watches for the user toggling the feature off even while
///   listening is active — in that case it disconnects cleanly.
///
/// This does **not** replace the tap used by the DSP pipeline.
/// `installTap` and graph connections coexist on the same `inputNode`,
/// so the tap still gets a copy of every buffer for
/// `DirectionEstimator` etc.
final class PassthroughMixer {

    private let engine: AVAudioEngine
    private let session = AVAudioSession.sharedInstance()
    private var isConnected = false

    /// Desired state the caller asked for. Actual connection state may
    /// lag when headphones come and go.
    private var desiredEnabled = false
    private var desiredPan: Float = 0

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Request that passthrough be enabled or disabled. If headphones
    /// are not currently connected, the request is remembered and
    /// applied later when a headphone route becomes available.
    func setEnabled(_ enabled: Bool, pan: Float) {
        desiredEnabled = enabled
        desiredPan = pan
        reconcile()
    }

    /// Update just the pan value without re-checking enabled state.
    func updatePan(_ pan: Float) {
        desiredPan = pan
        guard isConnected else { return }
        engine.mainMixerNode.pan = pan
    }

    /// Called by `AudioDirectionDetector` when the audio route changes.
    /// Re-evaluates whether we should be connected.
    func handleRouteChange() {
        reconcile()
    }

    /// Disconnect without forgetting the desired state. Useful when the
    /// detector is stopping the engine — the engine gets torn down so
    /// there's nothing to be connected to.
    func pause() {
        disconnect()
    }

    /// Whether the passthrough is actively feeding audio to the
    /// headphones right now. Useful for test introspection and for the
    /// UI to surface a small indicator.
    var isActive: Bool { isConnected }

    // MARK: - Private

    private func reconcile() {
        if desiredEnabled && hasSafeOutputRoute() {
            connect()
        } else {
            disconnect()
        }
    }

    /// I/O buffer duration requested while passthrough is live. The
    /// default (~23 ms) plus a Bluetooth A2DP link (100–200 ms) is an
    /// audible echo; 10 ms is the practical floor that still leaves the
    /// tap enough headroom. Wired / USB-C headphones get the full benefit.
    static let passthroughIOBufferDuration: TimeInterval = 0.010

    private func connect() {
        guard !isConnected else {
            engine.mainMixerNode.pan = desiredPan
            return
        }
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.passthrough.warning("Refusing to connect passthrough: invalid input format")
            return
        }
        try? session.setPreferredIOBufferDuration(PassthroughMixer.passthroughIOBufferDuration)
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.pan = desiredPan
        engine.mainMixerNode.outputVolume = 1.0
        isConnected = true
        Log.passthrough.info("Passthrough connected, pan \(self.desiredPan)")
    }

    private func disconnect() {
        guard isConnected else { return }
        // `installTap` is not a graph edge, so removing the connection
        // between inputNode and mainMixerNode does not remove the tap.
        engine.disconnectNodeOutput(engine.inputNode)
        isConnected = false
        Log.passthrough.info("Passthrough disconnected")
    }

    private func hasSafeOutputRoute() -> Bool {
        let route = session.currentRoute
        return route.outputs.contains { output in
            switch output.portType {
            case .headphones,
                 .bluetoothA2DP,
                 .bluetoothLE,
                 .bluetoothHFP,
                 .airPlay,
                 .usbAudio,
                 .lineOut:
                return true
            default:
                return false
            }
        }
    }
}
