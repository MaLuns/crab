import AppKit

enum FinderMenuPresentation {
    static func prepare(_ menu: NSMenu, appearance: NSAppearance) {
        for item in menu.items {
            if !item.isSeparatorItem, let source = item.image, source.isTemplate,
                      let image = resolvedImage(source, appearance: appearance) {
                item.image = image
            }
            if let submenu = item.submenu { prepare(submenu, appearance: appearance) }
        }
    }

    private static func resolvedImage(_ source: NSImage, appearance: NSAppearance) -> NSImage? {
        let size = source.size
        guard size.width > 0, size.height > 0 else { return nil }
        let result = NSImage(size: size)
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int((size.width * CGFloat(scale)).rounded()),
                pixelsHigh: Int((size.height * CGFloat(scale)).rounded()),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            appearance.performAsCurrentDrawingAppearance {
                let bounds = NSRect(origin: .zero, size: size)
                source.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
                NSColor.labelColor.setFill()
                bounds.fill(using: .sourceIn)
            }
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            result.addRepresentation(bitmap)
        }
        result.isTemplate = false
        result.accessibilityDescription = source.accessibilityDescription
        return result
    }
}
