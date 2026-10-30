import AppKit

extension AppConfiguration {
    func menuNode(_ id: String) -> MenuNode? {
        for node in menu { if node.id == id { return node }; if let child = node.children.first(where: { $0.id == id }) { return child } }; return nil
    }
    mutating func updateMenuNode(_ id: String, _ change: (inout MenuNode) -> Void) {
        for i in menu.indices {
            if menu[i].id == id { change(&menu[i]); return }
            if let j = menu[i].children.firstIndex(where: { $0.id == id }) { change(&menu[i].children[j]); return }
        }
    }
    mutating func removeMenuNode(_ id: String) {
        menu.removeAll { $0.id == id }; for i in menu.indices { menu[i].children.removeAll { $0.id == id } }
    }
    @discardableResult mutating func resetMenu(groupID: String? = nil) -> Bool {
        let defaults = DefaultMenuLayout.nodes(for: operations)
        guard let groupID else { menu = defaults; return true }
        guard let defaultGroup = defaults.first(where: { $0.id == groupID }),
              let index = menu.firstIndex(where: { $0.id == groupID && $0.kind == .group }) else { return false }
        let previous = menu[index].children
        var usedIDs = Set(menu.flatMap { [$0.id] + ($0.id == groupID ? [] : $0.children.map(\.id)) })
        menu[index].children = defaultGroup.children.map { child in
            var restored = child
            if let existing = previous.first(where: { $0.operationID == child.operationID }) { restored.id = existing.id }
            // A default reference may have been moved to another group. Keep
            // that group untouched and give this replacement its own identity.
            while usedIDs.contains(restored.id) { restored.id = UUID().uuidString }
            usedIDs.insert(restored.id)
            return restored
        }
        return true
    }
    @discardableResult mutating func moveMenuNode(_ id: String, into groupID: String?, at insertion: Int) -> Bool {
        guard let node = menuNode(id), id != groupID else { return false }
        if let groupID { guard node.kind == .operation, menu.first(where: { $0.id == groupID })?.kind == .group else { return false } }
        let oldGroup = menu.first { $0.children.contains { $0.id == id } }?.id
        let oldIndex = oldGroup.flatMap { group in menu.first { $0.id == group }?.children.firstIndex { $0.id == id } } ?? menu.firstIndex { $0.id == id } ?? 0
        var next = self; next.removeMenuNode(id)
        var index = insertion
        if oldGroup == groupID && oldIndex < insertion { index -= 1 }
        if let groupID, let group = next.menu.firstIndex(where: { $0.id == groupID }) {
            next.menu[group].children.insert(node, at: max(0, min(index, next.menu[group].children.count)))
        } else { next.menu.insert(node, at: max(0, min(index, next.menu.count))) }
        guard (try? next.validate()) != nil else { return false }; self = next; return true
    }
}
private final class MenuEmptyHint: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class MenuNameField: NSTextField {
    var nodeID = ""
    var editName: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = MenuNameCell(textCell: "")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if currentEditor() != nil { super.mouseDown(with: event); return }
        if event.clickCount >= 2 { editName?(); return }
        var ancestor = superview
        while let view = ancestor {
            if let table = view as? NSTableView { table.mouseDown(with: event); return }
            ancestor = view.superview
        }
    }
}
private final class MenuNameCell: NSTextFieldCell {
    private static let textLayout = NSLayoutManager()
    private func centered(_ rect: NSRect) -> NSRect {
        var result = rect
        let lineHeight = Self.textLayout.defaultLineHeight(for: font ?? .systemFont(ofSize: 13))
        let height = min(rect.height, ceil(lineHeight))
        result.origin.y = rect.midY - height / 2
        result.size.height = height
        return result
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centered(super.drawingRect(forBounds: rect))
    }
    override func titleRect(forBounds rect: NSRect) -> NSRect { drawingRect(forBounds: rect) }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
        prepareEditor(textObj)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
        prepareEditor(textObj)
    }
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        prepareEditor(editor)
        return editor
    }
    private func prepareEditor(_ editor: NSText) {
        editor.backgroundColor = .clear
        if let view = editor as? NSTextView {
            view.drawsBackground = false
            view.textContainerInset = .zero
        }
    }
}
private final class MenuListTable: NSTableView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is NSButton || responder is MenuNameField { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}
private final class MenuIconButton: ClosureButtonBase {
    var selectRow: (() -> Void)?
    var canEditIcon = true
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if canEditIcon, event.clickCount >= 2 { performClick(nil) } else { selectRow?() }
    }
}
private final class MenuVisibilityButton: NSButton {
    var nodeID = ""
    var trackingChanged: ((Bool) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        trackingChanged?(true)
        defer { trackingChanged?(false) }
        super.mouseDown(with: event)
    }
}
private final class MenuRowCell: NSTableCellView {
    static let iconSize: CGFloat = 28
    static let iconButtonSize: CGFloat = 36
    static let textInset: CGFloat = 40
    weak var iconButton: NSButton?
    weak var detailField: NSTextField?
    weak var visibilityButton: NSButton?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - Self.textInset - 40)
        textField?.setFrameSize(NSSize(width: width, height: 20))
        detailField?.setFrameSize(NSSize(width: width, height: 15))
        iconButton?.setFrameOrigin(NSPoint(x: 0, y: (bounds.height - Self.iconButtonSize) / 2))
        visibilityButton?.setFrameOrigin(NSPoint(x: max(0, bounds.width - 30), y: 10))
    }
}
final class MenuEditorView: ReferenceCanvas, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let store: ConfigurationStore
    private let primary = MenuListTable(), secondary = MenuListTable()
    private let secondaryTitle = NSTextField(labelWithString: "")
    private let secondaryHint = MenuEmptyHint(wrappingLabelWithString: "")
    private var primaryID: String?, secondaryID: String?
    private var reloading = false
    private var committingControl = false
    private var trackingControl = false
    private weak var editingField: MenuNameField?
    private var reloadPending = false
    private var reloadScheduled = false
    private var cancelledRenames = Set<String>()
    private var roots: [MenuNode] = [], children: [MenuNode] = []
    private var reasons: [String: String] = [:]
    private var iconPreviews: [String: OperationPreview] = [:]
    private var iconPicker: NSPopover?
    private var operationPicker: OperationPickerWindowController?
    private var checkedOperations: [OperationRecord] = []
    private var validationGeneration = 0
    private let dragType = NSPasteboard.PasteboardType("dev.crab.operations.v1.menu-node")
    private var primaryRemove: NSButton!
    private var secondaryAdd: NSButton!, secondaryRemove: NSButton!, secondaryReset: NSButton!

    init(store: ConfigurationStore) {
        self.store = store; super.init(frame: .zero)
        let pageWidth = ReferenceStyle.pageWidth
        let columnWidth = (pageWidth - 20) / 2
        let rightX = columnWidth + 20
        let title = referenceLabel("菜单编排", size: 22, weight: .semibold)
        title.identifier = .init("settings-page-title")
        referencePlace(title, 0, 0, pageWidth, 32, in: self)
        referencePlace(referenceLabel("一级菜单", size: 13, weight: .semibold), 0, 48, columnWidth, 24, in: self)
        secondaryTitle.font = .systemFont(ofSize: 13, weight: .semibold); secondaryTitle.lineBreakMode = .byTruncatingTail
        referencePlace(secondaryTitle, rightX, 48, columnWidth, 24, in: self)
        let group = toolbarButton("新建分组", symbol: "folder.badge.plus", fallback: "folder-plus", id: "menu-new-group") { [weak self] in self?.newGroup() }
        let add = toolbarButton("添加操作…", symbol: "plus", fallback: "plus", id: "menu-primary-add") { [weak self] in self?.chooseOperation(groupID: nil) }
        primaryRemove = toolbarButton("移除操作", symbol: "minus", fallback: "minus", id: "menu-primary-remove") { [weak self] in self?.removeSelected(secondary: false) }
        let reset = toolbarButton("重置全部菜单", symbol: "arrow.counterclockwise", fallback: "arrow-back-up", id: "menu-primary-reset") { [weak self] in self?.resetMenu() }
        secondaryAdd = toolbarButton("添加操作…", symbol: "plus", fallback: "plus", id: "menu-secondary-add") { [weak self] in
            guard let self, let groupID = self.selectedGroup?.id else { return }
            self.chooseOperation(groupID: groupID)
        }
        secondaryRemove = toolbarButton("移除操作", symbol: "minus", fallback: "minus", id: "menu-secondary-remove") { [weak self] in self?.removeSelected(secondary: true) }
        secondaryReset = toolbarButton("重置当前分组", symbol: "arrow.counterclockwise", fallback: "arrow-back-up", id: "menu-secondary-reset") { [weak self] in
            guard let self, let groupID = self.selectedGroup?.id else { return }
            self.resetMenu(groupID: groupID)
        }
        let left = ReferenceMaterialCard(frame: NSRect(x: 0, y: 80, width: columnWidth, height: 520))
        let right = ReferenceMaterialCard(frame: NSRect(x: rightX, y: 80, width: columnWidth, height: 520))
        left.identifier = .init("menu-primary-panel"); right.identifier = .init("menu-secondary-panel")
        addSubview(left); addSubview(right)
        placeToolbar([group, add, primaryRemove], reset: reset, in: left)
        placeToolbar([secondaryAdd, secondaryRemove], reset: secondaryReset, in: right)
        let listTop: CGFloat = 50
        setup(primary, in: left, top: listTop, identifier: "menu-primary", label: "一级菜单")
        setup(secondary, in: right, top: listTop, identifier: "menu-secondary", label: "二级菜单")
        secondaryHint.font = .systemFont(ofSize: 12); secondaryHint.textColor = .secondaryLabelColor
        referencePlace(secondaryHint, 14, listTop + 12, right.bounds.width - 28, 80, in: right)
        let help = referenceLabel("拖拽调整顺序或移动菜单项，双击名称或图标修改。", size: 11, color: .secondaryLabelColor)
        let size = referenceWrapLabel(help, width: pageWidth); referencePlace(help, 0, 612, size.width, size.height, in: self)
        if let first = store.configuration.menu.first, first.defaultNameKey != nil { primaryID = first.id }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func toolbarButton(_ title: String, symbol: String, fallback: String, id: String,
                               action: @escaping () -> Void) -> NSButton {
        let button = referenceButton("", action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? CrabSymbol.image(named: fallback, size: 14)
        button.imagePosition = .imageOnly; button.imageScaling = .scaleNone
        button.identifier = .init(id); button.toolTip = L(title); button.setAccessibilityLabel(L(title))
        return button
    }
    private func placeToolbar(_ buttons: [NSButton], reset: NSButton, in panel: NSView) {
        for (index, button) in buttons.enumerated() { referencePlace(button, 12 + CGFloat(index) * 36, 12, 30, 28, in: panel) }
        referencePlace(reset, panel.bounds.width - 42, 12, 30, 28, in: panel)
    }
    private func refreshPrimaryRemove() {
        let node = roots.first { $0.id == primaryID }
        primaryRemove.isEnabled = node != nil
        let title = L(node?.kind == .group ? "移除分组" : "移除操作")
        primaryRemove.toolTip = title; primaryRemove.setAccessibilityLabel(title)
    }
    private func setup(_ table: NSTableView, in panel: NSView, top: CGFloat, identifier: String, label: String) {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        referenceUseOverlayScrollers(scroll)
        let width = max(0, panel.bounds.width - 16)
        referencePlace(scroll, 8, top, width, panel.bounds.height - top - 8, in: panel)
        table.dataSource = self; table.delegate = self; table.headerView = nil; table.rowHeight = 48; table.intercellSpacing = NSSize(width: 0, height: 4)
        table.backgroundColor = .clear; table.usesAlternatingRowBackgroundColors = false
        let column = NSTableColumn(identifier: .init("menu-name")); column.width = width; table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.registerForDraggedTypes([dragType]); table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.target = self; table.doubleAction = #selector(editName(_:)); table.identifier = .init(identifier); table.setAccessibilityLabel(L(label))
        scroll.documentView = table
    }
    private var selectedGroup: MenuNode? { roots.first { $0.id == primaryID && $0.kind == .group } }
    private func isDefaultGroup(_ id: String) -> Bool { DefaultMenuLayout.nodes(for: store.configuration.operations).contains { $0.id == id } }
    private func nodes(_ table: NSTableView) -> [MenuNode] { table === primary ? roots : children }
    func reload() {
        guard !committingControl, !trackingControl, editingField == nil else { reloadPending = true; return }
        reloadPending = false
        let primaryOrigin = primary.enclosingScrollView?.contentView.bounds.origin
        let secondaryOrigin = secondary.enclosingScrollView?.contentView.bounds.origin
        reloading = true; roots = store.configuration.menu
        if !roots.contains(where: { $0.id == primaryID }) { primaryID = nil; secondaryID = nil }
        refreshPrimaryRemove()
        primary.reloadData(); restoreSelection(primary, id: primaryID)
        reloadSecondary()
        for (table, origin) in [(primary, primaryOrigin), (secondary, secondaryOrigin)] {
            if let origin, let scroll = table.enclosingScrollView {
                scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        reloading = false; refreshAvailability()
    }
    private func scheduleReload() {
        reloadPending = true
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloadScheduled = false
            if self.reloadPending { self.reload() }
        }
    }
    private func reloadSecondary() {
        children = selectedGroup?.children ?? []
        if !children.contains(where: { $0.id == secondaryID }) { secondaryID = nil }
        secondary.reloadData(); restoreSelection(secondary, id: secondaryID)
        secondaryTitle.stringValue = L("二级菜单") + (selectedGroup.map { " · " + title($0) } ?? "")
        secondaryTitle.toolTip = secondaryTitle.stringValue
        secondaryAdd.isEnabled = selectedGroup != nil; secondaryRemove.isEnabled = secondaryID != nil
        secondaryReset.isEnabled = selectedGroup.map { isDefaultGroup($0.id) } ?? false
        secondaryHint.stringValue = L(selectedGroup == nil ? "选择左侧分组以编排二级菜单。" : "此分组暂无操作，可添加或拖入操作。")
        secondaryHint.isHidden = !children.isEmpty
    }
    private func restoreSelection(_ table: NSTableView, id: String?) {
        if let index = nodes(table).firstIndex(where: { $0.id == id }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
    }
    private func refreshAvailability() {
        let config = store.configuration
        guard checkedOperations != config.operations else { return }
        checkedOperations = config.operations; validationGeneration += 1; let expected = validationGeneration
        ConfigurationStore.prepareAsync(config, isCancelled: { [weak self] in self?.validationGeneration != expected }) { [weak self] prepared in
            guard let self, self.validationGeneration == expected else { return }
            self.reasons = prepared.previews.compactMapValues { $0.reason.map(L) }; self.iconPreviews = prepared.previews
            self.reload()
        }
    }
    private func title(_ node: MenuNode) -> String {
        node.displayName(operation: node.operationID.flatMap { id in store.configuration.operations.first { $0.id == id } })
    }
    func numberOfRows(in tableView: NSTableView) -> Int { nodes(tableView).count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let node = nodes(tableView)[row]
        let width = tableColumn?.width ?? tableView.bounds.width
        let cell = MenuRowCell(frame: NSRect(x: 0, y: 0, width: width, height: tableView.rowHeight))
        let op = node.operationID.flatMap { id in store.configuration.operations.first { $0.id == id } }
        let field = MenuNameField(frame: .zero); field.stringValue = title(node); field.nodeID = node.id; field.delegate = self
        field.isEditable = false; field.isSelectable = false; field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.cell?.isScrollable = true
        field.refusesFirstResponder = false; field.usesSingleLineMode = true
        field.editName = { [weak self, weak tableView] in
            guard let tableView else { return }; self?.beginNameEditing(nodeID: node.id, in: tableView)
        }
        field.font = .systemFont(ofSize: 13); field.lineBreakMode = .byTruncatingMiddle; field.toolTip = title(node)
        field.textColor = node.visible && op?.enabled != false ? .labelColor : .secondaryLabelColor
        field.identifier = .init("menu-name-" + node.id); field.setAccessibilityLabel(L("显示名称"))
        referencePlace(field, MenuRowCell.textInset, 5, max(0, width - MenuRowCell.textInset - 40), 20, in: cell); cell.textField = field
        var preview = store.configuration; preview.previews = iconPreviews
        let image = MenuIconButton("") { [weak self, weak cell] in
            guard let cell, let anchor = cell.subviews.first(where: { $0.identifier?.rawValue == "menu-icon-" + node.id }) else { return }
            self?.chooseIcon(nodeID: node.id, anchor: anchor)
        }
        image.selectRow = { [weak tableView] in tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        image.canEditIcon = canEditIcon(for: node)
        image.identifier = .init("menu-icon-" + node.id)
        image.setAccessibilityLabel(L(image.canEditIcon ? "选择菜单图标" : "图标") + " · " + title(node))
        image.toolTip = image.canEditIcon ? L("双击更换图标") : nil
        image.bezelStyle = .regularSquare; image.isBordered = false
        image.image = MenuNodeIcons.image(node: node, operation: op, configuration: preview, size: MenuRowCell.iconSize, allowFileRead: false)
            ?? CrabSymbol.image(named: node.iconID == MenuNodeIcons.hiddenID ? "eye-off" : "photo", size: MenuRowCell.iconSize)
        image.imagePosition = .imageOnly; image.imageScaling = .scaleNone
        image.contentTintColor = image.image?.isTemplate == true ? .secondaryLabelColor : nil
        referencePlace(image, 0, (cell.bounds.height - MenuRowCell.iconButtonSize) / 2,
                       MenuRowCell.iconButtonSize, MenuRowCell.iconButtonSize, in: cell)
        cell.iconButton = image
        let status: String
        if !node.visible { status = L("已隐藏") }
        else if node.kind == .group { status = LF("%d 个操作", node.children.count) }
        else if let op { status = !op.enabled ? L("已停用") : reasons[op.id] ?? L(OperationRegistry.shared.definition(for: op)?.title ?? "不受当前版本支持") }
        else { status = L("操作引用已失效") }
        let detail = NSTextField(labelWithString: status); detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail; detail.toolTip = status
        referencePlace(detail, MenuRowCell.textInset, 27, max(0, width - MenuRowCell.textInset - 40), 15, in: cell); cell.detailField = detail
        let visible = MenuVisibilityButton(checkboxWithTitle: "", target: self, action: #selector(toggleVisibility(_:)))
        visible.nodeID = node.id; visible.state = node.visible ? .on : .off
        visible.trackingChanged = { [weak self] tracking in
            guard let self else { return }
            self.trackingControl = tracking
            if !tracking, self.reloadPending { self.scheduleReload() }
        }
        visible.identifier = .init("menu-visible-" + node.id); visible.setAccessibilityLabel(L("显示在菜单中")); visible.toolTip = L("显示在菜单中")
        referencePlace(visible, max(0, width - 30), 10, 24, 26, in: cell); cell.visibilityButton = visible
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, let table = notification.object as? NSTableView else { return }
        if table === primary {
            primaryID = roots.indices.contains(table.selectedRow) ? roots[table.selectedRow].id : nil
            refreshPrimaryRemove()
            secondaryID = nil; reloading = true; reloadSecondary(); reloading = false
        } else { secondaryID = children.indices.contains(table.selectedRow) ? children[table.selectedRow].id : nil; secondaryRemove.isEnabled = secondaryID != nil }
    }
    @objc private func editName(_ sender: NSTableView) {
        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard nodes(sender).indices.contains(row) else { return }
        beginNameEditing(nodeID: nodes(sender)[row].id, in: sender)
    }
    private func beginNameEditing(nodeID: String, in table: NSTableView) {
        if editingField?.nodeID == nodeID { return }
        if editingField != nil { window?.makeFirstResponder(table) }
        guard let row = nodes(table).firstIndex(where: { $0.id == nodeID }),
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField as? MenuNameField else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        cancelledRenames.remove(field.nodeID)
        editingField = field
        field.isEditable = true; field.isSelectable = true
        field.refusesFirstResponder = false; field.selectText(nil)
        if field.currentEditor() == nil { editingField = nil }
    }
    @discardableResult func renameNode(_ id: String, name: String) -> Bool {
        guard let node = store.configuration.menuNode(id) else { return false }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = value.isEmpty ? nil : value
        guard next != node.name, value != title(node) else { return true }
        return store.update { $0.updateMenuNode(id) { $0.name = next } }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? MenuNameField else { return }
        committingControl = true
        editingField = nil
        if cancelledRenames.remove(field.nodeID) == nil { _ = renameNode(field.nodeID, name: field.stringValue) }
        field.isEditable = false; field.isSelectable = false
        committingControl = false
        scheduleReload()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)), let field = control as? MenuNameField else { return false }
        cancelledRenames.insert(field.nodeID)
        field.stringValue = store.configuration.menuNode(field.nodeID).map(title) ?? ""
        window?.makeFirstResponder(primary); return true
    }
    private func canEditIcon(for node: MenuNode) -> Bool {
        if let operation = store.configuration.operations.first(where: { $0.id == node.operationID }),
           case .image = operation.parameters { return false }
        return true
    }
    @discardableResult func setIcon(_ iconID: String?, for nodeID: String) -> Bool {
        guard let node = store.configuration.menuNode(nodeID), canEditIcon(for: node),
              iconID == nil || iconID == MenuNodeIcons.hiddenID || MenuNodeIcons.catalog.contains(where: { $0.id == iconID }) else { return false }
        let saved = store.update { $0.updateMenuNode(nodeID) { $0.iconID = iconID } }
        reload(); return saved
    }
    private func chooseIcon(nodeID: String, anchor: NSView) {
        guard let node = store.configuration.menuNode(nodeID), canEditIcon(for: node) else { return }
        iconPicker?.close()
        let popover = CatalogIconPicker.make(title: "选择菜单图标", selectedID: node.iconID, style: store.configuration.iconStyle) { [weak self] id in
            if self?.setIcon(id, for: nodeID) == true { self?.iconPicker?.close() }
        }
        popover.appearance = window?.effectiveAppearance; iconPicker = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }
    @objc private func toggleVisibility(_ sender: MenuVisibilityButton) {
        guard let node = store.configuration.menuNode(sender.nodeID) else { return }
        let visible = sender.state == .on
        committingControl = true
        let saved = store.update { $0.updateMenuNode(node.id) { $0.visible = visible } }
        sender.state = (saved ? visible : node.visible) ? .on : .off
        committingControl = false
        scheduleReload()
    }
    private func newGroup() {
        window?.makeFirstResponder(primary)
        let node = MenuNode(kind: .group, name: L("新建分组"))
        guard store.update({ $0.menu.append(node) }) else { return }
        primaryID = node.id; secondaryID = nil; reload()
        primary.scrollRowToVisible(roots.count - 1)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.primaryID == node.id else { return }
            self.beginNameEditing(nodeID: node.id, in: self.primary)
        }
    }
    private func resetMenu(groupID: String? = nil) {
        guard window?.attachedSheet == nil else { return }
        if let groupID { guard isDefaultGroup(groupID), store.configuration.menu.first(where: { $0.id == groupID })?.kind == .group else { return } }
        window?.makeFirstResponder(primary)
        let reset: () -> Void = { [weak self] in
            guard let self else { return }
            if let groupID { guard self.isDefaultGroup(groupID), self.store.configuration.menu.first(where: { $0.id == groupID })?.kind == .group else { return } }
            guard self.store.update({ _ = $0.resetMenu(groupID: groupID) }) else { return }
            self.primaryID = groupID ?? self.store.configuration.menu.first?.id; self.secondaryID = nil
            self.reload()
        }
        if groupID == nil, store.configuration.menu.isEmpty { reset(); return }
        guard let window else { return }
        let message = groupID == nil ? "将全部菜单恢复为默认编排。操作库内容保持不变。" : "将此分组下的操作恢复为默认编排。其他分组保持不变。"
        WindowDialogs.confirm(title: groupID == nil ? "重置全部菜单" : "重置当前分组", message: message,
                              button: "重置", for: window, store: store) { confirmed in
            if confirmed { reset() }
        }
    }
    private func chooseOperation(groupID: String?) {
        guard let window, window.attachedSheet == nil else { return }
        if let groupID { guard store.configuration.menu.first(where: { $0.id == groupID })?.kind == .group else { return } }
        let picker = OperationPickerWindowController(store: store)
        operationPicker = picker
        picker.didClose = { [weak self, weak picker] in
            guard let self, self.operationPicker === picker else { return }
            self.operationPicker = nil
        }
        let store = self.store
        picker.present(asSheetFor: window) { [weak self] ids in
            let validIDs = ids.filter { id in store.configuration.operations.contains { $0.id == id } }
            guard !validIDs.isEmpty else { return }
            if let groupID { guard store.configuration.menu.first(where: { $0.id == groupID })?.kind == .group else { return } }
            store.update { config in
                let references = validIDs.filter { id in config.operations.contains { $0.id == id } }.map(MenuNode.reference)
                if let groupID {
                    guard let index = config.menu.firstIndex(where: { $0.id == groupID && $0.kind == .group }) else { return }
                    config.menu[index].children += references
                } else { config.menu += references }
            }; self?.reload()
        }
    }
    private func removeSelected(secondary: Bool) {
        guard let id = secondary ? secondaryID : primaryID, let node = store.configuration.menuNode(id) else { return }
        let remove: () -> Void = { [weak self] in
            guard let self, self.store.configuration.menuNode(id) != nil else { return }
            self.store.update { $0.removeMenuNode(id) }
            if secondary { self.secondaryID = nil } else { self.primaryID = nil; self.secondaryID = nil }; self.reload()
        }
        if node.kind == .group {
            guard let window else { return }
            WindowDialogs.confirm(title: "移除分组", message: "仅移除此分组及菜单引用，操作库内容保持不变。", button: "移除", for: window, store: store) { confirmed in
                if confirmed { remove() }
            }
        } else { remove() }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard nodes(tableView).indices.contains(row) else { return nil }
        let data = NSPasteboardItem(); data.setString(nodes(tableView)[row].id, forType: dragType); return data
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard let source = info.draggingSource as? NSTableView, source === primary || source === secondary,
              let id = info.draggingPasteboard.string(forType: dragType), let node = store.configuration.menuNode(id) else { return [] }
        if tableView === secondary { guard selectedGroup != nil, node.kind == .operation else { return [] }; tableView.setDropRow(row, dropOperation: .above); return .move }
        if operation == .on, roots.indices.contains(row), roots[row].kind == .group { return node.kind == .operation ? .move : [] }
        tableView.setDropRow(row, dropOperation: .above); return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let source = info.draggingSource as? NSTableView, source === primary || source === secondary,
              let id = info.draggingPasteboard.string(forType: dragType) else { return false }
        let groupID: String?, index: Int
        if tableView === secondary { guard let group = selectedGroup else { return false }; groupID = group.id; index = row }
        else if dropOperation == .on, roots.indices.contains(row), roots[row].kind == .group { groupID = roots[row].id; index = roots[row].children.count }
        else { groupID = nil; index = row }
        return moveNode(id, into: groupID, at: index)
    }
    @discardableResult func moveNode(_ id: String, into groupID: String?, at index: Int) -> Bool {
        var moved = false
        let saved = store.update { moved = $0.moveMenuNode(id, into: groupID, at: index) }
        if saved && moved { primaryID = groupID ?? id; secondaryID = groupID == nil ? nil : id }
        reload(); return saved && moved
    }
    static func addReferences(ids: [String], store: ConfigurationStore, for window: NSWindow) {
        guard !ids.isEmpty else { return }
        let groups = store.configuration.menu.filter { $0.kind == .group }
        let alert = NSAlert(); alert.messageText = L("加入菜单…")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28)); popup.addItems(withTitles: [L("一级菜单")] + groups.map { $0.displayName() })
        alert.accessoryView = popup; alert.addButton(withTitle: L("添加")); alert.addButton(withTitle: L("取消"))
        WindowDialogs.present(alert, for: window, store: store) { response in
            let selected = popup.indexOfSelectedItem
            guard response == .alertFirstButtonReturn, selected == 0 || groups.indices.contains(selected - 1) else { return }
            let groupID = selected == 0 ? nil : groups[selected - 1].id
            store.update { config in
                let valid = ids.filter { id in config.operations.contains { $0.id == id } }.map(MenuNode.reference)
                if let groupID { if let index = config.menu.firstIndex(where: { $0.id == groupID && $0.kind == .group }) { config.menu[index].children += valid } }
                else { config.menu += valid }
            }
        }
    }

}
