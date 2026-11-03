import AppKit

// Both views use top-left coordinates, matching the oriented image and CGImage.cropping(to:).
private enum CropDrawing {
    static func fitted(_ image: CGImage, in area: CGRect) -> CGRect {
        guard area.size.width > 0, area.size.height > 0 else { return .zero }
        let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    private static let checker = NSColor(patternImage: NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
        NSColor(white: 0.88, alpha: 1).setFill()
        rect.fill()
        NSColor(white: 0.75, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 8, height: 8).fill()
        CGRect(x: 8, y: 8, width: 8, height: 8).fill()
        return true
    })

    static func background(in rect: CGRect, color: CGColor?) {
        if let color, let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(color)
            context.fill(rect)
        } else {
            checker.setFill()
            rect.fill()
        }
    }

    static func image(_ image: CGImage, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}

final class IconResultPreview: NSView {
    private var result: CGImage?
    private var backgroundColor: CGColor?
    override var isFlipped: Bool { true }

    func display(image: CGImage?, crop: IconCrop?, backgroundColor: CGColor?) {
        if let image, let crop {
            result = image.cropping(to: crop.pixelRect(in: CGSize(width: image.width, height: image.height)))
        } else {
            result = image
        }
        self.backgroundColor = backgroundColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let result else { return }
        let side = min(bounds.width, bounds.height)
        let frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        CropDrawing.background(in: frame, color: backgroundColor)
        CropDrawing.image(result, in: CropDrawing.fitted(result, in: frame))
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

final class IconCropCanvas: NSView {
    var onCropChange: ((IconCrop) -> Void)?
    private var image: CGImage?
    private var crop: IconCrop?
    private var backgroundColor: CGColor?
    private enum Gesture {
        case move(offset: CGPoint, side: CGFloat)
        case resize(anchor: CGPoint, direction: CGVector, offset: CGPoint)
    }
    private var gesture: Gesture?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { image != nil && crop != nil }

    func display(image: CGImage?, crop: IconCrop?, backgroundColor: CGColor?) {
        if self.image !== image || crop == nil { gesture = nil }
        self.image = image
        self.crop = crop
        self.backgroundColor = backgroundColor
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private var imageRect: CGRect {
        guard let image else { return .zero }
        return CropDrawing.fitted(image, in: bounds.insetBy(dx: 14, dy: 14))
    }

    private var selection: CGRect? {
        guard let image, let crop, !imageRect.isEmpty else { return nil }
        let frame = imageRect
        let pixels = crop.pixelRect(in: CGSize(width: image.width, height: image.height))
        let scale = frame.width / CGFloat(image.width)
        return CGRect(x: frame.minX + pixels.minX * scale, y: frame.minY + pixels.minY * scale,
                      width: pixels.width * scale, height: pixels.height * scale)
    }

    // Signed diagonals describe the four handles and their opposite, fixed corners.
    private static let diagonals = [CGVector(dx: -1, dy: -1), CGVector(dx: 1, dy: -1),
                                    CGVector(dx: -1, dy: 1), CGVector(dx: 1, dy: 1)]
    private func corner(of rect: CGRect, direction: CGVector) -> CGPoint {
        CGPoint(x: rect.midX + direction.dx * rect.width / 2, y: rect.midY + direction.dy * rect.height / 2)
    }

    private func handleArea(of rect: CGRect, direction: CGVector) -> CGRect {
        let point = corner(of: rect, direction: direction)
        let reach = min(7, rect.width / 3)
        return CGRect(x: point.x - reach, y: point.y - reach, width: 2 * reach, height: 2 * reach)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        guard let image, !imageRect.isEmpty else { return }
        CropDrawing.background(in: imageRect, color: backgroundColor)
        CropDrawing.image(image, in: imageRect)
        guard let rect = selection else { return }
        let shade = NSBezierPath(rect: imageRect)
        shade.appendRect(rect)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        shade.fill()

        let border = NSBezierPath(rect: rect)
        NSColor.black.withAlphaComponent(0.65).setStroke()
        border.lineWidth = 2.5
        border.stroke()
        NSColor.white.setStroke()
        border.lineWidth = 1.25
        border.stroke()
        for direction in Self.diagonals {
            let center = corner(of: rect, direction: direction)
            let handle = NSBezierPath(roundedRect: CGRect(x: center.x - 3.5, y: center.y - 3.5,
                                                          width: 7, height: 7), xRadius: 1.5, yRadius: 1.5)
            NSColor.white.setFill()
            handle.fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            handle.stroke()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let rect = selection else { return }
        addCursorRect(rect, cursor: .openHand)
        for direction in Self.diagonals {
            addCursorRect(handleArea(of: rect, direction: direction), cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let rect = selection else { return }
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        for direction in Self.diagonals where handleArea(of: rect, direction: direction).contains(point) {
            let handle = corner(of: rect, direction: direction)
            let opposite = CGVector(dx: -direction.dx, dy: -direction.dy)
            gesture = .resize(anchor: corner(of: rect, direction: opposite), direction: direction,
                              offset: CGPoint(x: point.x - handle.x, y: point.y - handle.y))
            return
        }
        guard imageRect.contains(point) else { return }
        let offset = rect.contains(point) ? CGPoint(x: point.x - rect.midX, y: point.y - rect.midY) : .zero
        gesture = .move(offset: offset, side: rect.width)
        if !rect.contains(point) { move(to: point, side: rect.width) }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch gesture {
        case let .move(offset, side):
            move(to: CGPoint(x: point.x - offset.x, y: point.y - offset.y), side: side)
        case let .resize(anchor, direction, offset):
            let frame = imageRect
            let limitX = direction.dx > 0 ? frame.maxX - anchor.x : anchor.x - frame.minX
            let limitY = direction.dy > 0 ? frame.maxY - anchor.y : anchor.y - frame.minY
            let dx = (point.x - offset.x - anchor.x) * direction.dx
            let dy = (point.y - offset.y - anchor.y) * direction.dy
            // Even on a panorama, allow a square smaller than the displayed short edge.
            let minimum = min(16, min(frame.width, frame.height) / 8)
            let side = min(limitX, limitY, max(minimum, (dx + dy) / 2))
            move(to: CGPoint(x: anchor.x + direction.dx * side / 2,
                             y: anchor.y + direction.dy * side / 2), side: side)
        case nil: break
        }
    }

    override func mouseUp(with event: NSEvent) { gesture = nil }

    override func keyDown(with event: NSEvent) {
        guard let rect = selection, let image else { super.keyDown(with: event); return }
        let step = imageRect.width / CGFloat(image.width) * (event.modifierFlags.contains(.shift) ? 10 : 1)
        var center = CGPoint(x: rect.midX, y: rect.midY)
        switch event.specialKey {
        case .leftArrow: center.x -= step
        case .rightArrow: center.x += step
        case .upArrow: center.y -= step
        case .downArrow: center.y += step
        default: super.keyDown(with: event); return
        }
        move(to: center, side: rect.width)
    }

    private func move(to point: CGPoint, side: CGFloat) {
        let frame = imageRect
        guard !frame.isEmpty, side > 0 else { return }
        let half = side / 2
        let x = max(frame.minX + half, min(point.x, frame.maxX - half))
        let y = max(frame.minY + half, min(point.y, frame.maxY - half))
        let updated = IconCrop(center: CGPoint(x: (x - frame.minX) / frame.width, y: (y - frame.minY) / frame.height),
                               fraction: side / min(frame.width, frame.height))
        crop = updated
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onCropChange?(updated)
    }
}
