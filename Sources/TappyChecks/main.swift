import AppKit
import Foundation
import TappyCore

// Assertion-based checks for TappyCore, runnable with plain Command Line
// Tools (no Xcode / XCTest needed): `swift run TappyChecks`.

Log.bootstrap()

var failures = 0

@MainActor
func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS  \(label)")
    } else {
        print("FAIL  \(label)")
        failures += 1
    }
}

/// Fresh scratch directory under Temporary — checks never touch the
/// user's real packs, caches, or defaults.
func scratchDir() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "tappy-checks-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// Zips a pack directory with ditto, the same archive form the
/// subscription download ships.
func makeZip(_ packDir: URL, to zip: URL) throws {
    let make = Process()
    make.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    make.arguments = ["-c", "-k", packDir.path(percentEncoded: false),
                      zip.path(percentEncoded: false)]
    try make.run()
    make.waitUntilExit()
}

// The audio and state paths are main-thread confined by design;
// run the checks on the main thread.
@MainActor
func runChecks() {
    SoundPlayer.isEnabled = false
    Speaker.shared.isEnabled = false

    // Spawn places an entity at the requested position.
    do {
        let state = GameState()
        let entity = state.spawn(at: CGPoint(x: 0.5, y: 0.5))
        check(entity != nil, "spawn returns an entity")
        check(state.entities.count == 1, "spawn appends one entity")
        check(state.entities.first?.position == CGPoint(x: 0.5, y: 0.5),
              "spawn keeps requested position")
    }

    // Rate limiting: calls inside minSpawnInterval are dropped.
    do {
        let state = GameState()
        state.minSpawnInterval = 1.0
        let start = Date()
        check(state.spawn(now: start) != nil, "first spawn allowed")
        check(state.spawn(now: start.addingTimeInterval(0.5)) == nil,
              "spawn inside interval is rate-limited")
        check(state.spawn(now: start.addingTimeInterval(1.1)) != nil,
              "spawn after interval allowed")
        check(state.entities.count == 2, "only two entities kept")
    }

    // Cap: oldest entities are dropped beyond maxEntities.
    do {
        let state = GameState()
        state.maxEntities = 3
        state.minSpawnInterval = 0
        for _ in 0..<10 { state.spawn() }
        check(state.entities.count == 3, "entity count capped at maxEntities")
    }

    // Custom sound pack lookup.
    do {
        let dir = scratchDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        check(SoundPlayer.customSoundURL(for: "cat", in: dir) == nil,
              "no custom sound found in empty directory")

        let catFile = dir.appending(path: "cat.wav")
        FileManager.default.createFile(atPath: catFile.path(percentEncoded: false), contents: Data())
        check(SoundPlayer.customSoundURL(for: "cat", in: dir) == catFile,
              "custom sound found for matching entity")
        check(SoundPlayer.customSoundURL(for: "dog", in: dir) == nil,
              "no custom sound for other entities")

        let defaultFile = dir.appending(path: "default.mp3")
        FileManager.default.createFile(atPath: defaultFile.path(percentEncoded: false), contents: Data())
        check(SoundPlayer.customSoundURL(for: "dog", in: dir) == defaultFile,
              "default file used as catch-all")
        check(SoundPlayer.customSoundURL(for: "cat", in: dir) == catFile,
              "entity-specific file wins over default")
    }

    // Parade mode activates at the threshold.
    do {
        let state = GameState()
        state.paradeThreshold = 3
        state.minSpawnInterval = 0
        check(!state.paradeActive, "parade inactive below threshold")
        state.spawn()
        state.spawn()
        check(!state.paradeActive, "parade inactive one below threshold")
        state.spawn()
        check(state.paradeActive, "parade active at threshold")
        if let first = state.entities.first {
            state.remove(first.id)
            check(!state.paradeActive, "parade deactivates below threshold")
        }
    }

    // Parade slots are stable: removing one entity never changes the
    // paradePhase of the others.
    do {
        let state = GameState()
        state.minSpawnInterval = 0
        for _ in 0..<5 { state.spawn() }
        let phases = state.entities.map(\.paradePhase)
        check(Set(phases).count == phases.count, "parade phases are distinct")
        if let first = state.entities.first {
            state.remove(first.id)
            check(state.entities.map(\.paradePhase) == Array(phases.dropFirst()),
                  "parade phases stable after removal")
        }
    }

    // Pack artwork rasterizes for every entity in the catalog.
    for entity in PackCatalog.shared.entities {
        if let image = EntityArt.image(for: entity) {
            check(image.size.width > 0, "vector artwork renders: \(entity.id)")
        } else {
            check(false, "vector artwork loads: \(entity.id)")
        }
    }

    // Pack sounds exist and load for every entity.
    for entity in PackCatalog.shared.entities {
        guard let url = entity.soundURL else {
            check(false, "pack sound exists: \(entity.id)")
            continue
        }
        let sound = NSSound(contentsOf: url, byReference: true)
        check(sound != nil, "pack sound loads: \(entity.id)")
    }

    // Scenes: every scene has a pack accent sound and a display name.
    for scene in PackCatalog.shared.scenes {
        check(scene.accentSoundURL != nil, "scene accent exists: \(scene.id)")
        check(!scene.displayName(for: .current).isEmpty, "scene has display name: \(scene.id)")
    }

    // Parade participants are capped: extra entities keep roaming.
    do {
        let state = GameState()
        state.minSpawnInterval = 0
        state.paradeThreshold = 3
        state.paradeMaxParticipants = 4
        for _ in 0..<6 { state.spawn() }
        check(state.paradeActive, "parade active with many entities")
        check(state.paradeParticipants.count == 4, "parade participants capped")
        check(state.paradeParticipants.map(\.id) == state.entities.prefix(4).map(\.id),
              "parade takes oldest entities first")
        check(!state.isParadeParticipant(state.entities[5].id),
              "extra entity not in parade")
    }

    // Size boost (scroll wheel) scales the spawned entity, clamped.
    do {
        let state = GameState()
        state.minSpawnInterval = 0
        let boosted = state.spawn(sizeBoost: 1.5)!
        let clamped = state.spawn(sizeBoost: 99)!
        check((25...405).contains(boosted.size), "boosted size within range")
        check(clamped.size <= 405, "size boost clamped")
    }

    // Real-world proportions: bear > rabbit > ant, deterministic via the
    // per-entity scale factor.
    do {
        check(PackCatalog.shared.entity("bear")!.sizeScale > PackCatalog.shared.entity("rabbit")!.sizeScale,
              "bear bigger than rabbit")
        check(PackCatalog.shared.entity("rabbit")!.sizeScale > PackCatalog.shared.entity("ant")!.sizeScale,
              "rabbit bigger than ant")
        check(PackCatalog.shared.entity("dog")!.sizeScale > PackCatalog.shared.entity("cat")!.sizeScale,
              "dog bigger than cat")
    }

    // Settings: defaults and persistence round-trip.
    do {
        let suite = UserDefaults(suiteName: "tappy-checks-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: suite)
        check(settings.scene.id == "mushroomForest", "default scene is mushroom forest")
        check(settings.soundEnabled, "sound on by default")
        check(!settings.speechEnabled, "speech naming off by default")
        check(settings.showNames, "name labels on by default")
        check(settings.toddlerLock, "toddler lock on by default")

        settings.scene = PackCatalog.shared.scene("mistyMeadow")!
        let reloaded = SettingsStore(defaults: suite)
        check(reloaded.scene.id == "mistyMeadow", "scene persists across reload")
        settings.showNames = false
        check(!SettingsStore(defaults: suite).showNames, "name-label preference persists")
        settings.toddlerLock = false
        check(!SettingsStore(defaults: suite).toddlerLock, "toddler-lock preference persists")
    }

    // i18n: localized names resolve (never raw keys).
    do {
        for entity in PackCatalog.shared.entities {
            for language in AppLanguage.allCases {
                check(!entity.name(for: language).isEmpty,
                      "pack entity name resolves: \(entity.id) \(language.bundleCode)")
            }
        }
        for scene in PackCatalog.shared.scenes {
            for language in AppLanguage.allCases {
                check(!scene.displayName(for: language).isEmpty,
                      "pack scene name resolves: \(scene.id) \(language.bundleCode)")
            }
        }
        check(L10n.settingsTitle != "settings.title" && !L10n.settingsTitle.isEmpty,
              "localized settings title resolves")
    }

    // Licence texts ship in the bundle for in-app browsing — the app's
    // own MIT text plus the third-party notices.
    do {
        for resource in ["mit", "cc-by-4.0", "cc0-1.0", "zlib"] {
            let url = TappyResources.bundle.url(
                forResource: resource, withExtension: "txt", subdirectory: "Licenses")
            check(url != nil, "licence text bundled: \(resource)")
        }
    }

    // Every UI string ships translated (non-empty) in all seven
    // localizations — the smoke harness runs one language per pass, so
    // per-language completeness is asserted here instead.
    do {
        let required = [
            "hint.controls", "hint.explore", "parade.announcement",
            "settings.title", "settings.theme", "settings.sound",
            "settings.speech", "settings.showNames", "settings.lock",
            "settings.aboutButton", "settings.about", "settings.credits",
            "settings.done", "settings.quit",
            "about.title", "about.story", "about.sourceCode",
            "about.ackTitle", "about.legalNote",
            "license.tappy", "license.twemoji", "license.sounds",
            "license.swiftdraw",
        ]
        for language in AppLanguage.allCases {
            let path = TappyResources.bundle.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: language.bundleCode)
            let dict = path.flatMap { NSDictionary(contentsOfFile: $0) } as? [String: String]
            check(dict != nil, "strings table loads: \(language.bundleCode)")
            for key in required {
                check(dict?[key]?.isEmpty == false,
                      "string ships: \(key) \(language.bundleCode)")
            }
        }
    }

    // Resource packs: built-in catalog loads; a user pack overrides
    // entries by id and adds brand-new generic scenes without code.
    do {
        let catalog = PackCatalog.shared
        check(catalog.entities(forPack: "default").count == 10,
              "default pack ships 10 entities")
        check(catalog.entities(forPack: "vehicles").count == 10,
              "vehicles pack ships 10 entities")
        check(catalog.scenes(forPack: "default").count == 2,
              "default pack ships 2 scenes")
        check(catalog.scenes(forPack: "vehicles").count == 2,
              "vehicles pack ships 2 scenes")
        check(catalog.entity("cat")?.name(for: .chinese) == "小猫", "pack name lookup by language")
        check(catalog.entity("cat")?.name(for: .german) == "Miezekatze", "german name from pack")

        let dir = scratchDir()
        let packDir = dir.appending(path: "Extra.tappypack", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let manifest = """
        {
          "format": 1, "id": "extra",
          "entities": [
            {"id": "cat", "names": {"en": "Override Cat"}},
            {"id": "panda", "sizeScale": 1.4, "names": {"en": "Panda"}}
          ],
          "scenes": [
            {"id": "candySky", "names": {"en": "Candy Sky"},
             "scene": {"gradient": ["#FF0000", "#00FF00"],
                       "ground": {"color": "#0000FF", "height": 0.2},
                       "decorations": [],
                       "particles": {"kind": "fireflies", "count": 3}},
             "parade": {"style": "graze", "speed": 0.05, "laneY": [0.75], "amplitude": 8}}
          ]
        }
        """
        try? manifest.write(to: packDir.appending(path: "pack.json"),
                            atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let merged = PackCatalog(userPacksDirectory: dir)
        check(merged.entities.count == PackCatalog.shared.entities.count + 1,
              "user pack adds an entity")
        check(merged.entity("cat")?.name(for: .english) == "Override Cat",
              "user pack overrides built-in by id")
        check(merged.entity("cat")?.packID == "extra", "override carries its pack id")
        check(merged.entity("panda")?.sizeScale == 1.4, "user entity loads with attributes")
        if case .generic(let spec)? = merged.scene("candySky")?.renderer {
            check(spec.gradient == ["#FF0000", "#00FF00"], "generic scene spec decodes")
            check(spec.particles?.count == 3, "particle spec decodes")
        } else {
            check(false, "generic scene renderer selected")
        }
        check(merged.scene("candySky")?.parade.style == .graze, "parade spec decodes")
        check(merged.scene("candySky")?.accentSoundURL == nil, "missing accent tolerated")
    }

    // Archive packs: a zipped .tappypack extracts and loads identically
    // (and the archive wrapping contents in one folder is tolerated).
    do {
        // Extract into a scratch cache so checks never touch the
        // real ~/Library/Caches/Tappy.
        PackCatalog.cacheDirectory = scratchDir()
        let dir = scratchDir()
        let packDir = dir.appending(path: "Zippy.tappypack", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let manifest = """
        {"format": 1, "id": "zippy",
         "entities": [{"id": "panda", "names": {"en": "Zipped Panda"}}],
         "scenes": []}
        """
        try? manifest.write(to: packDir.appending(path: "pack.json"),
                            atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let zip = dir.appending(path: "zippy.zip")
        try? makeZip(packDir, to: zip)
        try? FileManager.default.removeItem(at: packDir)
        try? FileManager.default.moveItem(at: zip,
                                          to: dir.appending(path: "Zippy.tappypack"))

        let merged = PackCatalog(userPacksDirectory: dir)
        check(merged.entity("panda")?.name(for: .english) == "Zipped Panda",
              "archived pack extracts and loads")
    }

    // Theme selection: only the active pack spawns, matches and offers
    // scenes; the choice persists; removing the pack falls back.
    do {
        let dir = scratchDir()
        let packDir = dir.appending(path: "Extra.tappypack", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let manifest = """
        {"format": 1, "id": "extra",
         "entities": [{"id": "truck", "names": {"en": "Truck"}}],
         "scenes": [{"id": "site", "names": {"en": "Work Site"}}]}
        """
        try? manifest.write(to: packDir.appending(path: "pack.json"),
                            atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let catalog = PackCatalog(userPacksDirectory: dir)
        check(catalog.packIDs == ["default", "vehicles", "extra"], "pack ids in load order")
        let suite = UserDefaults(suiteName: "tappy-checks-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: suite, catalog: catalog)
        check(settings.activePackID == "default", "active pack defaults to built-in")
        check(settings.activeEntities.count == 10, "default theme has 10 entities")

        settings.activePackID = "extra"
        check(settings.activeEntities.map(\.id) == ["truck"], "active theme restricts entities")
        check(settings.activeScenes.map(\.id) == ["site"], "active theme restricts scenes")
        check(settings.scene.id == "site", "scene falls back into the new theme")

        let reloaded = SettingsStore(defaults: suite, catalog: catalog)
        check(reloaded.activePackID == "extra", "theme choice persists")
        let builtinOnly = SettingsStore(defaults: suite,
                                        catalog: PackCatalog(userPacksDirectory: nil))
        check(builtinOnly.activePackID == "default", "missing pack falls back to built-in")

        let state = GameState(catalog: catalog)
        state.activePackID = "extra"
        check(state.spawn()?.definition.packID == "extra", "random spawn draws from active pack")
    }

    // Theme switch clears the playfield: old-theme entities must not
    // linger after the new theme takes over.
    do {
        let state = GameState()
        state.minSpawnInterval = 0
        for _ in 0..<5 { state.spawn() }
        check(state.entities.count == 5, "entities on screen before switch")
        state.activePackID = "vehicles"
        check(state.entities.isEmpty, "theme switch clears the playfield")
        check(state.spawn()?.definition.packID == "vehicles",
              "spawn pool follows the new theme after clearing")
    }

    // Pack display names: localized, falling back through en/any/id.
    do {
        let catalog = PackCatalog.shared
        check(catalog.displayName(forPack: "vehicles", language: .chinese) == "车车",
              "pack display name localized")
        check(catalog.displayName(forPack: "vehicles", language: .english) == "Vehicles",
              "pack display name in English")
        check(catalog.displayName(forPack: "missing", language: .english) == "missing",
              "unknown pack falls back to its id")

        // A pack without names presents as its id.
        let dir = scratchDir()
        let packDir = dir.appending(path: "Plain.tappypack", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        try? "{\"format\":1,\"id\":\"plain\"}".write(
            to: packDir.appending(path: "pack.json"), atomically: true, encoding: .utf8)
        let merged = PackCatalog(userPacksDirectory: dir)
        check(merged.displayName(forPack: "plain", language: .chinese) == "plain",
              "nameless pack falls back to id")
    }

    // A pack with a corrupt manifest is skipped; the others still load.
    do {
        let dir = scratchDir()
        for (name, contents) in [("Broken.tappypack", "{not json"),
                                 ("Good.tappypack", "{\"format\":1,\"id\":\"good\"}")] {
            let packDir = dir.appending(path: name, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
            try? contents.write(to: packDir.appending(path: "pack.json"),
                                atomically: true, encoding: .utf8)
        }
        let merged = PackCatalog(userPacksDirectory: dir)
        check(!merged.packIDs.contains("broken"), "corrupt pack skipped")
        check(merged.packIDs.contains("good"), "sibling pack still loads")
    }

    // Re-zipping an archive pack with new content re-extracts it (the
    // cache key is size + mtime); the stale cached contents are not used.
    do {
        PackCatalog.cacheDirectory = scratchDir()
        let dir = scratchDir()
        let packDir = dir.appending(path: "Fresh.tappypack", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)

        func zipCurrentPack(named name: String, entityName: String) throws {
            // The previous round replaced the pack directory with the
            // archive itself; rebuild it before writing the manifest.
            try? FileManager.default.removeItem(at: packDir)
            try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
            let manifest = "{\"format\":1,\"id\":\"fresh\",\"entities\":[" +
                "{\"id\":\"panda\",\"names\":{\"en\":\"\(entityName)\"}}]}"
            try manifest.write(to: packDir.appending(path: "pack.json"),
                               atomically: true, encoding: .utf8)
            let zip = dir.appending(path: "fresh.zip")
            try makeZip(packDir, to: zip)
            try? FileManager.default.removeItem(at: dir.appending(path: name))
            try FileManager.default.moveItem(at: zip, to: dir.appending(path: name))
            // Ensure a distinct mtime so the cache key changes.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: dir.appending(path: name).path)
            Thread.sleep(forTimeInterval: 1.1)
        }

        try? zipCurrentPack(named: "Fresh.tappypack", entityName: "Panda v1")
        check(PackCatalog(userPacksDirectory: dir).entity("panda")?.name(for: .english) == "Panda v1",
              "archive extracts once")

        try? zipCurrentPack(named: "Fresh.tappypack", entityName: "Panda v2")
        check(PackCatalog(userPacksDirectory: dir).entity("panda")?.name(for: .english) == "Panda v2",
              "updated archive re-extracts")
    }

    // Removal.
    do {
        let state = GameState()
        if let entity = state.spawn() {
            state.remove(entity.id)
            check(state.entities.isEmpty, "remove drops the entity")
        } else {
            check(false, "spawn returned nil")
        }
    }

    // InputCatcherView: monitor-based event routing. NSEvent factory
    // methods work without a window, so the logic is testable headless.
    func keyEvent(_ type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: "x", charactersIgnoringModifiers: "x",
                         isARepeat: false, keyCode: keyCode)!
    }
    do {
        let view = InputCatcherView()
        // Regression guards: the first-responder/focus-ring path crashed
        // the app (async AppKit focus work vs MainActor checks).
        check(view.acceptsFirstResponder == false, "catcher never first responder")
        check(view.focusRingType == .none, "catcher draws no focus ring")

        var keys = 0
        view.onKey = { keys += 1 }
        check(view.handle(keyEvent(.keyDown, keyCode: 0)) == nil, "key bang consumed")
        check(keys == 1, "key bang fires onKey")

        // ⌘Q is just a keyDown with command — swallowed like any key.
        check(view.handle(keyEvent(.keyDown, keyCode: 12, flags: .command)) == nil,
              "Cmd+Q swallowed")

        // Parent gate: Escape must be held; a quick tap does not exit.
        var exited = 0
        view.escapeHoldDuration = 0.15
        view.onExit = { exited += 1 }
        view.handle(keyEvent(.keyDown, keyCode: 53))
        view.handle(keyEvent(.keyDown, keyCode: 53)) // key repeat
        view.handle(keyEvent(.keyUp, keyCode: 53))   // released early
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(exited == 0, "short Esc tap does not exit")
        view.handle(keyEvent(.keyDown, keyCode: 53))
        view.handle(keyEvent(.keyDown, keyCode: 53)) // repeat ignored
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(exited == 1, "Esc hold exits exactly once")

        // Mouse clicks are deliberately not captured by the catcher:
        // SwiftUI gestures handle them so entity views can claim their
        // own taps — covered end-to-end by make smoke.

        // Scroll: tiny deltas ignored, real flicks spawn with a boost.
        var scrolls = 0
        var lastBoost: CGFloat = 0
        view.onScroll = { _, boost in scrolls += 1; lastBoost = boost }
        func scrollEvent(_ delta: Int32) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                             wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
            return NSEvent(cgEvent: cg)!
        }
        _ = view.handle(scrollEvent(0))
        check(scrolls == 0, "tiny scroll delta ignored")
        _ = view.handle(scrollEvent(30))
        check(scrolls == 1 && lastBoost == 1.5, "scroll flick spawns with clamped boost")

        // Precise devices stream sub-threshold deltas; they accumulate.
        _ = view.handle(scrollEvent(8))
        check(scrolls == 1, "first small scroll accumulates silently")
        _ = view.handle(scrollEvent(8))
        check(scrolls == 2, "accumulated scrolls cross the threshold")

        // Deactivated (settings open): everything passes through untouched.
        view.setActive(false)
        check(view.handle(keyEvent(.keyDown, keyCode: 0)) != nil, "inactive: key passes through")
        check(view.handle(scrollEvent(30)) != nil, "inactive: scroll passes through")
        check(keys == 1 && scrolls == 2, "inactive: handlers not called")
    }
}

// Every fallback icon must resolve to a real SF Symbol, otherwise the
// app would show a blank image.
for entity in PackCatalog.shared.entities {
    let image = NSImage(systemSymbolName: entity.symbol, accessibilityDescription: nil)
    check(image != nil, "SF Symbol exists: \(entity.symbol)")
}

runChecks()

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
