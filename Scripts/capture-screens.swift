// Staged App Store screenshot capture: drives the windowed app with
// real CGEvents through four scenes (playfield with name badges,
// second scene, parent settings, About page) and grabs the window at
// each stage. Usage: swift capture-screens.swift <pid> <outdir>
// The wrapper (capture-screens.sh) normalizes resolutions afterwards.

import AppKit
import CoreGraphics

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data("[capture] \(message)\n".utf8))
    exit(code)
}

guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[1]) else {
    fail(1, "usage: swift capture-screens.swift <pid> <outdir>")
}
let outDir = CommandLine.arguments[2]
guard AXIsProcessTrusted() else {
    fail(2, "no Accessibility trust — see Scripts/smoke.sh header")
}

// Window poll (SwiftUI builds it a moment after launch).
func windowInfo(for pid: Int32) -> (id: CGWindowID, bounds: CGRect)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] ?? []
    guard let info = list.first(where: { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) }),
          let b = info[kCGWindowBounds as String] as? [String: CGFloat],
          let w = b["Width"], let h = b["Height"], w > 1, h > 1,
          let x = b["X"], let y = b["Y"],
          let n = info[kCGWindowNumber as String] as? Int else { return nil }
    return (CGWindowID(n), CGRect(x: x, y: y, width: w, height: h))
}

var windowID = CGWindowID(0)
var bounds = CGRect.zero
for _ in 0..<30 {
    if let info = windowInfo(for: pid) {
        windowID = info.id
        bounds = info.bounds
        break
    }
    usleep(500_000)
}
guard bounds.width > 0 else { fail(1, "no on-screen window for pid \(pid)") }

// Launch race: the WindowGroup restores its saved frame first and the
// app re-pins it to TAPPY_WINDOW right after — wait for that size.
if let raw = ProcessInfo.processInfo.environment["TAPPY_WINDOW"] {
    let parts = raw.split(separator: "x").compactMap { Double($0) }
    if parts.count == 2 {
        for _ in 0..<20 {
            if abs(bounds.width - parts[0]) < 2, abs(bounds.height - parts[1]) < 2 { break }
            usleep(300_000)
            bounds = windowInfo(for: pid)?.bounds ?? bounds
        }
        guard abs(bounds.width - parts[0]) < 2, abs(bounds.height - parts[1]) < 2 else {
            fail(1, "window never reached \(raw): got \(bounds.width)x\(bounds.height)")
        }
    }
}

func click(_ fx: CGFloat, _ fy: CGFloat) {
    let point = CGPoint(x: bounds.minX + bounds.width * fx,
                        y: bounds.minY + bounds.height * fy)
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

/// Window-scoped grab at a staged moment (badges live ~2 s, entities
/// ~4 s — captures come right after the spawns that dress the frame).
func capture(_ name: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l\(windowID)", "\(outDir)/\(name).png"]
    try? task.run()
    task.waitUntilExit()
}

// Depth-first AX element finder (same approach as smoke-events:
// SwiftUI Toggles surface as checkBox, Buttons carry their label in
// AXDescription — so match on all three attributes).
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

func pressButton(where match: @escaping (_ title: String, _ desc: String, _ id: String) -> Bool,
                 _ name: String) {
    let app = AXUIElementCreateApplication(pid)
    for _ in 0..<12 {
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let button = findElement(window, depth: 0, where: match) {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                    return
                }
            }
        }
        usleep(500_000)
    }
    fail(1, "\(name) button not found")
}

let doneTitles: Set<String> = ["Done", "完成", "完了", "완료", "Listo", "Fertig", "Terminé"]

// Stage 01 — playfield: three spawns across the frame, name badges
// still up when the grab lands (~1.1 s after the first spawn).
click(0.30, 0.62)
usleep(300_000)
click(0.72, 0.40)
usleep(300_000)
key(17) // "t" → random-spot spawn
usleep(500_000)
capture("01-playfield")

// Stage 02 — the other scene, freshly dressed.
key(1, hold: 2_200_000) // hold S: cycle scene
usleep(600_000)          // scene fade
click(0.40, 0.58)
usleep(300_000)
key(17)
usleep(500_000)
capture("02-second-scene")

// Stage 03 — parent settings (the toddler-lock toggle row included).
key(35, hold: 2_200_000) // hold P
usleep(900_000)
capture("03-settings")

// Stage 04 — About page: backstory above the licence texts.
pressButton(where: { _, _, id in id == "settings.about" }, "settings info")
usleep(1_300_000)
capture("04-about")

// Leave quietly: About → settings → playfield → hold-Esc exit.
pressButton(where: { _, _, id in id == "about.done" }, "about Done")
usleep(400_000)
pressButton(where: { title, desc, _ in doneTitles.contains(title) || doneTitles.contains(desc) },
            "settings Done")
usleep(400_000)
key(53, hold: 1_700_000)
