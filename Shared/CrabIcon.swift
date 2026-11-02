import AppKit

enum CrabIcon {
    static func image(size: CGFloat, appearance: NSAppearance? = nil) -> NSImage? {
        guard size.isFinite, size > 0 else { return nil }
        for bundle in [Bundle(for: CrabIconBundleMarker.self), Bundle.main] {
            if let image = image(size: size, in: bundle, appearance: appearance) { return image }
        }
        return nil
    }

    static func image(size: CGFloat, in bundle: Bundle, appearance: NSAppearance? = nil) -> NSImage? {
        guard size.isFinite, size > 0 else { return nil }
        var source = bundle.image(forResource: NSImage.Name("CrabArtwork"))
        for directory in [nil, "Resources"] as [String?] {
            guard source == nil else { break }
            guard let url = bundle.url(forResource: "CrabIcon", withExtension: "png", subdirectory: directory),
                  let image = NSImage(contentsOf: url), image.isValid else { continue }
            source = image
        }
        guard let image = source?.copy() as? NSImage, image.isValid else { return nil }
        image.size = NSSize(width: size, height: size)
        let result: NSImage
        if let appearance {
            var bitmap: CGImage?
            appearance.performAsCurrentDrawingAppearance {
                bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            guard let bitmap else { return nil }
            result = NSImage(cgImage: bitmap, size: image.size)
        } else {
            // Keep the catalog image dynamic so each window uses its own appearance.
            result = image
        }
        result.isTemplate = false
        result.accessibilityDescription = "Crab"
        return result
    }
}

private final class CrabIconBundleMarker: NSObject {}
