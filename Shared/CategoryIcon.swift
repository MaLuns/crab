import AppKit

enum CategoryIcon: String, CaseIterable {
    case general, newFile, send, move, common, customIcons, tools, scripts
    case images, applications, archives

    var symbol: String {
        switch self {
        case .general: return "settings"
        case .newFile: return "file-plus"
        case .send: return "copy"
        case .move: return "folder-symlink"
        case .common: return "heart"
        case .customIcons: return "palette"
        case .tools: return "tools"
        case .scripts: return "terminal"
        case .images: return "photo"
        case .applications: return "app-window"
        case .archives: return "archive"
        }
    }

    var color: NSColor {
        let light: (CGFloat, CGFloat, CGFloat)
        let dark: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .general, .images: light = (0.12, 0.43, 0.83); dark = (0.17, 0.49, 0.90)
        case .newFile: light = (0.00, 0.48, 0.55); dark = (0.03, 0.55, 0.61)
        case .send, .move: light = (0.23, 0.49, 0.18); dark = (0.28, 0.56, 0.22)
        case .common: light = (0.80, 0.19, 0.34); dark = (0.89, 0.26, 0.42)
        case .customIcons, .archives: light = (0.75, 0.39, 0.07); dark = (0.82, 0.43, 0.10)
        case .tools: light = (0.53, 0.28, 0.75); dark = (0.65, 0.38, 0.86)
        case .scripts, .applications: light = (0.35, 0.41, 0.73); dark = (0.44, 0.51, 0.84)
        }
        return NSColor(name: NSColor.Name("Crab.Category." + rawValue)) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }

    func image(size: CGFloat = 18) -> NSImage? {
        CrabSymbol.image(named: symbol, size: size)
    }

    func image(style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let outline = image(size: size) else { return nil }
        return style == .color ? coloredImage(outline, size: size) : outline
    }

    func coloredImage(_ outline: NSImage, size: CGFloat = 18, color tintColor: NSColor? = nil) -> NSImage? {
        guard size.isFinite, size > 0, size <= 2048,
              outline.isValid, outline.size.width > 0, outline.size.height > 0,
              let paletteAppearance = NSAppearance(named: .aqua) else { return nil }
        let result = NSImage(size: NSSize(width: size, height: size))
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(size * CGFloat(scale))), pixelsHigh: Int(ceil(size * CGFloat(scale))),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            bitmap.size = result.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            paletteAppearance.performAsCurrentDrawingAppearance {
                let bounds = NSRect(x: 0, y: 0, width: size, height: size)
                let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                        xRadius: size * 0.23, yRadius: size * 0.23)
                let tint = tintColor ?? color
                NSGradient(starting: tint.blended(withFraction: 0.10, of: .white) ?? tint, ending: tint)?.draw(in: path, angle: 90)
                NSColor.white.withAlphaComponent(0.12).setStroke()
                path.lineWidth = 0.5; path.stroke()
                let glyphScale = size * 0.72 / max(outline.size.width, outline.size.height)
                let glyphSize = NSSize(width: outline.size.width * glyphScale, height: outline.size.height * glyphScale)
                let glyphRect = NSRect(x: (size - glyphSize.width) / 2, y: (size - glyphSize.height) / 2,
                                       width: glyphSize.width, height: glyphSize.height)
                context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
                outline.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
                NSColor.white.setFill(); glyphRect.fill(using: .sourceIn)
                context.cgContext.endTransparencyLayer()
            }
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            result.addRepresentation(bitmap)
        }
        result.isTemplate = false
        result.accessibilityDescription = outline.accessibilityDescription
        return result
    }

    static func toolCategory(_ category: String) -> CategoryIcon? {
        switch category {
        case "文件（夹）操作": return .tools
        case "图片转换": return .images
        case "进入 App": return .applications
        case "压缩与解压": return .archives
        default: return nil
        }
    }
}
