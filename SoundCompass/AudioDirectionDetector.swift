import AVFoundation
import Accelerate
import Combine
import Foundation
import os

/// The top-level audio capture + processing object the SwiftUI views talk to.
///
/// `AudioDirectionDetector` owns the `AVAudioEngine` tap and a suite of
/// processors:
///
/// * `DirectionEstimator` — broadband ILD (+ optional ITD) → raw estimate.
/// * `DirectionSmoother` — the exponential smoother behind `direction`
///   and `magnitude`.
/// * `SubbandDirectionEstimator` — per-band direction + magnitude so we can
///   tell rumble from speech from alarms.
/// * `SoundClassifier` — Apple's built-in `SNClassifySoundRequest` to tag
///   the loudest sound ("speech", "car horn", "dog bark", …).
/// * `HazardGate` — edge-triggered hazard banner state.
/// * `SpeechAnnouncer` — optional spoken callouts through the hearing ear.
/// * `WatchSessionManager` — mirrors everything to the watchOS companion.
///
/// The DSP runs on the engine's tap thread (not the real-time render
/// thread, but it must keep up); @Published updates are dispatched onto
/// the main queue once per tap buffer.
final class AudioDirectionDetector: ObservableObject {

    // MARK: - Published state

    @Published private(set) var direction: Double = 0
    @Published private(set) var magnitude: Double = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isMono: Bool = false
    @Published private(set) var lastError: String?
    /// `true` when `lastError` is a microphone-permission denial, so the
    /// UI can offer the Settings deep link instead of a generic banner.
    @Published private(set) var isPermissionDenied: Bool = false
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

    // DSP state. Accessed only from the tap thread after `start()` returns
    // (the estimators are rebuilt only while the tap is removed).
    private var estimator: DirectionEstimator?
    private var subband: SubbandDirectionEstimator?
    private let bufferFrames: AVAudioFrameCount = 2048

    /// Main-thread state behind `direction` / `magnitude` / hazard banner.
    private var smoother = DirectionSmoother()
    private var hazardGate = HazardGate()

    /// `-1` when the active stereo data source delivers a mirrored image
    /// (front source), `+1` otherwise. Written in `configureSession()`
    /// before the tap is installed; read on the tap thread.
    private var directionSign: Double = 1.0

    /// Human-readable description of the stereo source in use, for the
    /// debug overlay ("Back", "Front (mirrored)", "no stereo source").
    private var activeSourceDescription: String = "?"

    /// Set once the mono-input diagnostic marker has been written for the
    /// current tap; reset on every `installTap()`. Keeps the tap thread
    /// from allocating a note string per mono frame.
    private var loggedMonoDiagnostic = false

    /// Frames received before this instant are ignored for direction and
    /// classification: the phone's own speech callouts and haptic taps
    /// are picked up by the microphones 10 cm away and would otherwise
    /// classify as "speech" / register as low-band thumps. Written on the
    /// main thread, read on the tap thread.
    private let muteUntil = OSAllocatedUnfairLock<Date>(initialState: .distantPast)

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

        // Mute the mic path while the phone is talking.
        announcer.onSpeakingChanged = { [weak self] speaking in
            self?.setSpeechMute(speaking)
        }

        // Passthrough toggle + hearing-ear changes both flow into the
        // passthrough mixer's pan + enabled state.
        Publishers.CombineLatest(settings.$passthroughEnabled, settings.$hearingEar)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, ear in
                guard let self, self.isRunning else { return }
                self.passthroughMixer.setEnabled(enabled, pan: ear.pan)
            }
            .store(in: &settingsCancellables)

        // A calibrated ILD gain applies immediately to the live estimators.
        settings.$ildGain
            .receive(on: DispatchQueue.main)
            .sink { [weak self] gain in
                guard let self else { return }
                let effective = gain ?? DirectionEstimator.defaultIldGain
                self.estimator?.ildGain = effective
                self.subband?.setIldGain(effective)
            }
            .store(in: &settingsCancellables)

        // Switching the ILD measurement band needs new filters, so the
        // estimators are rebuilt behind a tap reinstall.
        settings.$ildHighBand
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                self.restartCapture(reason: "ILD band changed")
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
                    self.lastError = String(localized: "Microphone access was denied. Enable it in Settings to use SoundCompass.")
                    self.isPermissionDenied = true
                    return
                }
                do {
                    try self.configureSession()
                    try self.installTap()
                    try self.engine.start()
                    DSPDiagnostics.shared.begin(
                        config: self.diagnosticsConfigLine(),
                        enabled: self.settings.showDebugStats
                    )
                    self.smoother.reset()
                    self.hazardGate.reset()
                    self.isRunning = true
                    self.lastError = nil
                    self.isPermissionDenied = false
                    self.sessionStats.begin()
                    self.frontBackResolver.start()
                    self.passthroughMixer.setEnabled(self.settings.passthroughEnabled, pan: self.settings.hearingEar.pan)
                    self.liveActivity.start()
                } catch {
                    self.lastError = String(localized: "Could not start audio: \(error.localizedDescription)")
                    self.isPermissionDenied = false
                }
            }
        }
    }

    /// One-line description of the capture setup for the trace header.
    private func diagnosticsConfigLine() -> String {
        let engineChannels = engine.inputNode.inputFormat(forBus: 0).channelCount
        let gain = estimator?.ildGain ?? 0
        var band = "broadband"
        if let range = estimator?.ildBandHz {
            band = "\(range.lowerBound)-\(range.upperBound)"
        }
        let parts: [String] = [
            "source=\(activeSourceDescription)",
            "sign=\(directionSign)",
            "sessionChannels=\(session.inputNumberOfChannels)",
            "sampleRate=\(session.sampleRate)",
            "engineFormat=\(engineChannels)ch",
            "ildGain=\(gain)",
            "ildBand=\(band)",
        ]
        return parts.joined(separator: " ")
    }

    func stop() {
        guard isRunning else { return }
        Log.lifecycle.info("AudioDirectionDetector stopping")
        teardown()
    }

    /// Shared teardown for every path that ends a capture session: user
    /// stop, interruption `.began`, and a failed restart.
    private func teardown() {
        passthroughMixer.pause()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        classifier.reset()
        announcer.stop()
        frontBackResolver.stop()
        liveActivity.stop()
        sessionStats.end()
        subband?.reset()
        estimator?.reset()
        DSPDiagnostics.shared.end()
        muteUntil.withLock { $0 = .distantPast }
        isRunning = false
        isHazardActive = false
        hazardLabel = nil
    }

    /// Reinstall the tap against the current session state without
    /// ending the session (used for route changes and DSP reconfiguration).
    private func restartCapture(reason: String) {
        Log.lifecycle.info("Restarting capture: \(reason, privacy: .public)")
        do {
            passthroughMixer.pause()
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try configureSession()
            try installTap()
            try engine.start()
            passthroughMixer.handleRouteChange()
        } catch {
            lastError = String(localized: "Audio route changed and could not be restarted: \(error.localizedDescription)")
            isPermissionDenied = false
            teardown()
        }
    }

    // MARK: - Self-excitation gating

    /// Ignore microphone input until `duration` from now. Used by the UI
    /// after firing a haptic so the Taptic Engine's thump does not read
    /// as a low-band sound.
    func muteInput(for duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        muteUntil.withLock { current in
            if until > current { current = until }
        }
    }

    /// Upper bound on a speech mute, so a missed `didFinish` (interrupted
    /// synthesizer, audio session reset) cannot silence the mic for good.
    /// Callouts are a few words; 8 s is far beyond any of them.
    private static let maxSpeechMute: TimeInterval = 8

    private func setSpeechMute(_ speaking: Bool) {
        let until = Date().addingTimeInterval(
            speaking ? AudioDirectionDetector.maxSpeechMute : 0.3  // 0.3 s tail for the room's reverberation
        )
        muteUntil.withLock { $0 = until }
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
                teardown()
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

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            guard isRunning else { return }
            // Only reinstall the tap when the *input* actually changed.
            // `configureSession()` itself (data source, polar pattern,
            // orientation) posts route-change notifications, and a naive
            // restart-on-every-notification turns into a restart storm.
            // Output-only changes (headphones in/out) matter only to the
            // passthrough mixer.
            let previous = (userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
                .map(AudioSessionConfigurator.inputSignature(of:))
            let current = AudioSessionConfigurator.inputSignature(of: session.currentRoute)
            if let previous, previous == current {
                passthroughMixer.handleRouteChange()
            } else {
                restartCapture(reason: "input route changed (\(reason.rawValue))")
            }
        default:
            break
        }
    }

    // MARK: - Audio session + tap

    private func configureSession() throws {
        let selection = try AudioSessionConfigurator.configureForStereoCapture(session)
        directionSign = selection.directionSign
        activeSourceDescription = selection.description
    }

    private func installTap() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let channels = Int(format.channelCount)
        Log.audio.info("Engine input format: \(channels) ch, \(format.sampleRate) Hz, \(format.commonFormat.rawValue)")

        // A 0 Hz / 0-channel format (permission race, some CarPlay and
        // Simulator routes) makes `installTap` and `SNAudioStreamAnalyzer`
        // raise Objective-C exceptions that Swift cannot catch. Refuse it
        // here with a real error instead of crashing.
        guard format.sampleRate > 0, channels > 0 else {
            throw NSError(
                domain: "SoundCompass.AudioDirectionDetector",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "The microphone did not report a usable audio format. Try again.")]
            )
        }
        isMono = channels < 2

        // Size-check and allocate DSP. GCC-PHAT buffers are allocated once.
        let sampleRate = format.sampleRate
        let gain = settings.ildGain ?? DirectionEstimator.defaultIldGain
        let estimator = DirectionEstimator(
            sampleRate: sampleRate,
            frameCount: Int(bufferFrames),
            ildGain: gain,
            ildBandHz: settings.ildHighBand ? SettingsStore.highBandILDRange : nil
        )
        let subband = SubbandDirectionEstimator(
            sampleRate: sampleRate,
            frameCount: Int(bufferFrames),
            bands: SubbandDirectionEstimator.defaultBands()
        )
        subband.setIldGain(gain)
        self.estimator = estimator
        self.subband = subband
        loggedMonoDiagnostic = false

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

        let muted = Date() < muteUntil.withLock { $0 }

        // Classification is always best-effort and runs async on its own
        // queue — but not while the phone is the one making the sound.
        if !muted {
            classifier.analyze(buffer: buffer, at: time)
        }

        // Mono or muted: no direction possible, just publish loudness.
        if channels < 2 || muted {
            if channels < 2, !loggedMonoDiagnostic {
                // Edge-triggered: one marker per tap install, not one per
                // frame — the tap thread should stay free of per-frame
                // string building.
                loggedMonoDiagnostic = true
                DSPDiagnostics.shared.note("MONO input (\(channels)ch) — direction impossible")
            }
            var rms: Float = 0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frames))
            let loudness = Double(min(rms * 8, 1.0))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.smoother.updateLoudnessOnly(loudness, magnitudeBlend: self.settings.sensitivity.magnitudeBlend)
                self.publishSmoothed()
            }
            return
        }

        guard let estimator = self.estimator, let subband = self.subband else { return }

        let left = channelData[0]
        let right = channelData[1]
        let sign = directionSign
        let chunk = Int(bufferFrames)

        // The estimators are sized for `bufferFrames`, and installTap's
        // bufferSize is only a hint: devices routinely deliver larger
        // buffers. Walk the buffer in chunks so every frame is analysed
        // (the streaming band filters need the continuity anyway) and
        // combine the chunk estimates: direction weighted by energy,
        // loudness as the peak.
        var weightedDirection = 0.0
        var weight = 0.0
        var peakLoudness = 0.0
        var peakRms = 0.0
        var latest = DirectionEstimate(direction: 0, magnitude: 0, combinedRms: 0, isConfident: false)
        var bands: [SubbandDirectionEstimator.BandResult] = []
        var offset = 0
        while offset < frames {
            let n = min(chunk, frames - offset)
            var chunkEstimate = estimator.estimate(left: left + offset, right: right + offset, frameCount: n)
            chunkEstimate.direction *= sign
            bands = subband.estimate(left: left + offset, right: right + offset, frameCount: n, directionSign: sign)
            if chunkEstimate.isConfident {
                let w = chunkEstimate.combinedRms * Double(n)
                weightedDirection += chunkEstimate.direction * w
                weight += w
            }
            peakLoudness = max(peakLoudness, chunkEstimate.magnitude)
            peakRms = max(peakRms, chunkEstimate.combinedRms)
            latest = chunkEstimate
            offset += n
        }

        var broadband = latest
        broadband.magnitude = peakLoudness
        broadband.combinedRms = peakRms
        if weight > 0 {
            broadband.direction = weightedDirection / weight
            broadband.isConfident = true
        }

        // Pick the loudest band as the current focus.
        let dominant = bands.max(by: { $0.magnitude < $1.magnitude })

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.consume(broadband: broadband, bands: bands, dominant: dominant)
        }
    }

    /// Main-thread half of the per-buffer update: smoothing, hazard state,
    /// history, and fan-out.
    private func consume(
        broadband: DirectionEstimate,
        bands: [SubbandDirectionEstimator.BandResult],
        dominant: SubbandDirectionEstimator.BandResult?
    ) {
        classifier.expireStaleLabel()
        let rawId = classifier.topRawIdentifier
        let hazardSound = settings.hazardAlerts && HazardClassifier.isHazard(identifier: rawId)

        // Hazard override: if the classifier has flagged a safety-critical
        // sound and the setting is on, nearly skip the exponential
        // smoother so the arrow lands on the true direction immediately.
        let dirBlend = hazardSound ? 0.9 : settings.sensitivity.directionBlend
        smoother.update(
            estimate: broadband,
            directionBlend: dirBlend,
            magnitudeBlend: settings.sensitivity.magnitudeBlend
        )
        publishSmoothed()

        bandResults = bands
        dominantBandName = dominant?.band.name

        if settings.showDebugStats {
            let bandSummary = bands
                .map { String(format: "%@:%.4f", $0.band.name, $0.rawILD) }
                .joined(separator: "|")
            DSPDiagnostics.shared.append(
                estimate: broadband,
                smoothDir: direction,
                magnitude: magnitude,
                bandILD: bandSummary
            )
            debugDSP = String(
                format: "src=%@ ILD=%.4f ITD=%.4f lag=%d conf=%.2f L=%.4f R=%.4f iL=%.4f iR=%.4f dir=%.3f",
                activeSourceDescription,
                broadband.rawILD, broadband.rawITD, broadband.lagSamples, broadband.itdConfidence,
                broadband.leftRms, broadband.rightRms, broadband.ildLeftRms, broadband.ildRightRms,
                broadband.direction
            )
        } else if !debugDSP.isEmpty {
            debugDSP = ""
        }

        switch hazardGate.update(isHazardSound: hazardSound, magnitude: broadband.magnitude) {
        case .began:
            let friendly = rawId.map(HazardClassifier.friendlyLabel) ?? String(localized: "Hazard")
            Log.hazard.warning("Hazard detected: \(friendly, privacy: .public) at direction \(self.direction)")
            eventHistory.record(
                label: friendly,
                rawIdentifier: rawId,
                direction: direction,
                magnitude: magnitude,
                isHazard: true
            )
            sessionStats.record(label: friendly, direction: direction, isHazard: true)
            // Background fallback: also post a local notification so the
            // user knows about the hazard even when the SoundCompass
            // screen is covered.
            if sceneInBackground {
                hazardNotifier.post(
                    label: friendly,
                    direction: direction,
                    allowed: settings.hazardAlerts
                )
            }
            isHazardActive = true
            hazardLabel = friendly
        case .ended:
            isHazardActive = false
            hazardLabel = nil
        case .none:
            break
        }

        // Also log non-hazard label transitions so the history has
        // context around each hazard ("car horn followed by speech").
        if let label = classifier.topLabel,
           !hazardSound,
           eventHistory.events.first?.rawIdentifier != rawId {
            eventHistory.record(
                label: label,
                rawIdentifier: rawId,
                direction: direction,
                magnitude: magnitude,
                isHazard: false
            )
            sessionStats.record(label: label, direction: direction, isHazard: false)
        }

        // Feed the motion-based resolver so it can pair this direction
        // sample with the current cumulative yaw.
        if broadband.isConfident {
            frontBackResolver.recordDirection(direction)
        }

        // Fan-out to the speech announcer, the watch mirror, and the
        // Live Activity on the Lock Screen / Dynamic Island.
        let label = classifier.topLabel
        announcer.announce(
            direction: direction,
            magnitude: magnitude,
            label: label
        )
        watchSession.send(
            direction: direction,
            magnitude: magnitude,
            label: label,
            isHazard: isHazardActive
        )
        liveActivity.update(
            direction: direction,
            magnitude: magnitude,
            label: DirectionLabel.label(for: direction),
            classifierLabel: label
        )
    }

    private func publishSmoothed() {
        direction = smoother.direction
        magnitude = smoother.magnitude
    }
}
