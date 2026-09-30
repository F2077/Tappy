// Synthetic-input driver for Scripts/record-demo.sh: posts real
// CGEvents into the session to demonstrate Tappy's main flow for
// App Store review. Slower than smoke-events.swift — pauses are
// lengthened so viewers can follow.
//
// Usage:
//   swift record-events.swift --find-window <pid>     → prints window id
//   swift record-events.swift --window-bounds <pid>    → prints "x,y,w,h"
//   swift record-events.swift <pid>                    → runs the demo

import AppKit
import CoreGraphics

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data("[record-events] \(message)\n".utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail(1, "usage: swift record-events.swift [--find-window|--window-bounds] <pid>")
}
let findWindowMode = args[1] == "--find-window"
let boundsMode = args[1] == "--window-bounds"
let pidString = (findWindowMode || boundsMode) ? args[2] : args[1]
guard let pid = Int32(pidString) else {
    fail(1, "invalid pid: \(pidString)")
}
guard AXIsProcessTrusted() else {
    fail(2, "no Accessibility trust — enable in System Settings → Privacy & Security → Accessibility")
}

// MARK: - Window lookup

func findWindowID(for pid: Int32) -> (CGWindowID, CGRect)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for info in list where info[kCGWindowOwnerPID as String] as? Int == Int(pid) {
        guard let b = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
              w > 1, h > 1 else { continue }
        return (info[kCGWindowNumber as String] as? CGWindowID ?? 0,
                CGRect(x: x, y: y, width: w, height: h))
    }
    return nil
}

// --find-window mode: poll until the window appears, print its id, exit.
if CommandLine.arguments[1] == "--find-window" {
    for _ in 0..<30 {
        if let (win, _) = findWindowID(for: pid) {
            print(win)
            exit(0)
        }
        usleep(500_000)
    }
    fail(1, "no on-screen window for pid \(pid)")
}

// --window-bounds mode: print "x,y,w,h" for ffmpeg crop.
if boundsMode {
    guard let (_, bounds) = findWindowID(for: pid) else {
        fail(1, "no on-screen window for pid \(pid)")
    }
    print("\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(Int(bounds.width)),\(Int(bounds.height))")
    exit(0)
}

// Demo mode: resolve the window once for click coordinates.
guard let (_, bounds) = findWindowID(for: pid) else {
    fail(1, "no on-screen window for pid \(pid)")
}
let center = CGPoint(x: bounds.midX, y: bounds.midY)

// MARK: - Event helpers

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

// MARK: - Demo script

// Longer pauses than smoke so the recording is legible.
let pause: useconds_t = 1_200_000  // 1.2 s between actions
let longPause: useconds_t = 2_500_000

// 1. Launch pause — let the scene settle for the camera.
usleep(longPause)

// 2. Tap the background: first animal pops up.
click(center)
usleep(longPause)

// 3. Key bang: another animal.
key(17) // "t"
usleep(longPause)

// 4. A few more taps so the playfield feels alive.
click(center)
usleep(pause)
key(17)
usleep(longPause)

// 5. Hold S: switch scene (the hold fires while still down).
key(1, hold: 2_200_000)
usleep(longPause)

// 6. One more spawn in the new scene.
key(17)
usleep(longPause)

// 7. Hold P: open parent settings.
key(35, hold: 2_200_000)
usleep(longPause)

// 8. Close settings with the Done button (AX press, same as smoke).
let doneTitles: Set<String> = ["Done", "完成", "完了", "완료", "Listo", "Fertig", "Terminé"]
let app = AXUIElementCreateApplication(pid)
var donePressed = false
for _ in 0..<12 {
    var windowsRef: AnyObject?
    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for window in windows {
            if let button = findDoneButton(window, depth: 0) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
                donePressed = true
                break
            }
        }
    }
    if donePressed { break }
    usleep(500_000)
}
guard donePressed else { fail(1, "Done button not found") }

usleep(longPause)

// 9. Final spawn to show the app is still alive.
key(17)
usleep(longPause)

// 10. Print the timestamp when we are about to send Esc, so
// record-demo.sh can trim the recording to end right here
// (before the desktop shows through).
print("EXIT_AT=\(Date().timeIntervalSince1970)")

// 11. Hold Esc: clean exit (also ends the smoke-mode timer).
key(53, hold: 1_700_000)

// MARK: - AX helper

func findElementByIdentifier(_ element: AXUIElement, depth: Int, id: String) -> AXUIElement? {
    guard depth < 12 else { return nil }
    var idRef: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &idRef) == .success,
       (idRef as? String) == id {
        return element
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return nil }
    return children.lazy.compactMap { findElementByIdentifier($0, depth: depth + 1, id: id) }.first
}

func findDoneButton(_ element: AXUIElement, depth: Int) -> AXUIElement? {
    guard depth < 12 else { return nil }
    var roleRef: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
       (roleRef as? String) == (kAXButtonRole as String) {
        var titleRef: AnyObject?, descRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let title = (titleRef as? String) ?? ""
        let desc = (descRef as? String) ?? ""
        if doneTitles.contains(title) || doneTitles.contains(desc) {
            return element
        }
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return nil }
    return children.lazy.compactMap { findDoneButton($0, depth: depth + 1) }.first
}
