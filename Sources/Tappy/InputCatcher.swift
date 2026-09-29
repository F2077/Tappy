import SwiftUI
import AppKit
import TappyCore

/// SwiftUI wrapper around an NSView that captures every mouse click and
/// key press — exactly what a toddler produces.
struct InputCatcher: NSViewRepresentable {
    /// When false (settings panel open), the monitor passes events
    /// through so text fields and buttons work normally.
    var active = true
    /// Scroll wheel: location + how hard the wheel was flicked.
    var onScroll: (CGPoint, CGFloat) -> Void
    var onKey: () -> Void
    var onSceneCycle: () -> Void
    var onSettings: () -> Void
    var onExit: () -> Void

    func makeNSView(context: Context) -> InputCatcherView {
        InputCatcherView()
    }

    func updateNSView(_ nsView: InputCatcherView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onKey = onKey
        nsView.onSceneCycle = onSceneCycle
        nsView.onSettings = onSettings
        nsView.onExit = onExit
        nsView.setActive(active)
    }
}
