import Foundation

/// App localization, resolved from the resource bundle's preferred
/// localization. Babies' apps ship in the system language; parents can
/// switch via macOS language settings.
public enum AppLanguage: Sendable, CaseIterable {
    case english, chinese, japanese, korean, spanish, french, german

    /// One row per language: matching prefixes for the system locale,
    /// the pack-manifest/bundle-directory code, and the BCP-47 speech
    /// locale. English last — the table is also the fallback chain.
    private static let rows: [(language: AppLanguage,
                               prefixes: [String],
                               bundleCode: String,
                               speechLocale: String)] = [
        (.chinese, ["zh"], "zh-Hans", "zh-CN"),
        (.japanese, ["ja"], "ja", "ja-JP"),
        (.korean, ["ko"], "ko", "ko-KR"),
        (.spanish, ["es"], "es", "es-ES"),
        (.french, ["fr"], "fr", "fr-FR"),
        (.german, ["de"], "de", "de-DE"),
        (.english, [], "en", "en-US"),
    ]

    /// Resolved from the bundle localizations that actually exist.
    /// TAPPY_LANG forces a language for the E2E harness — the
    /// `-AppleLanguages` argument does not reach this bundle's
    /// preferredLocalizations (verified; it only affects Bundle.main).
    public static var current: AppLanguage {
        if let raw = ProcessInfo.processInfo.environment["TAPPY_LANG"] {
            return allCases.first { $0.bundleCode == raw } ?? resolved()
        }
        return resolved()
    }

    private static func resolved() -> AppLanguage {
        let code = TappyResources.bundle.preferredLocalizations.first
        return rows.first { row in
            row.prefixes.contains { code?.hasPrefix($0) ?? false }
        }?.language ?? .english
    }

    /// BCP-47 locale for speech synthesis.
    public var speechLocale: String {
        Self.rows.first { $0.language == self }?.speechLocale ?? "en-US"
    }

    /// Localization directory / pack-manifest key ("en", "zh-Hans", …).
    public var bundleCode: String {
        Self.rows.first { $0.language == self }?.bundleCode ?? "en"
    }
}

/// Localized user-facing strings, backed by Localizable.xcstrings in
/// this module's resource bundle.
public enum L10n {
    public static var settingsTitle: String { String(localized: "settings.title", bundle: TappyResources.bundle) }
    public static var settingsTheme: String { String(localized: "settings.theme", bundle: TappyResources.bundle) }
    public static var settingsSound: String { String(localized: "settings.sound", bundle: TappyResources.bundle) }
    public static var settingsSpeech: String { String(localized: "settings.speech", bundle: TappyResources.bundle) }
    public static var settingsShowNames: String { String(localized: "settings.showNames", bundle: TappyResources.bundle) }
    public static var settingsLock: String { String(localized: "settings.lock", bundle: TappyResources.bundle) }
    public static var settingsAbout: String { String(localized: "settings.about", bundle: TappyResources.bundle) }
    public static var settingsQuit: String { String(localized: "settings.quit", bundle: TappyResources.bundle) }
    public static var settingsDone: String { String(localized: "settings.done", bundle: TappyResources.bundle) }
    public static var settingsCredits: String { String(localized: "settings.credits", bundle: TappyResources.bundle) }
    public static var settingsAboutButton: String { String(localized: "settings.aboutButton", bundle: TappyResources.bundle) }
    public static var aboutTitle: String { String(localized: "about.title", bundle: TappyResources.bundle) }
    public static var aboutStory: String { String(localized: "about.story", bundle: TappyResources.bundle) }
    public static var aboutSourceCode: String { String(localized: "about.sourceCode", bundle: TappyResources.bundle) }
    public static var aboutAckTitle: String { String(localized: "about.ackTitle", bundle: TappyResources.bundle) }
    public static var aboutLegalNote: String { String(localized: "about.legalNote", bundle: TappyResources.bundle) }

    /// Localized third-party component titles ("license.<id>").
    public static func licenseTitle(_ id: String) -> String {
        String(localized: String.LocalizationValue("license.\(id)"),
               bundle: TappyResources.bundle)
    }
    public static var hintControls: String { String(localized: "hint.controls", bundle: TappyResources.bundle) }
    public static var hintExplore: String { String(localized: "hint.explore", bundle: TappyResources.bundle) }
    public static var paradeAnnouncement: String { String(localized: "parade.announcement", bundle: TappyResources.bundle) }
}
