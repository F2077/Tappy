import Foundation
import Logging
import OSLog

/// App-wide logging: swift-log facade backed by os_log, so entries land
/// in the unified logging system (Console.app, `log show/stream`) under
/// subsystem `local.tappy.app` — and stay debuggable even when the app
/// runs from LaunchServices with no terminal attached.
///
/// `Log.bootstrap()` must run once per process before the first logger
/// is created (TappyApp.init and TappyChecks' main both call it).
public enum Log {
    public static let subsystem = "local.tappy.app"

    /// Guarded by usage: bootstrap() is called exactly once at process
    /// start, before any thread does logging.
    nonisolated(unsafe) private static var bootstrapped = false

    public static func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        LoggingSystem.bootstrap { label in
            OSLogHandler(category: String(label.split(separator: ".").last ?? "app"))
        }
    }

    /// A logger for a subsystem category, e.g. "spawn".
    public static func logger(_ category: String) -> Logging.Logger {
        Logging.Logger(label: "\(subsystem).\(category)")
    }
}

/// Minimal swift-log backend forwarding to os.Logger.
struct OSLogHandler: LogHandler {
    private let osLogger: os.Logger

    var logLevel: Logging.Logger.Level = .info
    var metadata: Logging.Logger.Metadata = [:]

    init(category: String) {
        osLogger = os.Logger(subsystem: Log.subsystem, category: category)
    }

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logging.Logger.Level, message: Logging.Logger.Message,
             metadata: Logging.Logger.Metadata?, source: String,
             file: String, function: String, line: UInt) {
        var text = "\(message)"
        if let metadata, !metadata.isEmpty {
            text += " \(metadata.map { "\($0)=\($1)" }.sorted().joined(separator: " "))"
        }
        let osLevel: OSLogType = switch level {
        case .trace, .debug: .debug
        case .info, .notice: .info
        case .warning: .default
        case .error: .error
        case .critical: .fault
        }
        // Tappy logs contain no sensitive data; mark public so the text
        // is visible in `log show` without a profile.
        osLogger.log(level: osLevel, "\(text, privacy: .public)")
    }
}
