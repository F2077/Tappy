import AppKit
import AVFoundation

/// Plays the short sound attached to each entity.
///
/// Lookup order: custom pack file in
/// `~/Library/Application Support/Tappy/Sounds/` (parent overrides) →
/// sound shipped in the entity's resource pack → macOS system sound.
public enum SoundPlayer {
    /// Set to `false` in tests (or for quiet mode).
    /// Main-thread confinement only, like the rest of the audio path.
    nonisolated(unsafe) public static var isEnabled = true

    /// Extensions tried when looking up a custom sound file.
    public static let supportedExtensions = ["wav", "aif", "aiff", "mp3", "m4a", "caf"]

    /// Directory scanned for custom sound files.
    public static let customSoundsDirectory = TappyResources.appSupport("Sounds")

    // NSSound is not Sendable; main-thread confinement only.
    nonisolated(unsafe) private static var cache: [String: NSSound] = [:]
    nonisolated(unsafe) private static var accentCache: [String: NSSound] = [:]

    /// Plays a scene's soft accent sound (parade start, scene switch).
    public static func playAccent(for scene: SceneDefinition) {
        guard isEnabled else { return }
        if let cached = accentCache[scene.id] {
            playFromStart(cached, volume: 0.35)
            return
        }
        guard let url = scene.accentSoundURL,
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        accentCache[scene.id] = sound
        playFromStart(sound, volume: 0.35)
    }

    public static func playPop(for entity: EntityDefinition) {
        guard isEnabled, let sound = sound(for: entity) else { return }
        playFromStart(sound, volume: 0.6)
    }

    /// An entity's full audible reaction: its pop sound plus its name
    /// spoken aloud (no-op while speech is disabled). Both the spawn and
    /// tap paths react this way, so the pairing lives here.
    public static func announce(_ definition: EntityDefinition) {
        playPop(for: definition)
        Speaker.shared.say(definition.name(for: .current))
    }

    /// Restarts a cached sound from the beginning even if the same one
    /// was retriggered mid-play.
    private static func playFromStart(_ sound: NSSound, volume: Float) {
        if sound.isPlaying { sound.stop() }
        sound.volume = volume
        sound.play()
    }

    /// Resolves the sound for an entity: custom → pack → system.
    static func sound(for entity: EntityDefinition) -> NSSound? {
        if let cached = cache[entity.id] { return cached }
        let resolved: NSSound?
        if let url = customSoundURL(for: entity.id, in: customSoundsDirectory) {
            resolved = NSSound(contentsOf: url, byReference: true)
        } else if let url = entity.soundURL {
            resolved = NSSound(contentsOf: url, byReference: true)
        } else {
            resolved = NSSound(named: NSSound.Name(entity.systemSound))
                ?? NSSound(named: NSSound.Name("Pop"))
        }
        if let resolved { cache[entity.id] = resolved }
        return resolved
    }

    /// Finds a user-provided sound file for an entity id in `directory`,
    /// e.g. `cat.wav`, falling back to a catch-all `default.<ext>` file.
    /// Returns `nil` when no custom file exists.
    public static func customSoundURL(for entityID: String, in directory: URL) -> URL? {
        for name in [entityID, "default"] {
            for ext in supportedExtensions {
                let url = directory.appending(path: "\(name).\(ext)")
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    return url
                }
            }
        }
        return nil
    }
}

/// Speaks the entity name (in the current app language), at most once
/// a second so rapid keyboard banging does not queue a long speech
/// backlog. Disabled by default — pack sounds are the primary audio
/// feedback; a parent can re-enable speech in the settings.
public final class Speaker {
    nonisolated(unsafe) public static let shared = Speaker()

    public var isEnabled = false

    private let synth = AVSpeechSynthesizer()
    private var lastSpokeAt: Date = .distantPast

    private init() {}

    public func say(_ text: String) {
        guard isEnabled, !synth.isSpeaking else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpokeAt) > 1.0 else { return }
        lastSpokeAt = now

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AppLanguage.current.speechLocale)
        utterance.rate = 0.45 // slower than default, easier for a toddler
        synth.speak(utterance)
    }
}
