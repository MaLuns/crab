import AppKit
import QuartzCore

enum ReferenceStyle {
    static let windowSize = NSSize(width: 900, height: 700)
    static let pageInset: CGFloat = 40
    static let pageWidth: CGFloat = 620
    static let pageTitleY: CGFloat = 24
    static var text: NSColor { .labelColor }
    static var secondary: NSColor { .secondaryLabelColor }
    static var blue: NSColor { .controlAccentColor }
}

func referenceUseOverlayScrollers(_ scroll: NSScrollView) {
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    scroll.verticalScroller?.controlSize = .small
    scroll.horizontalScroller?.controlSize = .small
}

class ReferenceCanvas: NSView {
    var fill: NSColor?
    var radius: CGFloat = 0
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let fill else { return }
        fill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    convenience init(color: NSColor? = nil, radius: CGFloat = 0) { self.init(frame: .zero); fill = color; self.radius = radius }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class ReferenceMaterialCard: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let tint = NSColor.controlBackgroundColor
            NSGradient(starting: tint.withAlphaComponent(0.22), ending: tint.withAlphaComponent(0.06))?
                .draw(in: NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16), angle: 0)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class ReferenceWindowCanvas: ReferenceCanvas {
    private let roundedMask = CAShapeLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.mask = roundedMask
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        updateRoundedMask()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateRoundedMask()
    }
    override func viewWillDraw() {
        updateRoundedMask()
        super.viewWillDraw()
    }
    private func updateRoundedMask() {
        roundedMask.frame = bounds
        roundedMask.path = CGPath(roundedRect: bounds, cornerWidth: 24, cornerHeight: 24, transform: nil)
    }
}

@discardableResult
func referencePlace<T: NSView>(_ view: T, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in parent: NSView) -> T {
    view.frame = NSRect(x: x, y: y, width: width, height: height)
    view.translatesAutoresizingMaskIntoConstraints = true
    parent.addSubview(view)
    return view
}

func referenceLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = ReferenceStyle.text, alignment: NSTextAlignment = .left) -> NSTextField {
    let field = NSTextField(labelWithString: L(text))
    field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color; field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    return field
}

func referenceLink(_ title: String, size: CGFloat = 13, action: @escaping () -> Void) -> ClosureButton {
    let button = ClosureButton(L(title), action: action)
    button.isBordered = false; button.bezelStyle = .rounded; button.font = .systemFont(ofSize: size)
    button.contentTintColor = ReferenceStyle.blue; button.alignment = .left
    let text = NSAttributedString(string: L(title), attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: ReferenceStyle.blue])
    button.attributedTitle = text
    return button
}

func referenceButton(_ title: String, action: @escaping () -> Void) -> ClosureButton {
    let button = ClosureButton(L(title), action: action)
    button.font = .systemFont(ofSize: 13); button.bezelStyle = .rounded
    button.controlSize = .regular
    if title == "+" || title == "-" {
        button.image = CrabSymbol.image(named: title == "+" ? "plus" : "minus", size: 13)
        button.imagePosition = .imageOnly
    }
    return button
}

func referenceCheck(_ title: String, value: Bool, changed: @escaping (Bool) -> Void) -> ClosureCheck {
    let check = ClosureCheck(L(title), value: value, changed: changed)
    check.font = .systemFont(ofSize: 13)
    return check
}

func referenceFittingSize(_ view: NSView) -> NSSize {
    var size = view.intrinsicContentSize
    if let control = view as? NSControl, let cell = control.cell {
        size.width = max(size.width, cell.cellSize.width)
        size.height = max(size.height, cell.cellSize.height)
    }
    if let popup = view as? NSPopUpButton {
        let font = popup.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let widest = popup.itemTitles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        size.width = max(size.width, widest + 38)
    }
    let height = view is NSTextField ? ceil(max(0, size.height)) : ceil(max(20, size.height)) + 2
    return NSSize(width: ceil(max(0, size.width)) + 4, height: height)
}

@discardableResult
func referenceWrapLabel(_ field: NSTextField, width: CGFloat) -> NSSize {
    field.maximumNumberOfLines = 0
    field.usesSingleLineMode = false
    field.lineBreakMode = .byWordWrapping
    field.cell?.wraps = true
    field.cell?.isScrollable = false
    field.preferredMaxLayoutWidth = max(1, width - 4)
    let size = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width), height: .greatestFiniteMagnitude)) ?? .zero
    return NSSize(width: width, height: ceil(max(0, size.height)))
}

@discardableResult
func referenceFlowRow(_ views: [NSView], x: CGFloat, y: CGFloat, width: CGFloat, in parent: NSView, spacing: CGFloat = 10, trailingLast: Bool = false) -> CGFloat {
    var lines: [[(NSView, NSSize)]] = [[]]
    var used: CGFloat = 0
    for view in views {
        var size = referenceFittingSize(view)
        if size.width > width, let field = view as? NSTextField { size = referenceWrapLabel(field, width: width) }
        if used > 0 && used + spacing + size.width > width {
            lines.append([]); used = 0
        }
        lines[lines.count - 1].append((view, size))
        used += (used > 0 ? spacing : 0) + size.width
    }
    var top = y
    for line in lines where !line.isEmpty {
        let height = line.map { $0.1.height }.max() ?? 22
        var left = x
        for (view, size) in line {
            if trailingLast && view === views.last { left = x + width - size.width }
            referencePlace(view, left, top + (height - size.height) / 2, size.width, size.height, in: parent)
            left += size.width + spacing
        }
        top += height + 8
    }
    return max(0, top - y - 8)
}

final class ReferenceBadge: ReferenceCanvas {
    private let glyph: NSImageView
    private let tint: NSColor
    var iconStyle: AppIconStyle = .color {
        didSet {
            glyph.contentTintColor = iconStyle == .color ? .white : .labelColor
            needsDisplay = true
        }
    }
    init(symbol: String, color: NSColor, size: CGFloat = 22) {
        tint = color
        glyph = NSImageView()
        glyph.image = CrabSymbol.image(named: symbol, size: size * 0.76)
            ?? CrabSymbol.image(forLegacySymbol: symbol, size: size * 0.76)
        glyph.contentTintColor = .white; glyph.imageScaling = .scaleProportionallyDown
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        addSubview(glyph)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    convenience init(icon: CategoryIcon, size: CGFloat = 22) {
        self.init(symbol: icon.symbol, color: icon.color, size: size)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        glyph.needsDisplay = true
    }
    override func layout() { super.layout(); glyph.frame = bounds.insetBy(dx: bounds.width * 0.14, dy: bounds.height * 0.14) }
    override func draw(_ dirtyRect: NSRect) {
        guard iconStyle == .color else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.3, dy: 0.3), xRadius: bounds.width * 0.23, yRadius: bounds.height * 0.23)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGradient(starting: tint.blended(withFraction: dark ? 0.06 : 0.10, of: .white) ?? tint, ending: tint)!.draw(in: path, angle: 90)
        NSColor.white.withAlphaComponent(dark ? 0.16 : 0.12).setStroke()
        path.lineWidth = 0.5; path.stroke()
    }
}

func referenceOpen(_ address: String) {
    if let url = URL(string: address) { NSWorkspace.shared.open(url) }
}
