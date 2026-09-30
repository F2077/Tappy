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
    fail(1, "usage: swift record-events.swift [--find-window|--window-bounds|--double-click x,y] <pid>")
}

// --double-click x,y mode: two rapid clicks at the point (used to
// launch the desktop alias on camera), then exit. Handled before the
// pid parse — this mode takes coordinates instead of a pid.
if args[1] == "--double-click" {
    guard AXIsProcessTrusted() else {
        fail(2, "no Accessibility trust — enable in System Settings → Privacy & Security → Accessibility")
    }
    guard args.count >= 3 else { fail(1, "usage: --double-click x,y") }
    let parts = args[2].split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else { fail(1, "invalid coordinates: \(args[2])") }
    let point = CGPoint(x: parts[0], y: parts[1])
    click(point)
    usleep(120_000)
    click(point)
    exit(0)
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

// Pixel-unit scroll wheel. Negative dy reveals content below the fold.
func scroll(_ point: CGPoint, dy: Int32) {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                        wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)
    event?.location = point
    event?.post(tap: .cghidEventTap)
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

// 8. Switch the theme via the Theme popup: press it, then pick the
// second menu item — by index, not label, so it is language-independent.
// The playfield clears to the new theme behind the panel.
let app = AXUIElementCreateApplication(pid)
var themePopupPressed = false
for _ in 0..<12 {
    var windowsRef: AnyObject?
    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for window in windows {
            if let popup = findElementByIdentifier(window, depth: 0, id: "settings.theme") {
                AXUIElementPerformAction(popup, kAXPressAction as CFString)
                themePopupPressed = true
                break
            }
        }
    }
    if themePopupPressed { break }
    usleep(500_000)
}
if themePopupPressed {
    // Hold the open menu on camera — the reviewer should see both
    // packs listed before the selection lands.
    usleep(1_800_000)
    var picked = false
    for _ in 0..<12 {
        let items = findMenuItems(app, depth: 0)
        if items.count > 1 {
            // Pick the item WITHOUT the checkmark — the persisted
            // theme could make either pack current, so "the other
            // one" is the actual switch.
            let target = items.first(where: { !isMenuItemChecked($0) }) ?? items[1]
            // Menu items usually answer Press; fall back to Pick.
            if AXUIElementPerformAction(target, kAXPressAction as CFString) != .success {
                AXUIElementPerformAction(target, kAXPickAction as CFString)
            }
            picked = true
            break
        }
        usleep(500_000)
    }
    if !picked {
        key(53)  // tap Esc: never leave a menu hanging for the camera
    }
    usleep(1_800_000)  // menu closes; panel shows the new theme
}

// 9. Open the About page (info button in the title row) and scroll
// down into the open-source licences, so the recording shows the
// attribution section Apple asked about.
var aboutOpened = false
for _ in 0..<12 {
    var windowsRef: AnyObject?
    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for window in windows {
            if let button = findElementByIdentifier(window, depth: 0, id: "settings.about") {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
                aboutOpened = true
                break
            }
        }
    }
    if aboutOpened { break }
    usleep(500_000)
}
if aboutOpened {
    usleep(2_500_000)  // reviewer reads the backstory at the top
    // Scroll down through the licence texts (MIT first, then the
    // third-party works). Negative wheel delta = reveal lower content.
    for _ in 0..<3 {
        scroll(center, dy: -200)
        usleep(1_200_000)
    }
    usleep(1_500_000)  // linger on the MIT licence text
    // Close About via its own Done button ("about.done" — distinct
    // from the settings panel's Done behind it).
    var aboutClosed = false
    for _ in 0..<12 {
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let button = findElementByIdentifier(window, depth: 0, id: "about.done") {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                    aboutClosed = true
                    break
                }
            }
        }
        if aboutClosed { break }
        usleep(500_000)
    }
    usleep(longPause)
}

// 10. Toggle speech on (demonstrate the feature), then off again.
// The toggle is identified by its label text, which is localized
// but unique within the settings panel.
var speechToggled = false
let speechLabels: Set<String> = ["Speak names (synthesized voice)", "语音报名字（合成语音）",
    "名前を読み上げ（合成音声）", "이름 말하기(합성 음성)", "Decir nombres (voz sintetizada)",
    "Dire les noms (voix synthétisée)", "Namen sprechen (synthetisierte Stimme)"]
for _ in 0..<12 {
    var windowsRef: AnyObject?
    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for window in windows {
            if let toggle = findElementByLabel(window, depth: 0, labels: speechLabels) {
                AXUIElementPerformAction(toggle, kAXPressAction as CFString)
                speechToggled = true
                break
            }
        }
    }
    if speechToggled { break }
    usleep(500_000)
}
if speechToggled {
    usleep(1_500_000)  // let the toggle animate
    // Toggle back off (leave the app in its default state).
    for _ in 0..<12 {
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let toggle = findElementByLabel(window, depth: 0, labels: speechLabels) {
                    AXUIElementPerformAction(toggle, kAXPressAction as CFString)
                    break
                }
            }
        }
        usleep(500_000)
    }
    usleep(1_000_000)
}

// 11. Close settings with the Done button (AX press, same as smoke).
let doneTitles: Set<String> = ["Done", "完成", "完了", "완료", "Listo", "Fertig", "Terminé"]
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

// 12. Parade: six or more entities on screen start marching in a lane
// (GameState.paradeThreshold = 6, with an accent sound at the moment
// the parade forms). The theme switch cleared the playfield, so build
// a fresh crowd and let it march for the camera.
for _ in 0..<7 {
    key(17)
    usleep(700_000)
}
usleep(4_500_000)

// 13. Print the timestamp when we are about to send Esc, so
// record-demo.sh can trim the recording to a few seconds after this
// (enough to show the app has fully exited back to the desktop).
print("EXIT_AT=\(Date().timeIntervalSince1970)")

// 14. Hold Esc: clean exit (also ends the smoke-mode timer).
key(53, hold: 1_700_000)

// MARK: - AX helper

func findElementByLabel(_ element: AXUIElement, depth: Int, labels: Set<String>) -> AXUIElement? {
    guard depth < 12 else { return nil }
    var titleRef: AnyObject?, descRef: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
    let title = (titleRef as? String) ?? ""
    let desc = (descRef as? String) ?? ""
    if labels.contains(title) || labels.contains(desc) {
        return element
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return nil }
    return children.lazy.compactMap { findElementByLabel($0, depth: depth + 1, labels: labels) }.first
}

/// Collects AX menu items in DFS order (= display order). Used while a
/// popup menu is open; searched from the app element because the menu
/// may hang off the popup button rather than the window.
func findMenuItems(_ element: AXUIElement, depth: Int) -> [AXUIElement] {
    guard depth < 12 else { return [] }
    var roleRef: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
       (roleRef as? String) == (kAXMenuItemRole as String) {
        return [element]
    }
    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return [] }
    return children.flatMap { findMenuItems($0, depth: depth + 1) }
}

/// A menu item's checkmark lives in AXMenuItemMarkChar (✓ when on,
/// missing/empty when off).
func isMenuItemChecked(_ item: AXUIElement) -> Bool {
    var markRef: AnyObject?
    guard AXUIElementCopyAttributeValue(item, kAXMenuItemMarkCharAttribute as CFString, &markRef) == .success else { return false }
    return (markRef as? String).map { !$0.isEmpty } ?? false
}

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
