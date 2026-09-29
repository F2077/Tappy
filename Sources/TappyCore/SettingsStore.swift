import Foundation

/// Parent-facing settings, persisted in UserDefaults.
///
/// Content (entities, scenes) comes from the pack catalog; the store
/// only tracks which theme is active plus the audio toggles.
@Observable
public final class SettingsStore {
    nonisolated(unsafe) public static let shared = SettingsStore()

    public var scene: SceneDefinition {
        didSet { defaults.set(scene.id, forKey: Keys.scene) }
    }
    public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.sound) }
    }
    /// Speech synthesis (saying the entity's name out loud); needs no
    /// permission and is unrelated to microphone input.
    public var speechEnabled: Bool {
        didSet { defaults.set(speechEnabled, forKey: Keys.speech) }
    }
    /// Name badges under freshly spawned entities. On by default: the
    /// badge is a silent visual cue that echoes what the parent says,
    /// while synthesized speech stays opt-in — the app supports the
    /// parent's narration, it does not replace it.
    public var showNames: Bool {
        didSet { defaults.set(showNames, forKey: Keys.showNames) }
    }
    /// Baby-safe kiosk: full screen, hidden Dock and menu bar, no ⌘Tab,
    /// so a toddler banging the keyboard cannot leave the app. On by
    /// default — the safety net most parents never open settings for —
    /// and applied/removed live when toggled.
    public var toddlerLock: Bool {
        didSet { defaults.set(toddlerLock, forKey: Keys.toddlerLock) }
    }
    /// The theme being played: only its entities spawn and only its
    /// scenes are offered. Persisted by pack id; switching re-points the
    /// scene at the new pack's first scene.
    public var activePackID: String {
        didSet {
            defaults.set(activePackID, forKey: Keys.activePack)
            if !activeScenes.contains(scene), let first = activeScenes.first {
                scene = first
            }
        }
    }
    /// Content of the active theme.
    public var activeEntities: [EntityDefinition] {
        catalog.entities(forPack: activePackID)
    }
    public var activeScenes: [SceneDefinition] {
        catalog.scenes(forPack: activePackID)
    }

    private enum Keys {
        static let scene = "tappy.scene"
        static let sound = "tappy.soundEnabled"
        static let speech = "tappy.speechEnabled"
        static let showNames = "tappy.showNames"
        static let toddlerLock = "tappy.toddlerLock"
        static let activePack = "tappy.activePack"
    }

    private let defaults: UserDefaults
    private let catalog: PackCatalog

    public init(
        defaults: UserDefaults = .standard,
        catalog: PackCatalog = .shared
    ) {
        self.defaults = defaults
        self.catalog = catalog
        // Resolved through locals only: `self` is not fully initialized
        // until every stored property is set.
        let storedPack = defaults.string(forKey: Keys.activePack)
        let packID = storedPack.flatMap { id in
            catalog.packIDs.contains(id) ? id : nil
        } ?? catalog.packIDs.first ?? "default"
        let packScenes = catalog.scenes(forPack: packID)
        activePackID = packID
        let storedScene = defaults.string(forKey: Keys.scene).flatMap(catalog.scene)
        scene = storedScene.flatMap { s in
            packScenes.contains(s) ? s : nil
        } ?? packScenes.first
            ?? catalog.defaultScene
            ?? .placeholder
        // Bool defaults: sound on, speech synthesis off, name badges on,
        // toddler lock on.
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        speechEnabled = defaults.object(forKey: Keys.speech) as? Bool ?? false
        showNames = defaults.object(forKey: Keys.showNames) as? Bool ?? true
        toddlerLock = defaults.object(forKey: Keys.toddlerLock) as? Bool ?? true
    }
}
