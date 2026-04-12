import Foundation
import OSLog

/// Central home for `os.Logger` instances so every subsystem can log to
/// the same unified-logging stream under a single subsystem identifier.
///
/// Why unify: the moment you try to reproduce a user-reported bug in
/// Console.app, you want to be able to filter by subsystem
/// `com.soundcompass.app` and see every detector / DSP / motion /
/// classifier line in one place, in order.
///
/// Logger is essentially free at call sites — most log lines compile
/// away to a single static function call plus a format-string builder.
/// We use `.debug` for high-volume lines (tap callbacks, per-frame
/// state) and `.info` / `.error` for lifecycle and failure paths.
enum Log {
    private static let subsystem = "com.soundcompass.app"

    static let audio       = Logger(subsystem: subsystem, category: "audio")
    static let dsp         = Logger(subsystem: subsystem, category: "dsp")
    static let motion      = Logger(subsystem: subsystem, category: "motion")
    static let classifier  = Logger(subsystem: subsystem, category: "classifier")
    static let passthrough = Logger(subsystem: subsystem, category: "passthrough")
    static let watch       = Logger(subsystem: subsystem, category: "watch")
    static let hazard      = Logger(subsystem: subsystem, category: "hazard")
    static let lifecycle   = Logger(subsystem: subsystem, category: "lifecycle")
    static let settings    = Logger(subsystem: subsystem, category: "settings")
}
