import Foundation

/// Writes a per-frame CSV trace of the DSP pipeline into the app's
/// Documents directory so it can be pulled off a device with
/// `devicectl device copy from … --domain-type appDataContainer` and
/// analyzed offline. The overlay shows one frame at a time; this captures
/// the whole session.
///
/// The file is truncated on every `begin(config:)` so it only ever holds
/// the most recent listening session. Writes are funneled through a
/// serial utility queue, so `append` is safe to call from the audio tap
/// thread without blocking it.
final class DSPDiagnostics {

    static let shared = DSPDiagnostics()

    private let queue = DispatchQueue(label: "com.soundcompass.diagnostics", qos: .utility)
    private var handle: FileHandle?
    private var startedAt: Date?

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dsp-diagnostics.csv")
    }

    /// Truncate the trace and write a header. `config` should describe the
    /// capture setup (data source, channels, sample rate, direction sign).
    func begin(config: String) {
        queue.async { [self] in
            try? handle?.close()
            let fm = FileManager.default
            fm.createFile(atPath: fileURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: fileURL)
            startedAt = Date()
            write("# \(config)\n")
            write("t,leftRms,rightRms,ildRaw,lag,itdConf,rawDir,smoothDir,magnitude\n")
        }
    }

    /// Append one DSP frame. `smoothDir` is the post-smoothing published
    /// direction; everything else comes straight from `DirectionEstimate`.
    func append(estimate: DirectionEstimate, smoothDir: Double, magnitude: Double) {
        queue.async { [self] in
            guard let startedAt else { return }
            let t = Date().timeIntervalSince(startedAt)
            write(String(
                format: "%.2f,%.5f,%.5f,%.4f,%d,%.2f,%.3f,%.3f,%.3f\n",
                t, estimate.leftRms, estimate.rightRms, estimate.rawILD,
                estimate.lagSamples, estimate.itdConfidence,
                estimate.direction, smoothDir, magnitude
            ))
        }
    }

    /// Append a marker line (e.g. "MONO input — no direction possible").
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

    private func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        try? handle?.write(contentsOf: data)
    }
}
