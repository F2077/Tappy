import Foundation

/// Observable state of the playfield: which entities are on screen.
///
/// Deliberately NOT @MainActor: every access happens on the main thread
/// by construction (SwiftUI views, the event monitor), and actor
/// isolation would only add compiler-inserted executor checks — which
/// this toolchain intermittently faults on in ObjC-callback contexts
/// (EXC_BAD_ACCESS inside swift_task_isMainExecutorImpl).
@Observable
public final class GameState {
    public private(set) var entities: [EntityInstance] = []

    /// All content comes from loaded resource packs.
    nonisolated private let catalog: PackCatalog

    /// The active scene; drives background, idle actions, accents.
    public var scene: SceneDefinition

    /// The theme being played; random spawns draw only from its pack.
    /// Mirrored from SettingsStore by the view layer. Switching themes
    /// clears the playfield — animals from the old theme must not linger.
    public var activePackID = "default" {
        didSet {
            guard activePackID != oldValue else { return }
            entities.removeAll()
        }
    }

    /// The active pack's entities, derived on demand: spawns are
    /// user-paced (rate-limited to ~12/s), so filtering the small
    /// catalog per spawn costs nothing and keeps the pool in sync with
    /// the theme with no didSet/init bookkeeping.
    private var spawnPool: [EntityDefinition] {
        catalog.entities(forPack: activePackID)
    }

    /// Whether the parent settings panel is showing. Lives here (not in
    /// a SwiftUI @State) so the nonisolated event monitor can toggle it.
    public var showSettings = false

    /// Minimum delay between two spawns, so key-repeat from a held-down
    /// key does not flood the screen.
    public var minSpawnInterval: TimeInterval = 0.08

    /// Maximum number of entities kept on screen; oldest ones are dropped.
    public var maxEntities = 40

    /// Parade mode kicks in once this many entities are on screen: they
    /// line up and march across the bottom of the screen.
    public var paradeThreshold = 6

    /// Maximum number of marchers; any entities beyond this roam free so
    /// the parade never turns into a pile-up.
    public var paradeMaxParticipants = 8

    public var paradeActive: Bool { entities.count >= paradeThreshold }

    /// The entities actually marching (oldest first), capped.
    public var paradeParticipants: [EntityInstance] {
        paradeActive ? Array(entities.prefix(paradeMaxParticipants)) : []
    }

    public func isParadeParticipant(_ id: EntityInstance.ID) -> Bool {
        paradeParticipants.contains { $0.id == id }
    }

    private var lastSpawnAt: Date = .distantPast
    /// Static (lazily initialized on first use): an instance property
    /// would be created during TappyApp's @State default evaluation —
    /// before Log.bootstrap() — and swift-log would pin this logger to
    /// its default stderr backend instead of the unified log.
    nonisolated private static let logger = Log.logger("spawn")
    /// Total spawns so far, used to derive stable parade slots.
    private var spawnCounter = 0

    /// Called on the main thread after each successful spawn: the
    /// trigger source ("tap" / "key" / "scroll") and the entity id.
    /// Smoke mode (Sources/Tappy/SmokeMode.swift) writes these to a file
    /// for Scripts/smoke.sh to assert on; nil in normal play.
    nonisolated(unsafe) public static var onSpawn:
        ((_ source: String, _ entityID: String) -> Void)?

    public init(catalog: PackCatalog = .shared) {
        self.catalog = catalog
        scene = catalog.defaultScene ?? .placeholder
    }

    /// Spawns a random entity from the active theme. `position` is in
    /// normalized coordinates (0...1); pass `nil` for a random spot.
    /// `sizeBoost` scales the entity (fast scroll wheel flicks make
    /// bigger ones). `source` names the trigger ("tap" / "key" /
    /// "scroll") for the smoke log. Returns `nil` when rate-limited.
    @discardableResult
    public func spawn(at position: CGPoint? = nil,
                      sizeBoost: CGFloat = 1, now: Date = Date(),
                      source: String = "key") -> EntityInstance? {
        guard now.timeIntervalSince(lastSpawnAt) >= minSpawnInterval else { return nil }
        lastSpawnAt = now

        guard let entity = spawnPool.randomElement() else { return nil }
        // Golden-ratio spacing distributes parade slots evenly and keeps
        // each entity's slot stable no matter who joins or leaves.
        spawnCounter += 1
        let paradePhase = (Double(spawnCounter) * 0.6180339887498949)
            .truncatingRemainder(dividingBy: 1)
        let instance = EntityInstance(
            definition: entity,
            position: position ?? Self.randomPosition(),
            paradePhase: paradePhase,
            sizeBoost: min(max(sizeBoost, 0.7), 1.8)
        )
        entities.append(instance)
        if entities.count > maxEntities {
            entities.removeFirst(entities.count - maxEntities)
        }
        Self.onSpawn?(source, entity.id)
        if entities.count == paradeThreshold {
            Self.logger.info("parade started", metadata: ["scene": "\(scene.id)"])
            SoundPlayer.playAccent(for: scene)
            Speaker.shared.say(L10n.paradeAnnouncement)
        }

        SoundPlayer.announce(entity)
        return instance
    }

    public func remove(_ id: EntityInstance.ID) {
        entities.removeAll { $0.id == id }
    }

    /// Random position with a margin so entities never hug the screen edge.
    private static func randomPosition() -> CGPoint {
        CGPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.15...0.85))
    }
}
