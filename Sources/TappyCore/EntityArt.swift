import AppKit
import SwiftDraw

/// Loads and caches vector artwork from resource packs. Each SVG is
/// parsed once into a 512×512 lazy NSImage whose drawing handler
/// re-renders the vector at every requested draw size, so entities stay
/// crisp at any scale on Retina screens. Per-frame SVGView rendering
/// proved unstable on this toolchain (heap corruption in
/// AttributeGraph executor checks), and cached images are cheaper anyway.
public enum EntityArt {
    // NSImage is not Sendable; main-thread confinement only.
    nonisolated(unsafe) private static var cache: [URL: NSImage] = [:]

    /// The rasterized artwork for an entity, or `nil` if the pack ships
    /// none or it fails to render (callers fall back to the SF Symbol).
    public static func image(for entity: EntityDefinition) -> NSImage? {
        guard let url = entity.artURL else { return nil }
        return image(at: url)
    }

    /// Rasterizes any pack SVG (scene decorations use this too).
    public static func image(at url: URL) -> NSImage? {
        if let cached = cache[url] { return cached }
        guard let svg = SVG(fileURL: url) else { return nil }
        // rasterize(with:) returns a LAZY NSImage backed by a drawing
        // handler: AppKit re-invokes it at every distinct draw size, so
        // the vector stays sharp at any scale. Materializing a fixed
        // bitmap via pngData() instead upscales pixels and shows
        // jagged edges on Retina screens — do not "simplify" this.
        let image = svg.rasterize(with: CGSize(width: 512, height: 512))
        cache[url] = image
        return image
    }
}
