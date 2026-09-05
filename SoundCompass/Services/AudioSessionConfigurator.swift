import AVFoundation
import Foundation

/// The one place that knows how to put `AVAudioSession` into stereo
/// capture mode. Shared by `AudioDirectionDetector` and
/// `CalibrationRecorder` so a calibration recording is guaranteed to come
/// from the same data source, with the same mirroring, as the live compass.
enum AudioSessionConfigurator {

    /// Which built-in stereo data source ended up active and how its
    /// left/right relate to the user's.
    struct StereoSelection: Equatable {
        /// `-1` when the active source delivers a mirrored image (front
        /// source), `+1` otherwise.
        let directionSign: Double
        /// Human-readable description for the debug overlay and trace
        /// ("Back", "Front (mirrored)", "no stereo source").
        let description: String
    }

    /// A platform-independent view of one `AVAudioSessionDataSourceDescription`
    /// so the selection rule is unit-testable without a device.
    struct SourceCandidate: Equatable {
        let name: String
        let orientation: AVAudioSession.Orientation?
        let supportsStereo: Bool
    }

    /// Selection rule: iPhone "stereo" is a synthesized image and the
    /// FRONT and BACK data sources produce MIRRORED left/right relative to
    /// each other (WWDC20 session 10226). With the documented hold — phone
    /// flat, screen up, top edge pointing away — the BACK source's
    /// left/right match the user's, so prefer it explicitly instead of
    /// taking whichever source happens to enumerate first. If only the
    /// front source supports stereo, use it and flip the sign of every
    /// direction estimate.
    static func chooseStereoSource(from candidates: [SourceCandidate]) -> (index: Int, selection: StereoSelection)? {
        let stereo = candidates.enumerated().filter { $0.element.supportsStereo }
        guard let chosen = stereo.first(where: { $0.element.orientation == .back }) ?? stereo.first else {
            return nil
        }
        let mirrored = chosen.element.orientation == .front
        return (
            chosen.offset,
            StereoSelection(
                directionSign: mirrored ? -1.0 : 1.0,
                description: "\(chosen.element.name)\(mirrored ? " (mirrored)" : "")"
            )
        )
    }

    /// Configure and activate the shared session for stereo capture.
    ///
    /// Category is `.playAndRecord` so the CROS passthrough can play.
    /// `.allowBluetoothA2DP` is required for `playAndRecord` to route
    /// *output* to Bluetooth headphones at all; without it iOS keeps the
    /// speaker and passthrough can never engage on AirPods. A2DP is
    /// output-only, so the built-in stereo mic stays the input.
    /// `.allowBluetoothHFP` is deliberately absent: HFP would switch the
    /// input to the headset's mono mic and make direction finding
    /// impossible.
    @discardableResult
    static func configureForStereoCapture(_ session: AVAudioSession) throws -> StereoSelection {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )

        var selection = StereoSelection(directionSign: 1.0, description: "no stereo source")

        // Prefer the built-in mic so we get the multi-element array.
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtIn)

            let sources = builtIn.dataSources ?? []
            Log.audio.info("Built-in mic: \(builtIn.portName, privacy: .public), \(sources.count) data sources")
            for source in sources {
                let patterns = source.supportedPolarPatterns?.map(\.rawValue) ?? []
                Log.audio.info("  Source: \(source.dataSourceName, privacy: .public) orientation: \(source.orientation?.rawValue ?? "nil", privacy: .public) patterns: \(patterns, privacy: .public)")
            }

            let candidates = sources.map {
                SourceCandidate(
                    name: $0.dataSourceName,
                    orientation: $0.orientation,
                    supportsStereo: $0.supportedPolarPatterns?.contains(.stereo) == true
                )
            }
            if let choice = chooseStereoSource(from: candidates) {
                let source = sources[choice.index]
                try source.setPreferredPolarPattern(.stereo)
                try builtIn.setPreferredDataSource(source)
                selection = choice.selection
                Log.audio.info("  → Selected \(selection.description, privacy: .public) for stereo, directionSign \(selection.directionSign)")
            } else {
                Log.audio.warning("No data source with stereo polar pattern found")
            }
        } else {
            Log.audio.warning("No built-in mic found in available inputs")
        }

        // Ask for both channels explicitly — the polar pattern alone is a
        // preference, not a guarantee. Best-effort: throws if the route
        // can't do 2 channels, which the mono path already handles.
        try? session.setPreferredInputNumberOfChannels(2)

        try session.setPreferredInputOrientation(.portrait)
        try session.setActive(true, options: [])

        Log.audio.info("Session active — input channels: \(session.inputNumberOfChannels), sample rate: \(session.sampleRate)")
        return selection
    }

    /// Input-port signature of a route, used to decide whether a route
    /// change actually touched capture (and therefore needs a tap
    /// reinstall) or only moved the output (which only the passthrough
    /// mixer cares about).
    static func inputSignature(of route: AVAudioSessionRouteDescription) -> [String] {
        route.inputs.map { "\($0.uid)|\($0.channels?.count ?? 0)" }
    }
}
