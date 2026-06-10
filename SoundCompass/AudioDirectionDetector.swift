import AVFoundation
import Accelerate
import Combine
import Foundation

/// The top-level audio capture + processing object the SwiftUI views talk to.
///
/// `AudioDirectionDetector` owns the `AVAudioEngine` tap and a suite of
/// processors:
///
/// * `DirectionEstimator` — broadband ITD + ILD → `direction`, `magnitude`.
/// * `SubbandDirectionEstimator` — per-band direction + magnitude so we can
///   tell rumble from speech from alarms.
/// * `SoundClassifier` — Apple's built-in `SNClassifySoundRequest` to tag
///   the loudest sound ("speech", "car horn", "dog bark", …).
/// * `SpeechAnnouncer` — optional spoken callouts through the hearing ear.
/// * `WatchSessionManager` — mirrors everything to the watchOS companion.
///
/// The DSP runs on the real-time tap thread; @Published updates are
/// dispatched onto the main queue.
final class AudioDirectionDetector: ObservableObject {

    // MARK: - Published state

    @Published private(set) var direction: Double = 0
    @Published private(set) var magnitude: Double = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isMono: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var bandResults: [SubbandDirectionEstimator.BandResult] = []
    @Published private(set) var dominantBandName: String?

    /// Raw DSP debug values — visible when DSP stats toggle is on.
    @Published private(set) var debugDSP: String = ""

    /// Top-scoring classifier label re-published from `SoundClassifier` so
    /// SwiftUI views that only observe this object still redraw when it
    /// changes. (SwiftUI does not propagate nested ObservableObjects.)
    @Published private(set) var classifierLabel: String?
    @Published private(set) var classifierConfidence: Double = 0
    @Published private(set) var classifierRawIdentifier: String?

    /// True when the current classifier label is a safety-critical sound
    /// (siren, alarm, horn, reversing beep…). When set, the UI should
    /// surface a prominent banner and the DSP skips its usual smoother.
    @Published private(set) var isHazardActive: Bool = false
    @Published private(set) var hazardLabel: String?

    /// Front/back resolution re-published from `FrontBackResolver`.
    @Published private(set) var frontBackResolution: FrontBackResolver.Resolution = .unknown
    @Published private(set) var yawRangeDegrees: Double = 0

    // MARK: - Services (exposed so the UI can bind to them)

    let classifier = SoundClassifier()
    let announcer = SpeechAnnouncer()
    let watchSession = WatchSessionManager()
    let frontBackResolver = FrontBackResolver()
    let settings: SettingsStore
    let liveActivity = LiveActivityController()
    let eventHistory = EventHistoryStore()
    let hazardNotifier = HazardNotifier()
    let sessionStats = SessionStats()
    lazy var passthroughMixer = PassthroughMixer(engine: engine)

    /// `true` when the SwiftUI scene is in the background. Used to gate
    /// hazard notifications so we don't spam the user while they're
    /// already staring at the big red banner in the foreground.
    private var sceneInBackground = false

    // MARK: - Audio pipeline

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()

    // DSP state. Accessed only from the tap thread after `start()` returns.
    private var estimator: DirectionEstimator?
    private var subband: SubbandDirectionEstimator?
    private let bufferFrames: AVAudioFrameCount = 2048

    /// `-1` when the active stereo data source delivers a mirrored image
    /// (front source), `+1` otherwise. Written in `configureSession()`
    /// before the tap is installed; read on the tap thread.
    private var directionSign: Double = 1.0

    /// Human-readable description of the stereo source in use, for the
    /// debug overlay ("Back", "Front (mirrored)", "no stereo source").
    private var activeSourceDescription: String = "?"

    // Lifecycle bookkeeping.
    private var isStarting = false
    private var wasRunningBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var settingsCancellables = Set<AnyCancellable>()

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        watchSession.activate()

        // Speech announcer follows the settings toggle directly.
        settings.$speechEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.announcer.isEnabled = enabled
            }
            .store(in: &settingsCancellables)

        settings.$speechRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.announcer.rateMultiplier = rate
            }
            .store(in: &settingsCancellables)

        settings.$speechVoiceIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] identifier in
                self?.announcer.voiceIdentifier = identifier
            }
            .store(in: &settingsCancellables)

        // Passthrough toggle + hearing-ear changes both flow into the
        // passthrough mixer's pan + enabled state.
        Publishers.CombineLatest(settings.$passthroughEnabled, settings.$hearingEar)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, ear in
                guard let self else { return }
                let pan: Float
                switch ear {
                case .left:  pan = -1.0
                case .right: pan =  1.0
                case .unspecified: pan = 0
                }
                if self.isRunning {
                    self.passthroughMixer.setEnabled(enabled, pan: pan)
                }
            }
            .store(in: &settingsCancellables)

        // Re-publish classifier updates so ContentView observes them through
        // its single `@EnvironmentObject AudioDirectionDetector`.
        classifier.$topLabel
            .receive(on: DispatchQueue.main)
            .assign(to: &$classifierLabel)
        classifier.$topConfidence
            .receive(on: DispatchQueue.main)
            .assign(to: &$classifierConfidence)
        classifier.$topRawIdentifier
            .receive(on: DispatchQueue.main)
            .assign(to: &$classifierRawIdentifier)

        // Same re-publish dance for the motion-based front/back resolver.
        frontBackResolver.$resolution
            .receive(on: DispatchQueue.main)
            .assign(to: &$frontBackResolution)
        frontBackResolver.$yawRangeDegrees
            .receive(on: DispatchQueue.main)
            .assign(to: &$yawRangeDegrees)

        // System audio interruptions (phone calls, Siri, alarms) suspend
        // our tap; we need to update UI state and optionally resume.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }

        // Route changes (headset plugged in/out, CarPlay, AirPlay) can
        // swap our capture format from stereo to mono out from under us.
        // React by tearing down and re-installing the tap so the DSP
        // buffers pick up the new format.
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    /// Requests microphone permission and starts capture. Safe to call
    /// repeatedly; re-entrant calls (e.g. a double-tap on the button) are
    /// coalesced via `isStarting`.
    func start() {
        guard !isRunning, !isStarting else { return }
        isStarting = true

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.isStarting = false }

                guard granted else {
                    self.lastError = "Microphone access was denied. Enable it in Settings to use SoundCompass."
                    return
                }
                do {
                    try self.configureSession()
                    try self.installTap()
                    try self.engine.start()
                    self.isRunning = true
                    self.lastError = nil
                    self.sessionStats.begin()
                    self.frontBackResolver.start()
                    let pan: Float
                    switch self.settings.hearingEar {
                    case .left:  pan = -1.0
                    case .right: pan =  1.0
                    case .unspecified: pan = 0
                    }
                    self.passthroughMixer.setEnabled(self.settings.passthroughEnabled, pan: pan)
                    self.liveActivity.start()
                } catch {
                    self.lastError = "Could not start audio: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        Log.lifecycle.info("AudioDirectionDetector stopping")
        passthroughMixer.pause()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        classifier.reset()
        announcer.stop()
        frontBackResolver.stop()
        liveActivity.stop()
        sessionStats.end()
        subband?.reset()
        isRunning = false
    }

    // MARK: - Interruptions

    private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            // System has already suspended the engine. Mirror that in our
            // UI state; remember whether we were running so we can resume.
            Log.lifecycle.info("Audio interruption began")
            wasRunningBeforeInterruption = isRunning
            if isRunning {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                announcer.stop()
                frontBackResolver.stop()
                isRunning = false
            }

        case .ended:
            Log.lifecycle.info("Audio interruption ended")
            let shouldResume: Bool = {
                guard let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return false
                }
                return AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            }()
            if shouldResume && wasRunningBeforeInterruption {
                wasRunningBeforeInterruption = false
                start()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Scene lifecycle

    /// Called from `SoundCompassApp` when `scenePhase` becomes `.background`.
    /// The audio tap keeps running (thanks to `UIBackgroundModes: audio`),
    /// but we pause the CoreMotion front/back resolver so we don't spin
    /// the gyro budget while the user can't see the UI, and we flush the
    /// announcer so it stops mid-sentence.
    func handleBackgroundTransition() {
        sceneInBackground = true
        guard isRunning else { return }
        frontBackResolver.stop()
        announcer.stop()
    }

    /// Called from `SoundCompassApp` when `scenePhase` becomes `.active`.
    /// Resumes the resolver if we're still capturing audio.
    func handleForegroundTransition() {
        sceneInBackground = false
        guard isRunning else { return }
        frontBackResolver.start()
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        // Only re-configure on route changes that actually change the
        // input capabilities. `.categoryChange` / `.override` don't.
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            guard isRunning else { return }
            do {
                passthroughMixer.pause()
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                try configureSession()
                try installTap()
                try engine.start()
                // Re-check whether the new route supports CROS.
                passthroughMixer.handleRouteChange()
            } catch {
                lastError = "Audio route changed and could not be restarted: \(error.localizedDescription)"
                isRunning = false
            }
        default:
            break
        }
    }

    // MARK: - Audio session + tap

    private func configureSession() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker]
        )

        // Prefer the built-in mic so we get the multi-element array.
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtIn)

            Log.audio.info("Built-in mic: \(builtIn.portName, privacy: .public)")
            Log.audio.info("Data sources: \(builtIn.dataSources?.count ?? 0)")

            for source in builtIn.dataSources ?? [] {
                let patterns = source.supportedPolarPatterns?.map(\.rawValue) ?? []
                Log.audio.info("  Source: \(source.dataSourceName, privacy: .public) orientation: \(source.orientation?.rawValue ?? "nil", privacy: .public) patterns: \(patterns, privacy: .public)")
            }

            // iPhone "stereo" is a synthesized image and the FRONT and BACK
            // data sources produce MIRRORED left/right relative to each
            // other (WWDC20 session 10226). With the documented hold —
            // phone flat, screen up, top edge pointing away — the BACK
            // source's left/right match the user's left/right, so prefer
            // it explicitly instead of taking whichever source happens to
            // enumerate first. If only the front source supports stereo,
            // use it and flip the sign of every direction estimate.
            let stereoSources = (builtIn.dataSources ?? []).filter {
                $0.supportedPolarPatterns?.contains(.stereo) == true
            }
            let chosen = stereoSources.first(where: { $0.orientation == .back })
                ?? stereoSources.first

            if let chosen {
                try chosen.setPreferredPolarPattern(.stereo)
                try builtIn.setPreferredDataSource(chosen)
                let mirrored = chosen.orientation == .front
                directionSign = mirrored ? -1.0 : 1.0
                activeSourceDescription = "\(chosen.dataSourceName)\(mirrored ? " (mirrored)" : "")"
                Log.audio.info("  → Selected \(chosen.dataSourceName, privacy: .public) for stereo, directionSign \(self.directionSign)")
            } else {
                directionSign = 1.0
                activeSourceDescription = "no stereo source"
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

        // Log what the session actually gave us after activation.
        Log.audio.info("Session active — input channels: \(self.session.inputNumberOfChannels), sample rate: \(self.session.sampleRate)")
    }

    private func installTap() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let channels = Int(format.channelCount)
        Log.audio.info("Engine input format: \(channels) ch, \(format.sampleRate) Hz, \(format.commonFormat.rawValue)")
        isMono = channels < 2

        // Size-check and allocate DSP. GCC-PHAT buffers are allocated once.
        let sampleRate = format.sampleRate
        let estimator = DirectionEstimator(
            sampleRate: sampleRate,
            frameCount: Int(bufferFrames)
        )
        let subband = SubbandDirectionEstimator(
            sampleRate: sampleRate,
            frameCount: Int(bufferFrames),
            bands: SubbandDirectionEstimator.defaultBands()
        )
        self.estimator = estimator
        self.subband = subband

        classifier.configure(with: format)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferFrames, format: format) { [weak self] buffer, time in
            self?.process(buffer: buffer, time: time)
        }
    }

    // MARK: - DSP

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channels = Int(buffer.format.channelCount)

        // Classification is always best-effort and runs async on its own queue.
        classifier.analyze(buffer: buffer, at: time)

        // Mono path — no direction possible, just publish loudness.
        if channels < 2 {
            var rms: Float = 0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frames))
            let loudness = Double(min(rms * 8, 1.0))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.magnitude = self.magnitude * 0.6 + loudness * 0.4
                self.direction *= 0.9
            }
            return
        }

        guard let estimator = self.estimator, let subband = self.subband else { return }

        let left = channelData[0]
        let right = channelData[1]

        // The estimators see raw channels; un-mirror front-source capture
        // here so every consumer downstream gets user-space left/right.
        let sign = directionSign
        var broadband = estimator.estimate(left: left, right: right, frameCount: frames)
        broadband.direction *= sign
        let bands = subband.estimate(left: left, right: right, frameCount: frames).map {
            SubbandDirectionEstimator.BandResult(
                band: $0.band,
                direction: $0.direction * sign,
                magnitude: $0.magnitude
            )
        }

        // Pick the loudest band as the current focus.
        let dominant = bands.max(by: { $0.magnitude < $1.magnitude })

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let baseBlend = self.settings.sensitivity.directionBlend
            let magBlend = self.settings.sensitivity.magnitudeBlend

            // Hazard override: if the classifier has flagged a safety-
            // critical sound and the setting is on, skip the usual
            // exponential smoother so the arrow lands on the true
            // direction immediately.
            let rawId = self.classifier.topRawIdentifier
            let hazard = self.settings.hazardAlerts && HazardClassifier.isHazard(identifier: rawId)
            let dirBlend = hazard ? 0.9 : baseBlend

            if broadband.isConfident {
                self.direction = self.direction * (1 - dirBlend) + broadband.direction * dirBlend
            } else {
                self.direction *= 0.9
            }
            self.magnitude = self.magnitude * (1 - magBlend) + broadband.magnitude * magBlend
            self.bandResults = bands
            self.dominantBandName = dominant?.band.name
            self.debugDSP = self.settings.showDebugStats
                ? String(format: "src=%@ ILD=%.4f ITD=%.4f lag=%d conf=%.2f L=%.4f R=%.4f dir=%.3f",
                    self.activeSourceDescription,
                    broadband.rawILD, broadband.rawITD, broadband.lagSamples, broadband.itdConfidence,
                    broadband.leftRms, broadband.rightRms, broadband.direction)
                : ""

            if hazard {
                let friendly = rawId.map(HazardClassifier.friendlyLabel) ?? "Hazard"
                if !self.isHazardActive {
                    Log.hazard.warning("Hazard detected: \(friendly, privacy: .public) at direction \(self.direction)")
                    // Edge-triggered: record the entry only on rising edge.
                    self.eventHistory.record(
                        label: friendly,
                        rawIdentifier: rawId,
                        direction: self.direction,
                        magnitude: self.magnitude,
                        isHazard: true
                    )
                    self.sessionStats.record(label: friendly, direction: self.direction, isHazard: true)
                    // Background fallback: also post a local notification
                    // so the user knows about the hazard even when the
                    // SoundCompass screen is covered.
                    if self.sceneInBackground {
                        self.hazardNotifier.post(
                            label: friendly,
                            direction: self.direction,
                            allowed: self.settings.hazardAlerts
                        )
                    }
                }
                self.isHazardActive = true
                self.hazardLabel = friendly
            } else if self.isHazardActive && broadband.magnitude < 0.15 {
                // Decay hazard banner once the sound fades.
                self.isHazardActive = false
                self.hazardLabel = nil
            }

            // Also log non-hazard label transitions so the history has
            // context around each hazard ("car horn followed by speech").
            if let label = self.classifier.topLabel,
               !hazard,
               self.eventHistory.events.first?.rawIdentifier != rawId {
                self.eventHistory.record(
                    label: label,
                    rawIdentifier: rawId,
                    direction: self.direction,
                    magnitude: self.magnitude,
                    isHazard: false
                )
                self.sessionStats.record(label: label, direction: self.direction, isHazard: false)
            }

            // Feed the motion-based resolver so it can pair this direction
            // sample with the current cumulative yaw.
            if broadband.isConfident {
                self.frontBackResolver.recordDirection(self.direction)
            }

            // Fan-out to the speech announcer, the watch mirror, and the
            // Live Activity on the Lock Screen / Dynamic Island.
            let label = self.classifier.topLabel
            self.announcer.announce(
                direction: self.direction,
                magnitude: self.magnitude,
                label: label
            )
            self.watchSession.send(
                direction: self.direction,
                magnitude: self.magnitude,
                label: label
            )
            self.liveActivity.update(
                direction: self.direction,
                magnitude: self.magnitude,
                label: DirectionLabel.label(for: self.direction),
                classifierLabel: label
            )
        }
    }
}
