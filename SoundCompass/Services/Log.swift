import Foundation
import OSLog

/// Central home for `os.Logger` instances so every subsystem can log to
/// the same unified-logging stream under a single subsystem identifier.
///
/// Why unify: the moment you try to reproduce a user-reported bug in
/// Console.app, you want to be able to filter by subsystem
/// `com.soundcompass.app` and see every detector / motion / classifier
/// line in one place, in order.
///
/// `.info` / `.warning` / `.error` are used for lifecycle and failure
/// paths only; nothing logs per DSP frame (that is what `DSPDiagnostics`
/// is for).
enum Log {
    private static let subsystem = "com.soundcompass.app"

    static let audio       = Logger(subsystem: subsystem, category: "audio")
    static let motion      = Logger(subsystem: subsystem, category: "motion")
    static let classifier  = Logger(subsystem: subsystem, category: "classifier")
    static let passthrough = Logger(subsystem: subsystem, category: "passthrough")
    static let hazard      = Logger(subsystem: subsystem, category: "hazard")
    static let lifecycle   = Logger(subsystem: subsystem, category: "lifecycle")
}
