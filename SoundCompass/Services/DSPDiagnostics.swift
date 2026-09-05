import Foundation

/// Writes a per-frame CSV trace of the DSP pipeline into the app's
/// Documents directory so it can be pulled off a device with
/// `devicectl device copy from … --domain-type appDataContainer` and
/// analyzed offline. The overlay shows one frame at a time; this captures
/// the whole session.
///
/// Tracing only runs when the developer "Show DSP stats" setting is on at
/// session start (`begin(config:enabled:)`); otherwise no file is written
/// and any trace from a previous session is deleted. The file is truncated
/// on every enabled `begin` so it only ever holds the most recent listening
/// session, and capped at `maxBytes` so an all-day session can't grow it
/// unbounded. Writes are funneled through a serial utility queue, so
/// `append` is safe to call from the audio tap thread without blocking it.
final class DSPDiagnostics {

    static let shared = DSPDiagnostics()

    private let queue = DispatchQueue(label: "com.soundcompass.diagnostics", qos: .utility)
    private var handle: FileHandle?
    private var startedAt: Date?
    private var bytesWritten = 0

    let fileURL: URL
    private let maxBytes: Int

    init(fileURL: URL? = nil, maxBytes: Int = 20 * 1024 * 1024) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dsp-diagnostics.csv")
        self.maxBytes = maxBytes
    }

    /// Start a capture. When `enabled` is false this is a teardown instead:
    /// no file is opened and any previous session's trace is removed, so no
    /// stale acoustic log lingers after the user turns the toggle off.
    /// `config` should describe the capture setup (data source, channels,
    /// sample rate, direction sign).
    func begin(config: String, enabled: Bool) {
        queue.async { [self] in
            try? handle?.close()
            handle = nil
            startedAt = nil
            bytesWritten = 0

            let fm = FileManager.default
            guard enabled else {
                try? fm.removeItem(at: fileURL)
                return
            }
            fm.createFile(atPath: fileURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: fileURL)
            startedAt = Date()
            write("# \(config)\n")
            write("t,leftRms,rightRms,ildLeftRms,ildRightRms,ildRaw,lag,itdConf,rawDir,smoothDir,magnitude,bandILD\n")
        }
    }

    /// Append one DSP frame. `smoothDir` is the post-smoothing published
    /// direction; `bandILD` is a `name:ild|name:ild` summary of the
    /// per-band raw level differences; everything else comes straight from
    /// `DirectionEstimate`. No-op unless an enabled `begin` opened the trace.
    func append(estimate: DirectionEstimate, smoothDir: Double, magnitude: Double, bandILD: String = "") {
        queue.async { [self] in
            guard let startedAt else { return }
            let t = Date().timeIntervalSince(startedAt)
            write(String(
                format: "%.2f,%.5f,%.5f,%.5f,%.5f,%.4f,%d,%.2f,%.3f,%.3f,%.3f,%@\n",
                t, estimate.leftRms, estimate.rightRms,
                estimate.ildLeftRms, estimate.ildRightRms, estimate.rawILD,
                estimate.lagSamples, estimate.itdConfidence,
                estimate.direction, smoothDir, magnitude, bandILD
            ))
        }
    }

    /// Append a marker line (e.g. "MONO input — no direction possible").
    /// No-op unless an enabled `begin` opened the trace.
    func note(_ message: String) {
        queue.async { [self] in
            write("# \(message)\n")
        }
    }

    func end() {
        queue.async { [self] in
            try? handle?.close()
            handle = nil
            startedAt = nil
        }
    }

    /// Blocks until every previously enqueued write has landed. Test-only.
    func flush() {
        queue.sync {}
    }

    private func write(_ string: String) {
        guard let handle, let data = string.data(using: .utf8) else { return }
        if bytesWritten + data.count > maxBytes {
            if let marker = "# trace capped at \(maxBytes) bytes\n".data(using: .utf8) {
                try? handle.write(contentsOf: marker)
            }
            try? handle.close()
            self.handle = nil
            return
        }
        bytesWritten += data.count
        try? handle.write(contentsOf: data)
    }
}
