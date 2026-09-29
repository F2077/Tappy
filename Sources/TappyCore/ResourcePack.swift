import Foundation

/// Resource packs: everything that makes a scene or an entity — artwork,
/// sounds, localized names, parade choreography — lives in
/// a `<name>.tappypack` directory described by one `pack.json`. Adding
/// content never touches code: drop a pack into
/// `~/Library/Application Support/Tappy/Packs/` (user packs override
/// built-in entries with the same id) or ship it in the app bundle.
///
/// This file defines the manifest schema (Codable) and the runtime
/// definitions the rest of the app uses.

// MARK: - Manifest schema (pack.json)

/// Note on decoding: Swift's synthesized Decodable IGNORES property
/// defaults (a missing key throws), so every manifest type with defaults
/// implements init(from:) via decodeIfPresent — a pack may omit any
/// optional field without being rejected wholesale.
struct PackManifest: Decodable {
    var format: Int = 1
    let id: String
    /// Localized pack display name for the theme picker (id if absent).
    var names: [String: String] = [:]
    var entities: [EntityManifest] = []
    var scenes: [SceneManifest] = []

    private enum CodingKeys: String, CodingKey {
        case format, id, names, entities, scenes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
        guard f == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .format, in: c,
                debugDescription: "unsupported pack format \(f)")
        }
        format = f
        id = try c.decode(String.self, forKey: .id)
        names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        entities = try c.decodeIfPresent([EntityManifest].self, forKey: .entities) ?? []
        scenes = try c.decodeIfPresent([SceneManifest].self, forKey: .scenes) ?? []
    }

    struct EntityManifest: Decodable {
        let id: String
        var art: String?
        var sound: String?
        var symbol: String = "questionmark"
        var color: String = "#FF9500"
        var systemSound: String = "Pop"
        var sizeScale: Double = 1.0
        var names: [String: String] = [:]

        private enum CodingKeys: String, CodingKey {
            case id, art, sound, symbol, color, systemSound, sizeScale, names
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            art = try c.decodeIfPresent(String.self, forKey: .art)
            sound = try c.decodeIfPresent(String.self, forKey: .sound)
            symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "questionmark"
            color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#FF9500"
            systemSound = try c.decodeIfPresent(String.self, forKey: .systemSound) ?? "Pop"
            sizeScale = try c.decodeIfPresent(Double.self, forKey: .sizeScale) ?? 1.0
            names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        }
    }

    struct SceneManifest: Decodable {
        let id: String
        /// Built-in bespoke renderer ("mushroomForest", "mistyMeadow");
        /// omit to use the data-driven generic renderer (`scene` spec).
        var renderer: String?
        var idleAction: String = "sway"
        var accentSound: String?
        var names: [String: String] = [:]
        var parade: ParadeSpec = .default
        var scene: GenericSceneSpec?

        private enum CodingKeys: String, CodingKey {
            case id, renderer, idleAction, accentSound, names, parade, scene
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            renderer = try c.decodeIfPresent(String.self, forKey: .renderer)
            idleAction = try c.decodeIfPresent(String.self, forKey: .idleAction) ?? "sway"
            accentSound = try c.decodeIfPresent(String.self, forKey: .accentSound)
            names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
            parade = try c.decodeIfPresent(ParadeSpec.self, forKey: .parade) ?? .default
            scene = try c.decodeIfPresent(GenericSceneSpec.self, forKey: .scene)
        }
    }
}

// MARK: - Scene building blocks (Codable: manifest + runtime)

/// Parade choreography, parameterized so packs can tune it. `laneY` holds
/// normalized lane heights; entities are dealt onto lanes by spawn phase
/// and odd lanes march in the opposite direction.
public struct ParadeSpec: Codable, Hashable, Sendable {
    public var style: Style
    /// Fraction of the screen span marched per second.
    public var speed: Double
    public var laneY: [Double]
    /// Hop/bob height in points.
    public var amplitude: Double
    /// Horizontal spacing of the hop/bob wave, in points per radian.
    public var waveLength: Double

    public enum Style: String, Codable, Sendable {
        case lanes  // energetic hopping between lanes
        case graze  // one slow grazing line with a gentle bob
    }

    public static let `default` = ParadeSpec()

    /// Defaults live only here; every decode path funnels through it.
    public init(style: Style? = nil, speed: Double? = nil,
                laneY: [Double]? = nil, amplitude: Double? = nil,
                waveLength: Double? = nil) {
        self.style = style ?? .lanes
        self.speed = speed ?? 0.06
        self.laneY = laneY ?? [0.8]
        self.amplitude = amplitude ?? 12
        self.waveLength = waveLength ?? 50
    }

    private enum CodingKeys: String, CodingKey {
        case style, speed, laneY, amplitude, waveLength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            style: try c.decodeIfPresent(Style.self, forKey: .style),
            speed: try c.decodeIfPresent(Double.self, forKey: .speed),
            laneY: try c.decodeIfPresent([Double].self, forKey: .laneY),
            amplitude: try c.decodeIfPresent(Double.self, forKey: .amplitude),
            waveLength: try c.decodeIfPresent(Double.self, forKey: .waveLength)
        )
    }
}

/// Data-driven scene background: gradient sky, optional ground band,
/// placed decorations (pack SVGs), ambient particles. Packs that want a
/// bespoke hand-coded look name a built-in `renderer` instead.
public struct GenericSceneSpec: Codable, Hashable, Sendable {
    /// Sky gradient hex colors, top to bottom (2 or more).
    public var gradient: [String] = ["#B8E0F0", "#FFF3D6"]
    public var ground: Ground?
    public var decorations: [Decoration] = []
    public var particles: Particles?

    public struct Ground: Codable, Hashable, Sendable {
        public var color: String = "#7FBF6A"
        /// Height as a fraction of screen height.
        public var height: Double = 0.18
    }

    public struct Decoration: Codable, Hashable, Sendable {
        /// SVG path relative to the pack directory.
        public let art: String
        /// Normalized position (0...1).
        public var x: Double = 0.5
        public var y: Double = 0.8
        public var scale: Double = 1.0
        public var motion: Motion = .none

        private enum CodingKeys: String, CodingKey {
            case art, x, y, scale, motion
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            art = try c.decode(String.self, forKey: .art)
            x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
            y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.8
            scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
            motion = try c.decodeIfPresent(Motion.self, forKey: .motion) ?? .none
        }
    }

    public enum Motion: String, Codable, Sendable {
        case none, sway, drift, pulse
    }

    public struct Particles: Codable, Hashable, Sendable {
        public var kind: Kind = .fireflies
        public var count: Int = 8

        public enum Kind: String, Codable, Sendable {
            case fireflies, mist
        }
    }

    private enum CodingKeys: String, CodingKey {
        case gradient, ground, decorations, particles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gradient = try c.decodeIfPresent([String].self, forKey: .gradient) ?? ["#B8E0F0", "#FFF3D6"]
        ground = try c.decodeIfPresent(Ground.self, forKey: .ground)
        decorations = try c.decodeIfPresent([Decoration].self, forKey: .decorations) ?? []
        particles = try c.decodeIfPresent(Particles.self, forKey: .particles)
    }

    public init() {}
}

// MARK: - Runtime definitions

/// Scene-specific idle animation style for an entity.
public enum IdleAction: String, Sendable {
    case hop
    case sway
}

/// A cute thing that can pop up on screen — animal, truck, doctor,
/// anything a theme pack describes.
/// Identity is the `id` string ("cat"); two definitions with the same id
/// (built-in and user override) are interchangeable for persisted data.
public struct EntityDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    /// Manifest id of the pack this entry came from (settings group
    /// content by pack).
    public let packID: String
    /// Directory of the pack this entry came from; asset paths resolve
    /// against it.
    public let packURL: URL
    public let artPath: String?
    public let soundPath: String?
    /// SF Symbol fallback when the pack ships no artwork.
    public let symbol: String
    /// Hex tint ("#RRGGBB") for the symbol fallback.
    public let colorHex: String
    /// System sound name fallback when the pack ships no sound file.
    public let systemSound: String
    /// Rough real-world size ratio — a bear is visibly bigger than a
    /// rabbit, an ant is tiny. 1.0 ≈ cat-sized.
    public let sizeScale: Double
    /// Display names keyed by bundle code ("en", "zh-Hans", "ja", …).
    public let names: [String: String]

    public var artURL: URL? { artPath.map { packURL.appending(path: $0) } }
    public var soundURL: URL? { soundPath.map { packURL.appending(path: $0) } }

    /// Baby-talk name in the given language, falling back to English,
    /// then any available language, then the id.
    public func name(for language: AppLanguage) -> String {
        Self.resolve(names, for: language) ?? id
    }

    static func resolve<T>(_ table: [String: T], for language: AppLanguage) -> T? {
        table[language.bundleCode] ?? table["en"] ?? table.first?.value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A themed playfield scene: background, idle motion, accent sound,
/// parade choreography — all from its pack manifest.
public struct SceneDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let packID: String
    public let packURL: URL
    public let names: [String: String]
    public let idleAction: IdleAction
    public let accentSoundPath: String?
    public let renderer: Renderer
    public let parade: ParadeSpec

    public enum Renderer: Hashable, Sendable {
        case mushroomForest
        case mistyMeadow
        case generic(GenericSceneSpec)
    }

    public var accentSoundURL: URL? { accentSoundPath.map { packURL.appending(path: $0) } }

    public func displayName(for language: AppLanguage) -> String {
        EntityDefinition.resolve(names, for: language) ?? id
    }

    /// Empty fallback when a catalog ships no scenes at all.
    public static let placeholder = SceneDefinition(
        id: "none", packID: "none", packURL: URL(fileURLWithPath: "/"),
        names: [:], idleAction: .sway, accentSoundPath: nil,
        renderer: .generic(GenericSceneSpec()), parade: .default)

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Catalog

/// All packs merged into one lookup: built-in packs from the resource
/// bundle first, then user packs from
/// `~/Library/Application Support/Tappy/Packs/`. A pack is either a
/// `.tappypack` DIRECTORY (development) or a `.tappypack` ZIP ARCHIVE
/// (distribution — the subscription-downloadable form); archives are
/// extracted into `~/Library/Caches/Tappy/Packs/` and re-extracted when
/// the file changes. A user entry whose id matches a built-in one
/// REPLACES it (parents can fix artwork or words without rebuilding).
public final class PackCatalog: Sendable {
    public let entities: [EntityDefinition]
    public let scenes: [SceneDefinition]
    /// Manifest ids of successfully loaded packs, in load order.
    public let packIDs: [String]
    /// Localized display names per pack id (theme picker); later packs
    /// override earlier ones together with their content.
    public let packNames: [String: [String: String]]

    nonisolated(unsafe) public static let shared = PackCatalog()

    private static let logger = Log.logger("packs")

    /// - Parameter userPacksDirectory: override in tests; `nil` skips
    ///   user packs entirely.
    public init(
        bundle: Bundle = TappyResources.bundle,
        userPacksDirectory: URL? = PackCatalog.defaultUserPacksDirectory
    ) {
        var candidates: [URL] = []
        if let builtin = bundle.urls(forResourcesWithExtension: "tappypack", subdirectory: "Packs") {
            candidates += builtin.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if let userPacksDirectory,
           let user = try? FileManager.default.contentsOfDirectory(
               at: userPacksDirectory,
               includingPropertiesForKeys: nil
           ).filter({ $0.pathExtension == "tappypack" }) {
            candidates += user.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        // Archives resolve to their extracted directory; unopenable or
        // unextractable packs are skipped with a log, never a crash.
        let packDirs = candidates.compactMap(Self.packDirectory(for:))

        var entities: [EntityDefinition] = []
        var scenes: [SceneDefinition] = []
        var packIDs: [String] = []
        var packNames: [String: [String: String]] = [:]
        for dir in packDirs {
            guard let manifest = Self.loadManifest(from: dir) else { continue }
            packIDs.append(manifest.id)
            packNames[manifest.id] = manifest.names
            for a in manifest.entities {
                let definition = EntityDefinition(
                    id: a.id, packID: manifest.id, packURL: dir,
                    artPath: a.art, soundPath: a.sound,
                    symbol: a.symbol, colorHex: a.color,
                    systemSound: a.systemSound, sizeScale: a.sizeScale,
                    names: a.names
                )
                if let existing = entities.firstIndex(of: definition) {
                    entities[existing] = definition
                } else {
                    entities.append(definition)
                }
            }
            for s in manifest.scenes {
                let definition = SceneDefinition(
                    id: s.id, packID: manifest.id, packURL: dir, names: s.names,
                    idleAction: IdleAction(rawValue: s.idleAction) ?? .sway,
                    accentSoundPath: s.accentSound,
                    renderer: Self.renderer(for: s),
                    parade: s.parade
                )
                if let existing = scenes.firstIndex(of: definition) {
                    scenes[existing] = definition
                } else {
                    scenes.append(definition)
                }
            }
            Self.logger.info("loaded pack \(manifest.id) (\(manifest.entities.count) entities, \(manifest.scenes.count) scenes)")
        }
        self.entities = entities
        self.scenes = scenes
        self.packIDs = packIDs
        self.packNames = packNames
    }

    /// Localized display name of a pack (theme picker): current language
    /// → English → any available → the raw id. Mirrors how entity and
    /// scene names resolve, so packs without names stay presentable.
    public func displayName(forPack packID: String, language: AppLanguage = .current) -> String {
        EntityDefinition.resolve(packNames[packID] ?? [:], for: language) ?? packID
    }

    public static var defaultUserPacksDirectory: URL {
        TappyResources.appSupport("Packs")
    }

    public func entity(_ id: String) -> EntityDefinition? {
        entities.first { $0.id == id }
    }

    public func scene(_ id: String) -> SceneDefinition? {
        scenes.first { $0.id == id }
    }

    /// A pack's entities, in load order.
    public func entities(forPack packID: String) -> [EntityDefinition] {
        entities.filter { $0.packID == packID }
    }

    /// A pack's scenes, in load order.
    public func scenes(forPack packID: String) -> [SceneDefinition] {
        scenes.filter { $0.packID == packID }
    }

    /// First scene, the app's home screen.
    public var defaultScene: SceneDefinition? { scenes.first }

    private static func loadManifest(from dir: URL) -> PackManifest? {
        let url = dir.appending(path: "pack.json")
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PackManifest.self, from: data)
        } catch {
            logger.error("skipping pack \(dir.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Archive extraction

    /// Resolves a `.tappypack` candidate to a directory containing
    /// `pack.json`: directories pass through, zip archives are extracted
    /// to the caches directory (keyed by size+mtime, so an updated
    /// archive is re-extracted, an unchanged one is reused).
    static func packDirectory(for candidate: URL) -> URL? {
        var isDirectory: ObjCBool = false
        let path = candidate.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue { return candidate }
        return extractArchive(candidate)
    }

    /// Test hook for the cache location.
    public nonisolated(unsafe) static var cacheDirectory: URL = {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return caches
            .appending(path: "Tappy", directoryHint: .isDirectory)
            .appending(path: "Packs", directoryHint: .isDirectory)
    }()

    static func extractArchive(_ archive: URL) -> URL? {
        let path = archive.path(percentEncoded: false)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int else { return nil }
        let name = archive.deletingPathExtension().lastPathComponent
        let key = "\(name)-\(size)-\(Int(mtime.timeIntervalSince1970))"
        let destination = cacheDirectory.appending(path: key, directoryHint: .isDirectory)
        let marker = destination.appending(path: ".extracted")
        if FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            return resolveRoot(of: destination)
        }

        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            logger.error("cannot create pack cache: \(error.localizedDescription)")
            return nil
        }
        // ditto -xk: the zip extractor present on every macOS; no extra
        // dependency for a format the system already speaks.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", path, destination.path(percentEncoded: false)]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("cannot run ditto for \(name): \(error.localizedDescription)")
            return nil
        }
        guard process.terminationStatus == 0 else {
            logger.error("ditto failed (\(process.terminationStatus)) extracting \(name)")
            try? FileManager.default.removeItem(at: destination)
            return nil
        }

        // Tolerate archives that wrap everything in one top-level folder.
        FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: nil)
        logger.info("extracted pack archive \(name) -> \(key)")
        return resolveRoot(of: destination)
    }

    /// The directory actually holding pack.json: the extraction root, or
    /// its single child when the archive wraps contents in a folder.
    private static func resolveRoot(of destination: URL) -> URL? {
        let manifest = FileManager.default.fileExists(
            atPath: destination.appending(path: "pack.json").path(percentEncoded: false))
        if manifest { return destination }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: destination, includingPropertiesForKeys: nil
        ).filter({ !$0.lastPathComponent.hasPrefix(".") }),
              children.count == 1,
              FileManager.default.fileExists(
                atPath: children[0].appending(path: "pack.json").path(percentEncoded: false))
        else { return nil }
        return children[0]
    }

    private static func renderer(for scene: PackManifest.SceneManifest) -> SceneDefinition.Renderer {
        switch scene.renderer {
        case "mushroomForest": return .mushroomForest
        case "mistyMeadow": return .mistyMeadow
        default: return .generic(scene.scene ?? GenericSceneSpec())
        }
    }
}
