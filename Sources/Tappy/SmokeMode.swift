import AppKit
import TappyCore

/// Smoke-test mode, driven by Scripts/smoke.sh through the environment:
/// TAPPY_SMOKE=1 runs the app as a plain windowed app — no kiosk
/// takeover — logging spawns and UI state changes to TAPPY_SMOKE_LOG for
/// the harness to assert on, and self-terminating after TAPPY_SMOKE_SECONDS
/// (default 30) as a safety net: the harness normally exits earlier via
/// the real path (holding Escape). Sounds stay muted via the guard in
/// PlayfieldView.syncSettings. Absent the env var, none of this exists
/// at runtime.
///
/// TAPPY_SMOKE_FULLSCREEN=1 expands the window to cover the main
/// screen's visible frame — used by Scripts/record-demo.sh so the
/// App Review video shows the app filling the display without the
/// kiosk taking over process switching.
@MainActor
enum SmokeMode {
    static let isActive = ProcessInfo.processInfo.environment["TAPPY_SMOKE"] == "1"
    static let wantsFullscreen = ProcessInfo.processInfo.environment["TAPPY_SMOKE_FULLSCREEN"] == "1"

    nonisolated private static let logPath = ProcessInfo.processInfo.environment["TAPPY_SMOKE_LOG"]

    /// Called from TappyApp.init (main thread), before any window exists.
    static func install() {
        guard isActive else { return }
        // Which localization the bundle actually resolved — smoke.sh
        // asserts this against the requested TAPPY_SMOKE_LANG.
        log("lang \(AppLanguage.current.bundleCode)")
        GameState.onSpawn = { source, id in log("spawn \(source) \(id)") }
        let raw = ProcessInfo.processInfo.environment["TAPPY_SMOKE_SECONDS"]
        let seconds = raw.flatMap(TimeInterval.init) ?? 30
        // NSApp is still nil inside App.init — go through .shared, which
        // instantiates the application. ObjC performSelector: schedules
        // on the main run loop without a Swift closure crossing
        // isolation (same reasoning as the exit path in PlayfieldView).
        NSApplication.shared.perform(#selector(NSApplication.terminate),
                                     with: nil, afterDelay: seconds)
    }

    /// Append one line to the harness log. Called only from the main
    /// thread (spawn hook, SwiftUI onChange); unbuffered per-line writes
    /// so the script never reads a half line.
    nonisolated static func log(_ line: String) {
        guard let path = logPath, !path.isEmpty,
              let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data("\(line)\n".utf8))
    }
}
