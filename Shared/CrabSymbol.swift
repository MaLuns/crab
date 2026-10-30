import AppKit

enum CrabSymbol {
    static var names: [String] { CrabSymbolArtwork.names }
    private static let availableNames = Set(CrabSymbolArtwork.names)
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String, size: CGFloat = 18, template: Bool = true) -> NSImage? {
        guard size.isFinite, size > 0, size <= 2048 else { return nil }
        let iconName = name.hasPrefix("tabler-") ? String(name.dropFirst(7)) : name
        guard availableNames.contains(iconName) else { return nil }
        let key = iconName as NSString
        let original: NSImage
        if let cached = cache.object(forKey: key) {
            original = cached
        } else {
            guard let rendered = vectorImage(named: iconName) else { return nil }
            cache.setObject(rendered, forKey: key)
            original = rendered
        }
        guard let result = original.copy() as? NSImage else { return nil }
        result.size = NSSize(width: size, height: size)
        result.isTemplate = template
        result.accessibilityDescription = iconName.replacingOccurrences(of: "-", with: " ")
        return result
    }

    static func image(forLegacySymbol symbol: String, size: CGFloat = 18, template: Bool = true) -> NSImage? {
        image(named: legacyMapping[symbol] ?? symbol, size: size, template: template)
    }

    private static func vectorImage(named name: String) -> NSImage? {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { return nil }
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: 24)
        context.scaleBy(x: 1, y: -1)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1.65)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let drawn = CrabSymbolArtwork.draw(name, on: CrabSymbolCanvas(context: context))
        context.endPDFPage()
        context.closePDF()
        guard drawn, let representation = NSPDFImageRep(data: data as Data),
              representation.pageCount == 1, representation.bounds == bounds else { return nil }
        let result = NSImage(size: bounds.size)
        result.addRepresentation(representation)
        return result
    }

    static let legacyMapping: [String: String] = [
        "cursorarrow.and.square.on.square.dashed": "mouse", "cursorarrow.click.2": "mouse",
        "cursorarrow.click": "click", "cursorarrow": "pointer", "computermouse": "mouse",
        "doc": "file", "doc.fill": "file", "doc.text": "file-text", "doc.plaintext": "file-text",
        "doc.richtext": "file-typography", "doc.badge.plus": "file-plus", "doc.badge.gearshape": "file-code",
        "doc.on.doc": "copy", "doc.on.clipboard": "clipboard", "doc.zipper": "file-zip",
        "text.alignleft": "file-text", "curlybraces": "braces", "tablecells": "table",
        "chevron.left.forwardslash.chevron.right": "code", "swift": "brand-swift",
        "folder": "folder", "folder.fill": "folder", "folder.badge.plus": "folder-plus",
        "folder.badge.minus": "folder-minus", "folder.badge.gearshape": "folder-cog",
        "folder.badge.person.crop": "folder-share", "folder.badge.questionmark": "folder",
        "paperplane": "send", "paperplane.fill": "send", "paintpalette": "palette",
        "wrench.and.screwdriver": "tools", "wrench": "tools", "gearshape": "settings", "gearshape.fill": "settings",
        "questionmark.circle": "help-circle", "info.circle": "info-circle", "info.circle.fill": "info-circle",
        "plus": "plus", "plus.circle": "plus", "minus": "minus", "minus.circle": "minus",
        "chevron.up": "chevron-up", "chevron.down": "chevron-down", "chevron.left": "chevron-left", "chevron.right": "chevron-right",
        "arrow.up": "arrow-up", "arrow.down": "arrow-down", "arrow.right": "arrow-right",
        "arrow.uturn.backward": "arrow-back-up", "arrow.counterclockwise": "rotate",
        "arrow.clockwise": "rotate-clockwise", "arrow.triangle.2.circlepath": "refresh",
        "photo": "photo", "photo.fill": "photo", "photo.on.rectangle": "photo", "photo.artframe": "photo",
        "terminal": "terminal", "terminal.fill": "terminal", "archivebox": "archive", "archivebox.fill": "archive",
        "qrcode": "qrcode", "wand.and.stars": "wand", "link": "link", "link.circle": "link",
        "trash": "trash", "trash.fill": "trash", "trash.slash": "trash-x", "scissors": "cut",
        "eye": "eye", "eye.slash": "eye-off", "eye.fill": "eye", "checkmark": "check",
        "xmark": "x", "xmark.circle.fill": "x", "checkmark.circle": "check",
        "square.and.arrow.up": "upload", "square.and.arrow.down": "download",
        "arrow.up.right.square": "external-link", "puzzlepiece.extension": "puzzle",
        "display": "device-desktop", "desktopcomputer": "device-desktop", "camera.viewfinder": "screenshot",
        "rectangle.dashed": "scan", "character.bubble": "language", "character.book.closed": "language",
        "ellipsis": "dots", "ellipsis.circle": "dots", "line.3.horizontal": "menu-2"
    ]
}

struct CrabSymbolCanvas {
    let context: CGContext

    func stroke(_ points: [(CGFloat, CGFloat)], closed: Bool = false) {
        guard let first = points.first else { return }
        path { path in
            path.move(to: CGPoint(x: first.0, y: first.1))
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
            if closed { path.closeSubpath() }
        }
    }

    func path(_ body: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        body(path)
        context.addPath(path)
        context.strokePath()
    }

    func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 2.5) {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height),
                               cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
    }

    func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        context.strokeEllipse(in: CGRect(x: x, y: y, width: width, height: height))
    }

    func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat = 0.85) {
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
}
