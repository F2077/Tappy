import Foundation

/// Resolves the TappyCore resource bundle across layouts:
/// - swift run / tests: SwiftPM's generated `Bundle.module` (build dir)
/// - packaged .app: Contents/Resources/Tappy_TappyCore.bundle (the app
///   root is off-limits — codesign refuses to seal contents placed there)
public enum TappyResources {
    /// Root of Tappy's writable area under Application Support
    /// (`.../Tappy/<subpath>`), shared by user packs and custom sounds.
    public static func appSupport(_ subpath: String) -> URL {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return root
            .appending(path: "Tappy", directoryHint: .isDirectory)
            .appending(path: subpath, directoryHint: .isDirectory)
    }

    public static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appending(path: "Tappy_TappyCore.bundle")) {
            return bundle
        }
        return Bundle.module
    }()
}
