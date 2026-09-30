import SwiftUI
import TappyCore
import AppKit

@main
struct TappyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = GameState()

    init() {
        Log.bootstrap()
        Log.logger("app").info("Tappy launched")
        SmokeMode.install()
    }

    var body: some Scene {
        WindowGroup {
            PlayfieldView(state: state)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Self.windowSize.width, height: Self.windowSize.height)
    }

    /// TAPPY_WINDOW=1440x900 pins the windowed (smoke/capture) size so
    /// App Store screenshots come out at exact listing resolutions;
    /// unset means the 1024×768 default.
    private static var windowSize: NSSize {
        if let raw = ProcessInfo.processInfo.environment["TAPPY_WINDOW"] {
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] > 100, parts[1] > 100 {
                return NSSize(width: parts[0], height: parts[1])
            }
        }
        return NSSize(width: 1024, height: 768)
    }
}

/// Puts the app into a baby-safe kiosk: full screen, hidden Dock and menu
/// bar, no ⌘Tab process switching. The only exit is holding Escape
/// (handled by `InputCatcherView`). Applied at launch when the toddler
/// lock is on, and re-applied/removed live from the settings toggle.
@MainActor
enum KioskController {
    private static var applied = false

    /// Applies or removes the kiosk to match the setting.
    static func sync(enabled: Bool) {
        guard !SmokeMode.isActive else { return }
        enabled ? apply() : remove()
    }

    private static func apply() {
        guard !applied else { return }
        applied = true
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]
        // The SwiftUI window may not exist yet; configure it on the next
        // runloop turn.
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.styleMask.remove(.resizable)
            window.isMovable = false
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    private static func remove() {
        guard applied else { return }
        applied = false
        NSApp.presentationOptions = []
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            window.styleMask.insert(.resizable)
            window.isMovable = true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Smoke/capture: pin the frame to TAPPY_WINDOW=WxH — macOS
        // restores the WindowGroup's saved frame after the first
        // launch and would ignore defaultSize forever after.
        if let raw = ProcessInfo.processInfo.environment["TAPPY_WINDOW"] {
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first else { return }
                    window.setFrame(
                        NSRect(origin: window.frame.origin,
                               size: NSSize(width: parts[0], height: parts[1])),
                        display: true)
                }
            }
        }

        // Demo recording: expand to fill the main screen without
        // the kiosk (record-demo.sh needs to keep process switching
        // so it can stop the recorder afterwards).
        if SmokeMode.wantsFullscreen {
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first,
                      let screen = NSScreen.main else { return }
                window.setFrame(screen.visibleFrame, display: true)
            }
        }

        // Smoke mode runs as a plain windowed app — no kiosk takeover,
        // no full screen.
        KioskController.sync(enabled: SettingsStore.shared.toddlerLock)
    }
}
