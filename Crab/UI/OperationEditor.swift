import AppKit
import UniformTypeIdentifiers

final class OperationEditor: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let store: ConfigurationStore
    private(set) var draft: OperationRecord
    var isReadOnly: Bool { draft.isBuiltIn }
    var canEditIcon: Bool {
        guard !isReadOnly else { return false }
        switch draft.parameters {
        case .application, .image: return false
        default: return true
        }
    }
    private let existingID: String?
    private var bindings: [String: (String) -> Void] = [:]
    private var y: CGFloat = 20
    private let editorWidth: CGFloat = 460
    private let inset: CGFloat = 18
    private var fieldWidth: CGFloat { editorWidth - inset * 2 - 16 }
    private let body = ReferenceCanvas()
    private let scroll = NSScrollView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var cancelButton: NSButton!
    private var saveButton: NSButton?
    private var iconButton: NSButton?
    private var iconPicker: NSPopover?
    var didSave: (() -> Void)?

    init(operation: OperationRecord, existing: Bool, store: ConfigurationStore) {
        self.draft = operation; self.existingID = existing ? operation.id : nil; self.store = store
        if !operation.isBuiltIn, !existing, self.draft.iconID == nil { self.draft.iconID = OperationImages.defaultIconID(for: operation.parameters.kind) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L(operation.isBuiltIn ? "查看操作" : existing ? "编辑操作" : "新增操作…"); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self; WindowAppearance.bind(window, to: store)
        let root: ReferenceCanvas = isReadOnly ? UnfocusedContentCanvas(color: .windowBackgroundColor) : ReferenceCanvas(color: .windowBackgroundColor)
        window.contentView = root
        if isReadOnly { window.initialFirstResponder = root }
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        referenceUseOverlayScrollers(scroll)
        scroll.drawsBackground = false; scroll.documentView = body; root.addSubview(scroll)
        errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .systemRed
        root.addSubview(errorLabel)
        let cancel = referenceButton(isReadOnly ? "关闭" : "取消") { [weak self] in self?.close() }; cancel.keyEquivalent = "\u{1b}"
        cancel.identifier = .init(isReadOnly ? "operation-close" : "operation-cancel")
        cancelButton = cancel; root.addSubview(cancel)
        if isReadOnly { window.defaultButtonCell = cancel.cell as? NSButtonCell }
        else {
            let save = referenceButton("保存") { [weak self] in self?.save() }; save.keyEquivalent = "\r"; save.identifier = .init("operation-save")
            saveButton = save; root.addSubview(save)
        }
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    func present(asSheetFor parent: NSWindow) {
        guard let window, parent.attachedSheet == nil, window.sheetParent == nil else { return }
        if isReadOnly { window.makeFirstResponder(window.contentView) }
        parent.beginSheet(window) { [weak self] _ in self?.window?.orderOut(nil) }
        if isReadOnly { window.makeFirstResponder(window.contentView) }
    }
    override func close() { dismiss(response: .cancel) }
    private func dismiss(response: NSApplication.ModalResponse) {
        iconPicker?.close()
        guard let window else { return }
        if let parent = window.sheetParent { parent.endSheet(window, returnCode: response) }
        else { super.close() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.sheetParent != nil else { return true }
        close(); return false
    }
    private func rebuild() {
        body.subviews.forEach { $0.removeFromSuperview() }; bindings = [:]; y = inset
        if !canEditIcon {
            let image = NSImageView()
            image.identifier = .init("operation-icon"); image.setAccessibilityLabel(L("图标"))
            image.image = OperationImages.image(draft, configuration: store.configuration, size: 36) ?? CrabSymbol.image(named: "eye-off", size: 30)
            image.imageScaling = .scaleProportionallyDown
            image.contentTintColor = image.image?.isTemplate == true ? .labelColor : nil
            referencePlace(image, inset, y, 46, 46, in: body); iconButton = nil
        } else {
            let button = referenceButton("") { [weak self] in self?.chooseIcon() }
            button.identifier = .init("operation-icon"); button.bezelStyle = .regularSquare; button.imagePosition = .imageOnly
            button.setAccessibilityLabel(L("修改图标")); button.toolTip = L("修改图标")
            referencePlace(button, inset, y, 46, 46, in: body); iconButton = button; refreshIcon()
        }
        let nameX = inset + 62
        let name = text("名称", value: isReadOnly ? draft.displayName : draft.name ?? "", placeholder: draft.displayName, leading: nameX, showsLabel: false) { [weak self] value in self?.draft.name = value.isEmpty ? nil : value }
        name.identifier = .init("operation-name")
        if isReadOnly {
            name.font = .systemFont(ofSize: 18, weight: .semibold)
            name.lineBreakMode = .byTruncatingTail; name.toolTip = draft.displayName
            window?.contentView?.nextKeyView = name
        }
        let badge = OperationOriginBadge(operation: draft)
        referencePlace(badge, nameX, inset + 33, badge.frame.width, 18, in: body)
        if let definition = OperationRegistry.shared.definition(for: draft) {
            let description = L(definition.title) + (isReadOnly ? " · " + L("只读") : "")
            let type = NSTextField(labelWithString: description); type.font = .systemFont(ofSize: 11); type.textColor = .secondaryLabelColor
            type.lineBreakMode = .byTruncatingTail; type.toolTip = description
            referencePlace(type, badge.frame.maxX + 8, inset + 33, fieldWidth - 62 - badge.frame.width - 8, 18, in: body)
        }
        y = inset + (isReadOnly ? 62 : 70)
        OperationUIRegistry.shared.adapter(draft.parameters.kind)?.fields(self)
        layoutEditor()
    }
    private func layoutEditor() {
        guard let window else { return }
        let errorHeight: CGFloat = errorLabel.stringValue.isEmpty ? 0 : referenceWrapLabel(errorLabel, width: editorWidth - inset * 2).height + 10
        let footerHeight: CGFloat = (isReadOnly ? 54 : 58) + errorHeight
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let minimumHeight: CGFloat = isReadOnly ? 86 : 140
        let bodyHeight = min(max(minimumHeight, y + 6), max(minimumHeight, min(420, available - footerHeight - 100)))
        window.setContentSize(NSSize(width: editorWidth, height: bodyHeight + footerHeight))
        scroll.frame = NSRect(x: 0, y: 0, width: editorWidth, height: bodyHeight)
        body.setFrameSize(NSSize(width: editorWidth - 16, height: max(bodyHeight, y + 6)))
        errorLabel.isHidden = errorHeight == 0
        errorLabel.frame = NSRect(x: inset, y: bodyHeight + 2, width: editorWidth - inset * 2, height: max(0, errorHeight - 10))
        let cancelWidth = max(80, referenceFittingSize(cancelButton).width)
        let buttonY = bodyHeight + errorHeight + 12
        if let saveButton {
            let saveWidth = max(80, referenceFittingSize(saveButton).width)
            saveButton.frame = NSRect(x: editorWidth - inset - saveWidth, y: buttonY, width: saveWidth, height: 30)
            cancelButton.frame = NSRect(x: saveButton.frame.minX - 10 - cancelWidth, y: buttonY, width: cancelWidth, height: 30)
        } else {
            cancelButton.frame = NSRect(x: editorWidth - inset - cancelWidth, y: buttonY, width: cancelWidth, height: 30)
        }
    }
    private func refreshIcon() {
        iconButton?.image = OperationImages.image(draft, configuration: store.configuration, size: 28) ?? CrabSymbol.image(named: "eye-off", size: 24)
        iconButton?.contentTintColor = iconButton?.image?.isTemplate == true ? .labelColor : nil
    }
    @discardableResult func setIcon(_ id: String?) -> Bool {
        guard canEditIcon, let id,
              id == MenuNodeIcons.hiddenID || MenuNodeIcons.catalog.contains(where: { $0.id == id }) else { return false }
        draft.iconID = id
        refreshIcon(); return true
    }
    private func chooseIcon() {
        guard canEditIcon, let anchor = iconButton else { return }
        iconPicker?.close()
        let popover = CatalogIconPicker.make(title: "选择图标", selectedID: draft.iconID, style: store.configuration.iconStyle, allowsDefault: false) { [weak self] id in
            if self?.setIcon(id) == true { self?.iconPicker?.close() }
        }
        popover.appearance = window?.effectiveAppearance; iconPicker = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }
    private func showError(_ message: String) {
        errorLabel.stringValue = message; layoutEditor()
    }
    func controlTextDidChange(_ obj: Notification) {
        guard !isReadOnly, let field = obj.object as? NSTextField, let key = field.identifier?.rawValue else { return }
        bindings[key]?(field.stringValue)
    }
    func updateDraft(_ change: (inout OperationRecord) -> Void) { if !isReadOnly { change(&draft) } }
    func content(_ view: NSView, height: CGFloat) {
        referencePlace(view, inset, y, fieldWidth, height, in: body); y += height + 10
    }
    @discardableResult func text(_ title: String, value: String, placeholder: String = "", leading: CGFloat? = nil, showsLabel: Bool = true, changed: @escaping (String) -> Void) -> NSTextField {
        if isReadOnly, showsLabel { return readOnlyValue(title, value: value) }
        let x = leading ?? inset, width = fieldWidth - (x - inset)
        if showsLabel {
            let label = referenceLabel(title, size: 12); referencePlace(label, x, y, width, 20, in: body); y += 23
        }
        let field = NSTextField(string: value); field.font = .systemFont(ofSize: 13); field.placeholderString = placeholder
        let key = title == "名称" ? "operation-name" : UUID().uuidString
        field.identifier = .init(key); bindings[key] = changed; field.delegate = self
        if isReadOnly { field.isEditable = false; field.isSelectable = true; field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none }
        field.setAccessibilityLabel(L(title)); referencePlace(field, x, y, width, 26, in: body); y += 34
        return field
    }
    func toggle(_ title: String, value: Bool, changed: @escaping (Bool) -> Void) {
        if isReadOnly { readOnlyValue(title, value: L(value ? "已启用" : "未启用")); return }
        let check = referenceCheck(title, value: value) { [weak self] value in if self?.isReadOnly == false { changed(value) } }
        check.isEnabled = !isReadOnly
        let size = referenceWrapButton(check, width: fieldWidth)
        referencePlace(check, inset, y, size.width, size.height, in: body); y += size.height + 10
    }
    func choice(_ title: String, titles: [String], selected: Int, changed: @escaping (Int) -> Void) {
        if isReadOnly {
            readOnlyValue(title, value: titles.indices.contains(selected) ? L(titles[selected]) : "")
            return
        }
        referencePlace(referenceLabel(title, size: 12), inset, y, fieldWidth, 20, in: body); y += 23
        let popup = ActionPopup(titles: titles.map(L), selected: selected) { [weak self] index in if self?.isReadOnly == false { changed(index) } }
        popup.isEnabled = !isReadOnly
        popup.setAccessibilityLabel(L(title)); referencePlace(popup, inset, y, fieldWidth, 28, in: body); y += 36
    }
    @discardableResult private func readOnlyValue(_ title: String, value: String) -> NSTextField {
        let row = ReferenceCanvas(color: .controlBackgroundColor, radius: 10)
        row.identifier = .init("operation-detail-row")
        let label = referenceLabel(title, size: 12, color: .secondaryLabelColor)
        let labelWidth = min(174, fieldWidth * 0.44)
        let labelSize = referenceWrapLabel(label, width: labelWidth)
        let height = max(44, labelSize.height + 20)
        referencePlace(label, 12, (height - labelSize.height) / 2, labelWidth, labelSize.height, in: row)
        let field = NSTextField(labelWithString: value)
        field.identifier = .init("operation-detail-value-" + title); field.delegate = self
        field.font = .systemFont(ofSize: 13, weight: .medium); field.alignment = .right
        field.isSelectable = true; field.focusRingType = .none
        field.lineBreakMode = .byTruncatingMiddle; field.toolTip = value
        field.setAccessibilityLabel(L(title))
        referencePlace(field, label.frame.maxX + 12, (height - 22) / 2, fieldWidth - labelWidth - 36, 22, in: row)
        referencePlace(row, inset, y, fieldWidth, height, in: body); y += height + 8
        return field
    }
    func file(_ title: String, value: String, directories: Bool = false, application: Bool = false, changed: @escaping (String) -> Void) {
        let field = text(title, value: value, changed: changed)
        field.lineBreakMode = .byTruncatingMiddle; field.toolTip = value
        guard !isReadOnly else { return }
        let button = referenceButton("选择…") { [weak self] in
            guard let self, !self.isReadOnly, let window = self.window else { return }
            let panel = NSOpenPanel(); panel.canChooseDirectories = directories; panel.canChooseFiles = !directories
            panel.allowsMultipleSelection = false
            if application { panel.allowedContentTypes = [.applicationBundle] }
            WindowDialogs.present(panel, for: window, store: self.store) { [weak self] response in
                guard response == .OK, let url = panel.url, let self else { return }
                changed(url.path); self.rebuild()
            }
        }
        let buttonWidth = max(84, referenceFittingSize(button).width)
        field.setFrameSize(NSSize(width: fieldWidth - buttonWidth - 8, height: field.frame.height))
        referencePlace(button, field.frame.maxX + 8, field.frame.minY - 1, buttonWidth, 28, in: body)
    }
    func toolFields() {
        guard case .tool(let parameters) = draft.parameters else { return }
        let actions = ToolAction.displayOrder.filter { $0.applicationID == nil }
        if !isReadOnly {
            choice(OperationRegistry.shared.definition(for: draft)?.title ?? "工具操作", titles: actions.map(\.title), selected: actions.firstIndex(of: parameters.action) ?? 0) { [weak self] index in
                self?.draft.parameters = .tool(.init(action: actions[index])); self?.rebuild()
            }
        }
        if parameters.action == .cut {
            toggle("剪切时隐藏选中的文件", value: parameters.hideOriginals) { [weak self] value in
                var p = parameters; p.hideOriginals = value; self?.draft.parameters = .tool(p)
            }
        }
        if parameters.action == .deletePermanently {
            toggle("需要再次确认", value: parameters.confirmDeletion) { [weak self] value in
                var p = parameters; p.confirmDeletion = value; self?.draft.parameters = .tool(p)
            }
        }
    }
    func templateFields() {
        guard case .template(let p) = draft.parameters else { return }
        let suffix = isReadOnly && p.template.suffix.isEmpty ? L("自定义文件格式") : p.template.suffix
        text("后缀", value: suffix) { [weak self] value in
            guard let self, case .template(var current) = self.draft.parameters else { return }; current.template.suffix = value; self.draft.parameters = .template(current)
        }
        let templatePath = p.template.importedPath ?? p.template.resourceName.map { Bundle.main.url(forResource: $0, withExtension: nil)?.path ?? $0 }
        if !isReadOnly || templatePath != nil {
            file(isReadOnly ? "模板文件" : "模板文件（可选）", value: templatePath ?? "") { [weak self] value in
                guard let self, case .template(var current) = self.draft.parameters else { return }; current.template.importedPath = value.isEmpty ? nil : value; current.template.resourceName = nil; self.draft.parameters = .template(current)
            }
        }
        if templatePath == nil, !isReadOnly || !p.template.contents.isEmpty {
            text("内置内容", value: p.template.contents) { [weak self] value in
                guard let self, case .template(var current) = self.draft.parameters else { return }; current.template.contents = value; self.draft.parameters = .template(current)
            }
        }
        toggle("新建文件后自动打开", value: p.autoOpen) { [weak self] value in
            guard let self, case .template(var current) = self.draft.parameters else { return }; current.autoOpen = value; self.draft.parameters = .template(current)
        }
        toggle("开启提示音", value: p.playSound) { [weak self] value in
            guard let self, case .template(var current) = self.draft.parameters else { return }; current.playSound = value; self.draft.parameters = .template(current)
        }
    }
    func transferFields() {
        guard case .transfer(let p) = draft.parameters else { return }
        choice("传送方式", titles: ["复制到", "移动到"], selected: p.move ? 1 : 0) { [weak self] index in
            guard let self, case .transfer(var current) = self.draft.parameters else { return }; current.move = index == 1; self.draft.parameters = .transfer(current)
        }
        toggle("每次选择目标目录", value: p.target == nil) { [weak self] value in
            guard let self, case .transfer(var current) = self.draft.parameters else { return }; current.target = value ? nil : ""; self.draft.parameters = .transfer(current); self.rebuild()
        }
        if let path = p.target {
            file("目标目录", value: path, directories: true) { [weak self] value in
                guard let self, case .transfer(var current) = self.draft.parameters else { return }; current.target = value; self.draft.parameters = .transfer(current)
            }
        }
    }
    func directoryFields() {
        guard case .directory(let path) = draft.parameters else { return }
        file("目标目录", value: path, directories: true) { [weak self] value in self?.draft.parameters = .directory(value) }
    }
    func applicationFields() {
        guard case .application(let p) = draft.parameters else { return }
        let path = p.path ?? (isReadOnly ? OperationRegistry.applicationURL(p)?.path ?? L("应用不可用") : "")
        file("应用位置", value: path, application: true) { [weak self] value in
            guard let self, case .application(var current) = self.draft.parameters else { return }; current.path = value.isEmpty ? nil : value; self.draft.parameters = .application(current)
        }
        if let id = p.catalogID, ["terminal", "iterm2"].contains(id) {
            toggle("在新标签页里打开", value: p.newTab) { [weak self] value in
                guard let self, case .application(var current) = self.draft.parameters else { return }; current.newTab = value; self.draft.parameters = .application(current)
            }
        }
    }
    func imageFields() {
        guard case .image(let p) = draft.parameters else { return }
        let definitions = SystemIconDefaults.catalog
        let selected = p.remove ? 1 : p.systemID == nil ? 0 : 2 + (definitions.firstIndex { $0.id == p.systemID } ?? 0)
        choice("图标来源", titles: ["自定义图片", "移除自定义图标"] + definitions.map(\.name), selected: selected) { [weak self] index in
            var next = ImageParameters()
            if index == 1 { next.remove = true }
            if index >= 2 { next.systemID = definitions[index - 2].id }
            self?.draft.parameters = .image(next); self?.rebuild()
        }
        if !p.remove && p.systemID == nil {
            file("图片文件", value: p.path ?? "") { [weak self] value in self?.draft.parameters = .image(.init(path: value)) }
        }
    }
    func scriptFields() {
        guard case .script(let path) = draft.parameters else { return }
        file("脚本路径", value: path) { [weak self] value in self?.draft.parameters = .script(value) }
        let info = referenceLabel("脚本仅引用原文件，不修改内容或执行权限。", size: 11, color: .secondaryLabelColor)
        let size = referenceWrapLabel(info, width: fieldWidth); referencePlace(info, inset, y, size.width, size.height, in: body); y += size.height + 10
    }
    @discardableResult func save() -> Bool {
        guard !isReadOnly else { return false }
        window?.makeFirstResponder(nil)
        guard !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let definition = OperationRegistry.shared.definition(for: draft) else { showError(L("配置无效")); return false }
        if let error = definition.validation(draft) { showError(L(error)); return false }
        if case .template(let p) = draft.parameters, p.template.suffix.contains(where: { "/\\\0".contains($0) }) {
            showError(L("配置无效")); return false
        }
        var next = draft
        var created: [URL] = []
        do {
            func imported(_ path: String) throws -> String {
                let url = URL(fileURLWithPath: path)
                if url.deletingLastPathComponent().standardizedFileURL == store.assetsDirectory.standardizedFileURL { return path }
                let result = try store.importAsset(url); created.append(result); return result.path
            }
            if case .template(var p) = next.parameters, let path = p.template.importedPath { p.template.importedPath = try imported(path); next.parameters = .template(p) }
            if case .image(var p) = next.parameters, let path = p.path { p.path = try imported(path); next.parameters = .image(p) }
            if let existingID, !store.configuration.operations.contains(where: { $0.id == existingID }) { throw CocoaError(.fileNoSuchFile) }
            let success = store.update { config in
                if let existingID, let index = config.operations.firstIndex(where: { $0.id == existingID }) { config.operations[index] = next }
                else { config.operations.append(next) }
            }
            guard success else { throw NSError(domain: "Crab", code: 1, userInfo: [NSLocalizedDescriptionKey: store.lastError ?? L("保存失败")]) }
            draft = next; didSave?(); dismiss(response: .OK); return true
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            showError(error.localizedDescription); return false
        }
    }
}

enum CatalogIconPicker {
    static func make(title: String, selectedID: String?, style: AppIconStyle, allowsDefault: Bool = true, selected: @escaping (String?) -> Void) -> NSPopover {
        let popover = NSPopover(); popover.behavior = .transient
        let controller = NSViewController()
        let root = ReferenceCanvas(frame: NSRect(x: 0, y: 0, width: 360, height: 350)); controller.view = root
        referencePlace(referenceLabel(title, size: 13, weight: .semibold), 12, 10, 336, 24, in: root)
        let hidden = referenceButton("不显示图标") { selected(MenuNodeIcons.hiddenID) }
        hidden.identifier = .init("catalog-icon-hidden")
        var controls: [NSButton] = []
        if allowsDefault {
            let defaults = referenceButton("使用默认图标") { selected(nil) }
            defaults.identifier = .init("catalog-icon-default")
            controls.append(defaults)
        }
        controls.append(hidden)
        let controlsHeight = referenceFlowRow(controls, x: 12, y: 40, width: 336, in: root)
        let gridTop = 40 + controlsHeight + 12
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        referenceUseOverlayScrollers(scroll)
        referencePlace(scroll, 10, gridTop, 340, 338 - gridTop, in: root)
        let entries = MenuNodeIcons.catalog, columns = 8
        let grid = ReferenceCanvas(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat((entries.count + columns - 1) / columns) * 40))
        for (index, entry) in entries.enumerated() {
            let button = ClosureButtonBase("") { selected(entry.id) }
            button.image = MenuNodeIcons.catalogImage(entry.id, style: style, size: 24); button.imagePosition = .imageOnly
            button.bezelStyle = .regularSquare; button.setButtonType(.pushOnPushOff); button.state = selectedID == entry.id ? .on : .off
            button.identifier = .init("catalog-icon-" + entry.id); button.setAccessibilityLabel(entry.title); button.toolTip = entry.title
            referencePlace(button, CGFloat(index % columns) * 40, CGFloat(index / columns) * 40, 36, 36, in: grid)
        }
        scroll.documentView = grid; popover.contentViewController = controller
        return popover
    }
}
final class ActionPopup: NSPopUpButton {
    private let changed: (Int) -> Void
    init(titles: [String], selected: Int, pullsDown: Bool = false, changed: @escaping (Int) -> Void) {
        self.changed = changed; super.init(frame: .zero, pullsDown: pullsDown)
        addItems(withTitles: titles); if titles.indices.contains(selected) { selectItem(at: selected) }
        target = self; action = #selector(updateChoice)

    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func updateChoice() { changed(indexOfSelectedItem) }
}
func referenceWrapButton(_ button: NSButton, width: CGFloat) -> NSSize {
    button.cell?.wraps = true; button.cell?.lineBreakMode = .byWordWrapping
    let natural = referenceFittingSize(button)
    return NSSize(width: min(width, natural.width), height: natural.width > width ? natural.height * ceil(natural.width / width) : natural.height)
}

final class OperationAddButton: NSButton {
    private let choose: (Int) -> Void
    init(title: String = "新增操作…", titles: [String], choose: @escaping (Int) -> Void) {
        self.choose = choose; super.init(frame: .zero)
        self.title = L(title); bezelStyle = .rounded; image = CrabSymbol.image(named: "chevron-down", size: 10); imagePosition = .imageRight
        target = self; action = #selector(openCommands)
        let menu = NSMenu(); menu.autoenablesItems = false
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(chooseCommand(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; menu.addItem(item)
        }
        self.menu = menu
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openCommands() { menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 4), in: self) }
    @objc private func chooseCommand(_ sender: NSMenuItem) {
        let index = sender.tag, callback = choose
        DispatchQueue.main.async { callback(index) }
    }
}
