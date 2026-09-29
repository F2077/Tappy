import AppKit

/// Weak, Sendable handle to the view so the *nonisolated* monitor
/// closure never captures the non-Sendable NSView directly.
private final class ViewBox: @unchecked Sendable {
    weak var view: InputCatcherView?
    init(_ view: InputCatcherView) { self.view = view }
}

/// Raw event sink for keyboard and scroll. Swallows menu key equivalents
/// (⌘Q included) so a baby cannot quit the app; parent controls are
/// long-presses: Escape exits, S cycles the scene, P opens settings.
/// Mouse clicks are deliberately NOT captured: SwiftUI gestures handle
/// them instead, so entity views can claim their own taps (a monitor
/// consuming every mouse down made `EntityView.onTapGesture` dead code —
/// regression found by make smoke, 2026-09-10).
///
/// Events are captured with a local NSEvent monitor instead of the
/// responder chain: this view never becomes first responder and draws no
/// focus ring. The whole handling path is nonisolated on purpose — crash
/// reports (2026-09-06) show compiler-inserted MainActor executor checks
/// intermittently faulting on this toolchain whenever ObjC/AppKit calls
/// into Swift (EXC_BAD_ACCESS inside swift_task_isMainExecutorImpl), and
/// Task-hopping out of the monitor callback silently never ran. Local
/// monitors fire synchronously on the main thread during event dispatch,
/// so handling directly is both safe and race-free. All mutable state is
/// nonisolated(unsafe) with main-thread confinement by construction.
public final class InputCatcherView: NSView {
    nonisolated(unsafe) public var onScroll: ((CGPoint, CGFloat) -> Void)?
    nonisolated(unsafe) public var onKey: (() -> Void)?
    nonisolated(unsafe) public var onSceneCycle: (() -> Void)?
    nonisolated(unsafe) public var onSettings: (() -> Void)?
    nonisolated(unsafe) public var onExit: (() -> Void)?

    /// Piled-up scroll magnitude awaiting the spawn threshold.
    nonisolated(unsafe) private var scrollAccumulator: CGFloat = 0

    /// How long parent-gate keys must be held.
    nonisolated(unsafe) public var escapeHoldDuration: TimeInterval = 1.5
    nonisolated(unsafe) public var sceneHoldDuration: TimeInterval = 2.0

    /// Whether events are consumed (play mode) or passed through to the
    /// app (settings panel open — its text fields need keyboard input).
    nonisolated(unsafe) private var activeFlag = true

    /// Held parent-gate keys: keyCode → generation counter. Key repeat is
    /// filtered by tracking whether the key is already held.
    /// Key codes currently down; a scheduled hold fires only while its
    /// key is still here (keyUp removes it, so releases cancel holds).
    nonisolated(unsafe) private var heldKeys: Set<UInt16> = []

    /// Monitor token. nonisolated(unsafe) so deinit can remove it.
    nonisolated(unsafe) private var monitor: Any?

    nonisolated private static let logger = Log.logger("input")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        monitor = Self.installMonitor(ViewBox(self))
        Self.logger.info("event monitor installed=\(self.monitor != nil)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    // Never take keyboard focus; the monitor sees events regardless.
    // nonisolated: pure values, and any executor-check prologue here is
    // exactly what crashed when AppKit introspected the view.
    nonisolated override public var acceptsFirstResponder: Bool { false }

    // Mouse events belong to SwiftUI gestures (background spawn, entity
    // taps). As a full-frame NSView this view would otherwise win AppKit
    // hit-testing and swallow every click before the hosting view's
    // gesture routing ever sees it — so opt out entirely. Keys and
    // scroll arrive via the app-level monitor, not hit-testing.
    nonisolated override public func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Match SwiftUI's top-left origin so tap coordinates need no flipping.
    nonisolated override public var isFlipped: Bool { true }

    /// Play mode consumes events; settings mode passes them through.
    nonisolated public func setActive(_ newValue: Bool) {
        activeFlag = newValue
    }

    /// Installs the local monitor. nonisolated so the handler closure
    /// inherits no actor isolation; it handles events synchronously on
    /// the dispatch thread (always main, per AppKit's guarantee).
    nonisolated private static func installMonitor(_ box: ViewBox) -> Any? {
        NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged, .scrollWheel]
        ) { event in
            guard let view = box.view, view.activeFlag else { return event }
            logger.debug("event type=\(event.type.rawValue) keyCode=\(event.keyCode)")
            return view.handle(event)
        }
    }

    /// Monitor entry point (also directly testable). Returning nil
    /// consumes the event; returning it lets the app continue with it.
    /// Local monitors only ever fire on the main thread — asserted in
    /// debug builds via the main-queue precondition.
    @discardableResult
    nonisolated public func handle(_ event: NSEvent) -> NSEvent? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeFlag else { return event }
        switch event.type {
        case .scrollWheel:
            // Precise devices (Magic Mouse, trackpads) stream many
            // events with sub-pixel deltas; dropping those felt dead.
            // Accumulate until a flick's worth piles up, then spawn —
            // GameState's rate limiter absorbs any flood. Harder flick
            // = bigger one.
            scrollAccumulator += abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX)
            guard scrollAccumulator >= 12 else { return nil }
            let boost = min(scrollAccumulator / 20, 1.5)
            scrollAccumulator = 0
            onScroll?(event.locationInWindow, boost)
            return nil
        case .keyDown:
            // ⌘Q and other shortcuts: swallowed without spawning.
            guard !event.modifierFlags.contains(.command) else { return nil }
            switch event.keyCode {
            case 53: // Escape → exit
                hold(keyCode: 53, duration: escapeHoldDuration) { [weak self] in
                    self?.onExit?()
                }
            case 1: // S → cycle scene
                hold(keyCode: 1, duration: sceneHoldDuration) { [weak self] in
                    self?.onSceneCycle?()
                }
            case 35: // P → settings
                hold(keyCode: 35, duration: sceneHoldDuration) { [weak self] in
                    self?.onSettings?()
                }
            default:
                onKey?()
            }
            return nil // swallow everything, ⌘Q included
        case .keyUp:
            heldKeys.remove(event.keyCode)
            return nil
        case .flagsChanged:
            return nil // ignore modifier-only bangs (Shift/Option/Command/CapsLock)
        default:
            return event
        }
    }

    /// Fires `action` when `keyCode` stays down for `duration`.
    nonisolated private func hold(keyCode: UInt16, duration: TimeInterval,
                                  action: @escaping @Sendable () -> Void) {
        guard !heldKeys.contains(keyCode) else { return } // ignore key repeat
        heldKeys.insert(keyCode)
        let box = ViewBox(self)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard let view = box.view, view.heldKeys.contains(keyCode) else { return }
            view.heldKeys.remove(keyCode)
            action()
        }
    }
}
