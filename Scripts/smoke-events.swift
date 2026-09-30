// Synthetic-input injector for Scripts/smoke.sh: posts real CGEvents
// (clicks, keys, holds, scroll) into the session and presses the
// settings Done button through the Accessibility API, so Tappy is
// driven exactly the way a toddler and a parent drive it.
//
// Usage: swift smoke-events.swift <pid>
// Prints the window id (used for the optional screenshot).
// Exit codes: 0 ok · 1 usage/window/button not found · 2 no
// Accessibility trust (CGEventPost would be silently dropped).

import AppKit
import CoreGraphics

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data("[smoke-events] \(message)\n".utf8))
    exit(code)
}

guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]) else {
    fail(1, "usage: swift smoke-events.swift <pid>")
}
guard AXIsProcessTrusted() else {
    fail(2, """
        this process has no Accessibility trust, so posted events would \
        be silently dropped. One-time grant: System Settings → Privacy \
        & Security → Accessibility → add and enable the app running \
        this script (Terminal / IDE), then re-run make smoke.
        """)
}

// Find the app's on-screen window by owner pid; SwiftUI builds it a
// moment after launch, so poll for up to 15 s.
var windowID = CGWindowID(0)
var bounds = CGRect.zero
for _ in 0..<30 {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] ?? []
    if let info = list.first(where: { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) }),
       let b = info[kCGWindowBounds as String] as? [String: CGFloat],
       let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
       w > 1, h > 1 {
        bounds = CGRect(x: x, y: y, width: w, height: h)
        windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
        break
    }
    usleep(500_000)
}
guard bounds.width > 0 else { fail(1, "no on-screen window for pid \(pid) after 15 s") }
print(windowID)
let center = CGPoint(x: bounds.midX, y: bounds.midY)

func click(_ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(80_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func key(_ keyCode: CGKeyCode, flags: CGEventFlags = [], hold: useconds_t = 0) {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(hold)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
}

let pause: useconds_t = 500_000 // spaced beyond the rate limiter (0.08 s)

// 1. Click twice at the same point: the first spawns on the background,
//    the second must be claimed by the entity (react, not re-spawn).
click(center)
usleep(700_000)
click(center)
usleep(pause)

// 2. A plain key bang: "t" (keyCode 17).
key(17)
usleep(pause)

// 3. A scroll flick worth 15 — the spawn threshold in InputCatcherView
//    is a |dy| + |dx| sum of 12.
CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
        wheel1: -15, wheel2: 0, wheel3: 0)?
    .post(tap: .cghidEventTap)
usleep(pause)

// 4. ⌘Q must be swallowed: no quit, no spawn.
key(12, flags: .maskCommand) // "q"
usleep(pause)

// 5. Hold S 2 s: cycles the scene (the hold fires while still down).
key(1, hold: 2_200_000)
usleep(pause)

// 6. Hold P 2 s: opens the parent settings panel.
key(35, hold: 2_200_000)
usleep(800_000)

// 7. With settings open the catcher is inactive: keys pass through.
key(17)
usleep(pause)

// 8. Parent-settings interaction via Accessibility. Buttons are found
//    by AXIdentifier where available (language-independent, unambiguous
//    when the About page stacks on top of the panel), by localized
//    label otherwise.
func findButton(_ element: AXUIElement, depth: Int,
                where match: @escaping (_ title: String, _ desc: String, _ id: String) -> Bool) -> AXUIElement? {
    guard depth < 12 else { return nil }
    var roleRef: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
       (roleRef as? String) == (kAXButtonRole as String) {
        // SwiftUI buttons expose their label via AXDescription, not AXTitle.
        var titleRef: AnyObject?, descRef: AnyObject?, idRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &idRef)
        if match((titleRef as? String) ?? "", (descRef as? String) ?? "",
                 (idRef as? String) ?? "") {
            return element
        }
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return nil }
    return children.lazy.compactMap { findButton($0, depth: depth + 1, where: match) }.first
}

/// Polls the AX tree (SwiftUI builds/updates it asynchronously) and
/// presses the first matching button.
func pressButton(where match: @escaping (String, String, String) -> Bool, _ name: String) {
    let app = AXUIElementCreateApplication(pid)
    for _ in 0..<12 {
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let button = findButton(window, depth: 0, where: match) {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                    return
                }
            }
        }
        usleep(500_000)
    }
    fail(1, "\(name) button not found via Accessibility")
}

let doneTitles: Set<String> = ["Done", "完成", "完了", "완료", "Listo", "Fertig", "Terminé"]

/// Verifies an element is exposed to Accessibility WITHOUT interacting
/// with it (for toggles whose behavior must not flip mid-harness, e.g.
/// the toddler lock). Role-agnostic — SwiftUI Toggles surface as
/// checkBox, not button. Failure exits 1, which fails "synthetic events
/// delivered" in smoke.sh with this message on stderr.
func verifyButton(identifier: String, _ name: String) {
    let app = AXUIElementCreateApplication(pid)
    for _ in 0..<12 {
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if findElement(window, depth: 0,
                               where: { _, _, id in id == identifier }) != nil {
                    return
                }
            }
        }
        usleep(500_000)
    }
    fail(1, "\(name) not found via Accessibility")
}

/// Depth-first search for an AXStaticText whose value contains the
/// needle. Separate from findElement because SwiftUI static texts
/// carry their content in AXValue, not AXTitle/AXDescription.
func findStaticText(_ element: AXUIElement, depth: Int, containing needle: String) -> Bool {
    guard depth < 12 else { return false }
    var roleRef: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
       (roleRef as? String) == (kAXStaticTextRole as String) {
        var valueRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if let value = valueRef as? String, value.contains(needle) { return true }
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return false }
    return children.contains { findStaticText($0, depth: depth + 1, containing: needle) }
}

/// Polls the AX tree for a static text containing the needle; failure
/// exits 1, same contract as verifyButton.
func verifyText(containing needle: String, _ name: String) {
    let app = AXUIElementCreateApplication(pid)
    for _ in 0..<12 {
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows where findStaticText(window, depth: 0, containing: needle) {
                return
            }
        }
        usleep(500_000)
    }
    fail(1, "\(name) not found via Accessibility")
}

/// Depth-first search over ALL elements (any role) matching a predicate
/// on (title, description, identifier).
func findElement(_ element: AXUIElement, depth: Int,
                 where match: @escaping (_ title: String, _ desc: String, _ id: String) -> Bool) -> AXUIElement? {
    guard depth < 12 else { return nil }
    var titleRef: AnyObject?, descRef: AnyObject?, idRef: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
    AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &idRef)
    if match((titleRef as? String) ?? "", (descRef as? String) ?? "",
             (idRef as? String) ?? "") {
        return element
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return nil }
    return children.lazy.compactMap { findElement($0, depth: depth + 1, where: match) }.first
}

/// Optional artifact (TAPPY_SMOKE_CAPTURE=1): window grabs at key
/// moments, for humans to look at. Needs Screen Recording trust;
/// best-effort, never fatal.
func capture(_ path: String) {
    guard ProcessInfo.processInfo.environment["TAPPY_SMOKE_CAPTURE"] == "1" else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-l\(windowID)", path]
    try? task.run()
    task.waitUntilExit()
}

// 7b. The toddler-lock toggle must be exposed to Accessibility (kids-
//     category review navigates by AX too). Found, not pressed: its
//     behavior (fullscreen kiosk) is intentionally inert in smoke's
//     windowed mode, and flipping it would touch the real preference.
verifyButton(identifier: "settings.lock", "toddler-lock toggle")

// 7c. The theme picker must be exposed too — the demo-recording
//     harness switches themes through it.
verifyButton(identifier: "settings.theme", "theme picker")

// 8a. The ⓘ button opens the About page (backstory + licences), then
//     dwell well past the fade animations — assertions come from the
//     log, but a human watching make smoke should actually see it.
pressButton(where: { _, _, id in id == "settings.about" }, "settings info")
usleep(1_500_000)
capture("build/smoke-about.png")

// 8a1. The licence section must render real content, not raw
//      "license.<id>" keys — regression guard for the
//      String.LocalizationValue interpolation bug that turned the
//      lookup key into "license.%@". "MIT License" is the untranslated
//      legal name, present in every localization.
verifyText(containing: "MIT License", "about licence texts")

// 8a2. The source-code link must be exposed to Accessibility. Found,
//      NOT pressed — pressing would open a browser mid-harness.
verifyButton(identifier: "about.sourceLink", "about source link")

// 8b. About's own Done closes it — matched by identifier because the
//     settings panel's Done sits behind and shares its label.
pressButton(where: { _, _, id in id == "about.done" }, "about Done")
usleep(pause)

// 8c. The panel's Done (localized title).
pressButton(where: { title, desc, _ in doneTitles.contains(title) || doneTitles.contains(desc) },
            "settings Done")
usleep(pause)

// 9. Keys work again after the panel closed. This also spawns one more
//    entity, so the frame right here has playfield + name badges.
key(17)
usleep(pause)
capture("build/smoke.png")

// 10. Hold Esc 1.5 s: the app must exit itself, cleanly and promptly.
key(53, hold: 1_700_000)
