import AppKit

struct CardSnapshot {
    var summary: String
    var reason: String?
    var image: NSImage?
}

final class OperationOriginBadge: ReferenceCanvas {
    private let naturalWidth: CGFloat
    override var intrinsicContentSize: NSSize { NSSize(width: naturalWidth, height: 18) }

    init(operation: OperationRecord) {
        let label = referenceLabel(operation.isBuiltIn ? "内置" : "自定义", size: 10, weight: .medium, color: .secondaryLabelColor)
        naturalWidth = referenceFittingSize(label).width + 12
        super.init(frame: NSRect(x: 0, y: 0, width: naturalWidth, height: 18))
        fill = NSColor.secondaryLabelColor.withAlphaComponent(0.10); radius = 4
        identifier = .init("operation-origin"); setAccessibilityIdentifier("operation-origin")
        setAccessibilityLabel(label.stringValue)
        referencePlace(label, 6, 2, naturalWidth - 12, 14, in: self)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class OperationCardItem: NSCollectionViewItem {
    private var editAction: (() -> Void)?
    private var commandAction: ((Int) -> Void)?
    override func loadView() { view = ReferenceMaterialCard(frame: NSRect(x: 0, y: 0, width: 620, height: 56)) }
    func configurePicker(_ operation: OperationRecord, snapshot: CardSnapshot?, selected: Bool,
                         toggle: @escaping () -> Void) {
        view.subviews.forEach { $0.removeFromSuperview() }
        editAction = nil; commandAction = nil; view.menu = nil
        view.identifier = .init("operation-picker-card-" + operation.id)
        view.setAccessibilityIdentifier("operation-picker-card-" + operation.id)
        let body = CardBodyButton("", action: toggle)
        body.isBordered = false; body.singleClick = true; body.selectionHighlighted = selected
        body.identifier = .init("operation-picker-toggle-" + operation.id)
        body.setAccessibilityLabel(operation.displayName + ". " + (snapshot?.summary ?? ""))
        body.setAccessibilityValue(selected ? 1 : 0)
        referencePlace(body, 0, 0, 620, 56, in: view)
        let image = NSImageView(); image.image = snapshot?.image
        image.contentTintColor = snapshot?.image?.isTemplate == true ? .labelColor : nil
        referencePlace(image, 14, 16, 24, 24, in: body)
        let title = NSTextField(labelWithString: operation.displayName)
        title.identifier = .init("operation-name"); title.maximumNumberOfLines = 1
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail; title.toolTip = operation.displayName
        referencePlace(title, 48, 8, 532, 18, in: body)
        let type = OperationRegistry.shared.definition(for: operation)?.title ?? "不受当前版本支持"
        let summary = snapshot?.reason ?? snapshot?.summary ?? L("正在读取操作信息…")
        let subtitle = NSTextField(labelWithString: L(type) + " · " + summary)
        subtitle.identifier = .init("operation-summary"); subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = snapshot?.reason == nil ? .secondaryLabelColor : .systemOrange
        subtitle.lineBreakMode = .byTruncatingMiddle; subtitle.toolTip = summary
        let origin = OperationOriginBadge(operation: operation)
        referencePlace(origin, 48, 29, origin.frame.width, 18, in: body)
        let summaryX = origin.frame.maxX + 8
        referencePlace(subtitle, summaryX, 30, 580 - summaryX, 16, in: body)
        let badge = NSImageView(); badge.image = CrabSymbol.image(named: "check", size: 12)
        badge.contentTintColor = .white; badge.imageScaling = .scaleNone
        badge.wantsLayer = true; badge.layer?.cornerRadius = 7
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.identifier = .init("operation-picker-selected-" + operation.id)
        badge.isHidden = !selected
        referencePlace(badge, 590, 8, 20, 20, in: body)
    }
    func configure(_ operation: OperationRecord, snapshot: CardSnapshot?, references: Int, selecting: Bool, selected: Bool,
                   edit: @escaping () -> Void, toggle: @escaping (Bool) -> Void, action: @escaping (Int) -> Void) {
        view.subviews.forEach { $0.removeFromSuperview() }
        editAction = edit; commandAction = action
        let height = max(56, OperationUIRegistry.shared.adapter(operation.parameters.kind)?.cardHeight ?? 56)
        view.setAccessibilityIdentifier("operation-card-" + operation.id)
        let body = CardBodyButton("", action: { [weak self] in
            if selecting {
                guard !operation.isBuiltIn else { return }
                toggle(!selected)
            } else { self?.editAction?() }
        }); body.isBordered = false; body.singleClick = selecting && !operation.isBuiltIn
        body.setAccessibilityLabel(operation.displayName + ". " + (snapshot?.summary ?? ""))
        referencePlace(body, 0, 0, 620, height, in: view)
        let textX: CGFloat = selecting ? 74 : 48
        let image = NSImageView(); image.image = snapshot?.image; image.contentTintColor = snapshot?.image?.isTemplate == true ? .labelColor : nil
        referencePlace(image, textX - 34, (height - 24) / 2, 24, 24, in: body)
        let status = NSTextField(labelWithString: snapshot?.reason ?? (references == 0 ? L("未加入菜单") : LF("已引用 %d 处", references)))
        status.identifier = .init("operation-status"); status.font = .systemFont(ofSize: 11)
        status.textColor = snapshot?.reason == nil ? .secondaryLabelColor : .systemOrange
        status.alignment = .right; status.lineBreakMode = .byTruncatingTail; status.toolTip = status.stringValue
        let statusWidth = min(210, ceil((status.stringValue as NSString).size(withAttributes: [.font: status.font!]).width) + 6)
        referencePlace(status, 606 - statusWidth, 8, statusWidth, 18, in: body)
        let title = NSTextField(labelWithString: operation.displayName)
        title.identifier = .init("operation-name"); title.maximumNumberOfLines = 1
        title.font = .systemFont(ofSize: 13, weight: .semibold); title.toolTip = operation.displayName; title.lineBreakMode = .byTruncatingTail
        referencePlace(title, textX, 8, 606 - statusWidth - 12 - textX, 18, in: body)
        let type = OperationRegistry.shared.definition(for: operation)?.title ?? "不受当前版本支持"
        let subtitle = NSTextField(labelWithString: L(type) + " · " + (snapshot?.summary ?? L("正在读取操作信息…")))
        subtitle.identifier = .init("operation-summary"); subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle; subtitle.toolTip = snapshot?.summary
        let origin = OperationOriginBadge(operation: operation)
        referencePlace(origin, textX, 29, origin.frame.width, 18, in: body)
        let summaryX = origin.frame.maxX + 8
        let width = 606 - summaryX
        referencePlace(subtitle, summaryX, 30, width, 16, in: body)
        if selecting && !operation.isBuiltIn {
            let check = referenceCheck("", value: selected, changed: toggle)
            check.setAccessibilityLabel(L("选择")); check.identifier = .init("operation-select-" + operation.id)
            referencePlace(check, 12, (height - 22) / 2, 20, 22, in: view)
        }
        let menu = NSMenu()
        func command(_ title: String, tag: Int) {
            let item = NSMenuItem(title: L(title), action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag; menu.addItem(item)
        }
        if !operation.isBuiltIn { command("编辑", tag: -1); command("复制", tag: 0) }
        command("加入菜单…", tag: 1)
        if !operation.isBuiltIn { command("删除", tag: 2) }
        body.menu = menu; view.menu = menu
        if let custom = OperationUIRegistry.shared.adapter(operation.parameters.kind)?.makeCardContent {
            let rect = NSRect(x: summaryX, y: 30, width: width, height: height - 38)
            let content = custom(operation, rect); subtitle.removeFromSuperview(); content.frame = rect; body.addSubview(content)
        }
    }
    @objc private func runCommand(_ sender: NSMenuItem) {
        if sender.tag == -1 { editAction?() } else { commandAction?(sender.tag) }
    }
}
private final class CardBodyButton: ClosureButtonBase {
    var singleClick = false
    var selectionHighlighted = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        if selectionHighlighted {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill(); path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke(); path.lineWidth = 1; path.stroke()
        }
        super.draw(dirtyRect)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseDown(with event: NSEvent) { if singleClick || event.clickCount == 2 { performClick(nil) } }
}
class ClosureButtonBase: NSButton {
    private let callback: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        callback = action; super.init(frame: .zero); self.title = title; target = self; self.action = #selector(activate)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { callback() }
}
