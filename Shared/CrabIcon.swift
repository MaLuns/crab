import AppKit

enum CrabIcon {
    static func image(size: CGFloat) -> NSImage? {
        guard size.isFinite, size > 0 else { return nil }
        for bundle in [Bundle(for: CrabIconBundleMarker.self), Bundle.main] {
            if let image = image(size: size, in: bundle) { return image }
        }
        return nil
    }

    static func image(size: CGFloat, in bundle: Bundle) -> NSImage? {
        guard size.isFinite, size > 0 else { return nil }
        for directory in [nil, "Resources"] as [String?] {
            guard let url = bundle.url(forResource: "CrabIcon", withExtension: "png", subdirectory: directory),
                  let image = NSImage(contentsOf: url), image.isValid else { continue }
            image.size = NSSize(width: size, height: size)
            image.isTemplate = false
            image.accessibilityDescription = "Crab"
            return image
        }
        return nil
    }
}

private final class CrabIconBundleMarker: NSObject {}
