import Combine
import CoreMotion
import Foundation

/// Resolves the front/back ambiguity inherent to a two-microphone direction
/// estimator by correlating the *change* in measured direction with the
/// *change* in device yaw.
///
/// The physics
/// -----------
/// With only two microphones we cannot measure elevation or front/back —
/// the left/right cue `d = sin(θ)` has the same value for `θ = 30°` (front
/// right) and `θ = 150°` (back right). The fix is to let the user rotate
/// the phone. CoreMotion's device frame is right-handed with `z` out of
/// the screen, so with the phone flat and screen up **positive yaw is a
/// counter-clockwise turn** seen from above. A CCW turn swings the phone's
/// top edge to the left, so a world-fixed source *in front* drifts to the
/// right of the device's forward axis: `d` grows with yaw. A source
/// *behind* drifts the other way. The **sign** of `∂d / ∂yaw` therefore
/// disambiguates front from back:
///
/// * slope `> 0` → source is in front
/// * slope `< 0` → source is behind
/// * magnitude below `confidenceThreshold` or yaw hasn't changed much yet
///   → ambiguous; the user needs to rotate more.
///
/// (An earlier version had these two cases swapped because it assumed
/// clockwise = positive yaw.)
///
/// The regression runs over a short sliding window of
/// `(unwrappedYaw, direction)` samples so the estimate updates continuously
/// as the user moves the phone. Once a `front`/`back` result is reached it
/// is **latched** for `latchDuration`, otherwise the answer would vanish a
/// couple of seconds after the user stops turning (the window's yaw range
/// collapses and the resolver would fall back to "keep rotating").
///
/// Yaw handling
/// ------------
/// `CMDeviceMotion.attitude.yaw` wraps at `±π`. We unwrap by accumulating
/// frame-to-frame deltas into `cumulativeYaw`, which gives us a continuous
/// signal even when the user rotates through the wrap point.
final class FrontBackResolver: ObservableObject {

    enum Resolution: Equatable {
        /// Not enough data yet — motion updates just started, or no
        /// direction samples have been recorded.
        case unknown
        /// User hasn't rotated far enough for a reliable estimate.
        case needsRotation(accumulatedDegrees: Double)
        /// Confident the source is in front of the user.
        case front
        /// Confident the source is behind the user.
        case back
    }

    // MARK: - Published state

    @Published private(set) var resolution: Resolution = .unknown
    @Published private(set) var yawRangeDegrees: Double = 0
    @Published private(set) var slope: Double = 0
    @Published private(set) var isMotionAvailable: Bool = false

    // MARK: - Tunables

    /// Maximum number of (yaw, direction) samples kept in the regression
    /// window. Samples arrive once per DSP frame (~23 Hz for 2048-frame
    /// buffers at 48 kHz), so 60 samples ≈ 2.6 s.
    private let maxSamples: Int = 60

    /// Minimum yaw range (in radians) required before a resolution other
    /// than `.needsRotation` can be emitted. 15° by default.
    private let minYawRange: Double = 15 * .pi / 180

    /// Minimum slope magnitude (direction change per radian of yaw) before
    /// we commit to front/back.
    private let confidenceThreshold: Double = 0.5

    /// How long a `front`/`back` result survives after the window stops
    /// supporting it.
    let latchDuration: TimeInterval

    // MARK: - Private state

    private let motion: CMMotionManager
    private let queue: OperationQueue
    private let now: () -> Date

    private var samples: [(yaw: Double, direction: Double)] = []
    private var previousRawYaw: Double?
    private var cumulativeYaw: Double = 0
    private var latched: (resolution: Resolution, at: Date)?

    init(
        motion: CMMotionManager = CMMotionManager(),
        latchDuration: TimeInterval = 10,
        now: @escaping () -> Date = { Date() }
    ) {
        self.motion = motion
        self.latchDuration = latchDuration
        self.now = now
        self.queue = OperationQueue()
        self.queue.name = "com.soundcompass.motion"
        self.queue.maxConcurrentOperationCount = 1
        self.isMotionAvailable = motion.isDeviceMotionAvailable
    }

    // MARK: - Lifecycle

    /// Start CoreMotion updates. No-op if the device doesn't support
    /// CoreMotion (e.g. some iPad simulators). Surfaces
    /// `isMotionAvailable` as a published property so the UI can show
    /// an explanatory message when front/back disambiguation isn't
    /// going to work.
    func start() {
        guard motion.isDeviceMotionAvailable else {
            isMotionAvailable = false
            resolution = .unknown
            return
        }
        guard !motion.isDeviceMotionActive else { return }
        isMotionAvailable = true

        motion.deviceMotionUpdateInterval = 0.02  // 50 Hz
        motion.startDeviceMotionUpdates(to: queue) { [weak self] deviceMotion, error in
            if let error {
                Log.motion.error("Device motion failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self?.isMotionAvailable = false
                    self?.resolution = .unknown
                }
                return
            }
            guard let self, let deviceMotion else { return }
            self.ingestYaw(deviceMotion.attitude.yaw)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        reset()
    }

    /// Clears the sample window and any latched result.
    func reset() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.clearState()
            DispatchQueue.main.async {
                self.resolution = .unknown
                self.yawRangeDegrees = 0
                self.slope = 0
            }
        }
    }

    // MARK: - Ingestion

    /// Called by `AudioDirectionDetector` after each DSP update.
    /// Dispatches onto the motion queue so all access to `samples`,
    /// `cumulativeYaw`, and `previousRawYaw` is serialized.
    func recordDirection(_ direction: Double) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.appendSample(yaw: self.cumulativeYaw, direction: direction)
            self.updateResolution()
        }
    }

    private func ingestYaw(_ rawYaw: Double) {
        // Unwrap: convert ±π-wrapping yaw into a continuous signal by
        // accumulating frame-to-frame deltas.
        if let previous = previousRawYaw {
            var delta = rawYaw - previous
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            cumulativeYaw += delta
        } else {
            cumulativeYaw = 0
        }
        previousRawYaw = rawYaw
    }

    private func appendSample(yaw: Double, direction: Double) {
        samples.append((yaw: yaw, direction: direction))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    private func clearState() {
        samples.removeAll(keepingCapacity: true)
        previousRawYaw = nil
        cumulativeYaw = 0
        latched = nil
    }

    // MARK: - Regression

    private func updateResolution() {
        guard samples.count >= 6 else {
            publish(.unknown, range: 0, slope: 0)
            return
        }

        // Yaw range over the current window. If the user hasn't rotated
        // far enough, ask them to rotate more — unless a recent result is
        // still latched.
        let yaws = samples.map(\.yaw)
        let minYaw = yaws.min() ?? 0
        let maxYaw = yaws.max() ?? 0
        let range = maxYaw - minYaw
        let rangeDegrees = range * 180 / .pi

        guard range >= minYawRange else {
            publish(latchedOr(.needsRotation(accumulatedDegrees: rangeDegrees)), range: rangeDegrees, slope: 0)
            return
        }

        // Ordinary-least-squares linear regression of direction on yaw.
        //   slope = (n·Σxy − Σx·Σy) / (n·Σx² − (Σx)²)
        let n = Double(samples.count)
        let sumX = yaws.reduce(0, +)
        let sumY = samples.map(\.direction).reduce(0, +)
        let sumXY = samples.reduce(0) { $0 + $1.yaw * $1.direction }
        let sumX2 = yaws.reduce(0) { $0 + $1 * $1 }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator > 1e-9 else {
            publish(latchedOr(.needsRotation(accumulatedDegrees: rangeDegrees)), range: rangeDegrees, slope: 0)
            return
        }

        let computedSlope = (n * sumXY - sumX * sumY) / denominator

        let resolved: Resolution
        if computedSlope > confidenceThreshold {
            resolved = .front
            latched = (.front, now())
        } else if computedSlope < -confidenceThreshold {
            resolved = .back
            latched = (.back, now())
        } else {
            resolved = latchedOr(.needsRotation(accumulatedDegrees: rangeDegrees))
        }

        publish(resolved, range: rangeDegrees, slope: computedSlope)
    }

    /// The latched `front`/`back` result while it is still fresh,
    /// otherwise `fallback`.
    private func latchedOr(_ fallback: Resolution) -> Resolution {
        if let latched, now().timeIntervalSince(latched.at) < latchDuration {
            return latched.resolution
        }
        latched = nil
        return fallback
    }

    private func publish(_ resolution: Resolution, range: Double, slope: Double) {
        // Dispatched to main even when called from main to satisfy
        // observers that expect object publications on the main queue.
        let newResolution = resolution
        let newRange = range
        let newSlope = slope
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.resolution != newResolution {
                self.resolution = newResolution
            }
            self.yawRangeDegrees = newRange
            self.slope = newSlope
        }
    }
}

// MARK: - Deterministic test hook

#if DEBUG
extension FrontBackResolver {
    /// Test-only: feed synthetic (yaw, direction) samples directly without
    /// going through CoreMotion. Runs synchronously on the motion queue
    /// so test assertions can read results immediately after.
    func _injectForTesting(yaw: Double, direction: Double) {
        queue.addOperations([BlockOperation { [self] in
            self.cumulativeYaw = yaw
            self.appendSample(yaw: yaw, direction: direction)
            self.updateResolution()
        }], waitUntilFinished: true)
        // Drain the main queue so @Published updates land before assertions.
        RunLoop.main.run(until: Date())
    }

    /// Test-only: synchronously reset state.
    func _resetForTesting() {
        queue.addOperations([BlockOperation { [self] in
            self.clearState()
        }], waitUntilFinished: true)
        DispatchQueue.main.async { [self] in
            self.resolution = .unknown
            self.yawRangeDegrees = 0
            self.slope = 0
        }
        RunLoop.main.run(until: Date())
    }
}
#endif
