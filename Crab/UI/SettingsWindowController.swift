import AppKit
import FinderSync
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable {
    case library = "操作库", menu = "菜单编排", general = "通用设置"
    var categoryIcon: CategoryIcon { self == .library ? .tools : self == .menu ? .newFile : .general }
}
final class SettingsWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSSearchFieldDelegate {
    let store: ConfigurationStore
    private let hasAccessibilityPermission: () -> Bool
    private let requestAccessibilityPermission: () -> Void
    private let loadPermissionStatuses: (@escaping ([AppPermissionStatus]) -> Void) -> Void
    private let requestPermission: (AppPermission, @escaping () -> Void) -> Void
    private let openPermissionSettings: (AppPermission) -> Void
    private var permissionWindowReturn: PermissionWindowReturnCoordinator?
    private weak var permissionList: SettingsPermissionsView?
    private weak var permissionQueryView: SettingsPermissionsView?
    private weak var pendingPermissionRefreshView: SettingsPermissionsView?
    private var permissionQueryID: UUID?
    private var permissionStatuses: [AppPermissionStatus] = []
    private var page = SettingsPage.library
    private let root = ReferenceWindowCanvas(frame: .zero)
    private let content = UnfocusedContentCanvas()
    private var navButtons: [SettingsPage: ReferenceNavigationButton] = [:]
    private var observers: [NSObjectProtocol] = []
    private var fallbackChecks: [WritableKeyPath<AppConfiguration, Bool>: ClosureCheck] = [:]
    private weak var fallbackStatusLabel: NSTextField?
    private var layoutGeneral: (() -> Void)?
    private var collection: NSCollectionView?
    private var snapshots: [String: CardSnapshot] = [:]
    private var visibleOperations: [OperationRecord] = []
    private var generation = 0
    private var search = ""
    private var typeFilter = ""
    private var statusFilter = 0
    private var selecting = false
    private var selectedIDs = Set<String>()
    private weak var batchDeleteButton: NSButton?
    private var layoutLibraryToolbar: (() -> Void)?
    private var editor: OperationEditor?
    private var menuEditor: MenuEditorView?
    private var displayedLanguage = ""
    private var displayedStyle = AppIconStyle.color
    var operationFilePicker: ((String) -> [URL])?

    init(store: ConfigurationStore = .shared,
         hasAccessibilityPermission: @escaping () -> Bool = FinderFallback.hasPermission,
         requestAccessibilityPermission: @escaping () -> Void = FinderFallback.requestPermission,
         loadPermissionStatuses: ((@escaping ([AppPermissionStatus]) -> Void) -> Void)? = nil,
         requestPermission: ((AppPermission, @escaping () -> Void) -> Void)? = nil,
         openPermissionSettings: ((AppPermission) -> Void)? = nil) {
        self.store = store
        self.hasAccessibilityPermission = hasAccessibilityPermission; self.requestAccessibilityPermission = requestAccessibilityPermission
        self.loadPermissionStatuses = loadPermissionStatuses ?? { AppPermissions.loadStatuses(hasAccessibilityPermission: hasAccessibilityPermission, completion: $0) }
        self.requestPermission = requestPermission ?? { permission, completion in
            if permission == .accessibility { requestAccessibilityPermission(); completion() }
            else { AppPermissions.request(permission, completion: completion) }
        }
        self.openPermissionSettings = openPermissionSettings ?? { permission in
            if permission == .finderExtension { FIFinderSyncController.showExtensionManagementInterface() }
            else if let url = permission.settingsURL { referenceOpen(url) }
        }
        let window = SearchFocusWindow(contentRect: NSRect(origin: .zero, size: ReferenceStyle.windowSize), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Crab"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear; window.isOpaque = false; window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(type)?.isHidden = true }
        window.contentView = root
        content.identifier = .init("settings-content")
        window.unfocusedView = content; window.initialFirstResponder = content
        super.init(window: window)
        permissionWindowReturn = PermissionWindowReturnCoordinator(window: window); WindowAppearance.bind(window, to: store)
        AppLocalization.languageCode = store.configuration.languageCode
        displayedLanguage = store.configuration.languageCode; displayedStyle = store.configuration.iconStyle
        buildChrome(); showPage(.library); window.center()
        observers.append(NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged, object: store, queue: .main) { [weak self] _ in self?.configurationChanged() })
        observers.append(NotificationCenter.default.addObserver(forName: AppConstants.fallbackStatusChanged, object: nil, queue: .main) { [weak self] note in
            if let status = note.object as? FinderFallbackStatus { self?.updateFallbackStatus(status) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshFallbackPermissions(); self?.refreshPermissionStatuses(); self?.refreshSnapshot()
        })
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    override func showWindow(_ sender: Any?) {
        let opening = window?.isVisible == false
        if opening { window?.makeFirstResponder(content) }
        super.showWindow(sender)
        if opening { window?.makeFirstResponder(content) }
        refreshPermissionStatuses(); refreshSnapshot()
    }
    func selectPage(_ name: String) { if let value = SettingsPage(rawValue: name) { showPage(value) } }
    private func buildChrome() {
        root.subviews.forEach { $0.removeFromSuperview() }; navButtons = [:]
        let background = NSVisualEffectView(); background.material = .popover; background.blendingMode = .behindWindow; background.state = .active
        referencePlace(background, 0, 0, 900, 700, in: root)
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow
        referencePlace(sidebar, 0, 0, 200, 700, in: root)
        let brand = NSImageView(); brand.image = CrabIcon.image(size: 70)
        referencePlace(brand, 65, 60, 70, 70, in: root)
        referencePlace(referenceLabel("Crab · 1.0.0", size: 13, alignment: .center), 20, 140, 160, 22, in: root)
        for (index, item) in SettingsPage.allCases.enumerated() {
            let button = ReferenceNavigationButton(page: item, iconStyle: store.configuration.iconStyle) { [weak self] in self?.showPage(item) }
            referencePlace(button, 10, 227 + CGFloat(index) * 46, 180, 38, in: root); navButtons[item] = button
        }
        referencePlace(content, 200, 0, 700, 700, in: root)
        referencePlace(ReferenceTrafficButton(close: true) { [weak self] in self?.window?.close() }, 20, 15, 14, 14, in: root)
        referencePlace(ReferenceTrafficButton(close: false) { [weak self] in self?.window?.miniaturize(nil) }, 44, 15, 14, 14, in: root)
    }
    private func showPage(_ page: SettingsPage) {
        self.page = page; window?.makeFirstResponder(content)
        (window as? SearchFocusWindow)?.searchField = nil; content.nextKeyView = nil
        content.subviews.forEach { $0.removeFromSuperview() }; collection = nil; menuEditor = nil; layoutGeneral = nil; layoutLibraryToolbar = nil; permissionList = nil; fallbackChecks = [:]
        for (item, button) in navButtons { button.selected = page == item }
        switch page { case .library: buildLibrary(); case .menu: buildMenu(); case .general: buildGeneral() }
        window?.makeFirstResponder(content)
    }
    private func configurationChanged() {
        if displayedLanguage != store.configuration.languageCode || displayedStyle != store.configuration.iconStyle {
            displayedLanguage = store.configuration.languageCode; displayedStyle = store.configuration.iconStyle
            AppLocalization.languageCode = displayedLanguage; buildChrome(); showPage(page)
        } else { refreshSnapshot(); menuEditor?.reload() }
    }
    private func buildLibrary() {
        batchDeleteButton = nil
        let title = referenceLabel("操作库", size: 22, weight: .semibold)
        title.identifier = .init("settings-page-title")
        referencePlace(title, ReferenceStyle.pageInset, ReferenceStyle.pageTitleY, ReferenceStyle.pageWidth, 32, in: content)
        let toolbar = ReferenceCanvas(); toolbar.identifier = .init("library-toolbar")
        referencePlace(toolbar, ReferenceStyle.pageInset, 70, ReferenceStyle.pageWidth, 28, in: content)
        let definitions = OperationRegistry.shared.definitions
        let commands = OperationFileImport.kinds.compactMap { kind in definitions.first { $0.kind == kind } }
        let add = OperationAddButton(title: "新增", titles: commands.map { L($0.title) }) { [weak self] index in
            guard commands.indices.contains(index) else { return }
            self?.addOperation(kind: commands[index].kind)
        }
        add.identifier = .init("library-add"); add.setAccessibilityLabel(L("新增操作…"))
        let field = OperationLibrarySearchField(frame: .zero); field.stringValue = search
        field.delegate = self; field.placeholderString = L("搜索名称或内容"); field.identifier = .init("library-search")
        field.setAccessibilityLabel(L("搜索名称或内容"))
        (window as? SearchFocusWindow)?.searchField = field; content.nextKeyView = field
        let type = ActionPopup(titles: [L("全部类型")] + definitions.map { L($0.title) }, selected: definitions.firstIndex { $0.kind == typeFilter }.map { $0 + 1 } ?? 0) { [weak self] index in
            self?.typeFilter = index == 0 ? "" : definitions[index - 1].kind; self?.layoutLibraryToolbar?(); self?.applyFilters()
        }
        type.identifier = .init("library-type"); type.setAccessibilityLabel(L("全部类型"))
        let statuses = ActionPopup(titles: ["全部状态", "已启用", "已停用", "操作不可用", "未加入菜单"].map(L), selected: statusFilter) { [weak self] index in
            self?.statusFilter = index; self?.layoutLibraryToolbar?(); self?.applyFilters()
        }
        statuses.identifier = .init("library-status"); statuses.setAccessibilityLabel(L("全部状态"))
        let batchTitle = selecting ? "删除" : "批量删除"
        let batch = referenceButton(batchTitle) { [weak self] in
            guard let self, self.window?.attachedSheet == nil else { return }
            if self.selecting { self.perform(2, ids: self.selectedIDs) }
            else { self.selecting = true; self.selectedIDs = []; self.showPage(.library) }
        }
        batch.identifier = .init("library-batch"); batch.setAccessibilityLabel(L(batchTitle))
        batchDeleteButton = batch
        let cancel = referenceButton("取消") { [weak self] in
            guard let self else { return }
            self.selecting = false; self.selectedIDs = []; self.showPage(.library)
        }
        cancel.identifier = .init("library-batch-cancel"); cancel.setAccessibilityLabel(L("取消")); cancel.isHidden = !selecting
        let selectionMode = selecting
        for control in [field, type, statuses, cancel, batch, add] as [NSControl] {
            control.controlSize = .small; control.font = .systemFont(ofSize: 12)
            toolbar.addSubview(control)
        }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        referenceUseOverlayScrollers(scroll)
        scroll.identifier = .init("library-scroll")
        referencePlace(scroll, ReferenceStyle.pageInset, 112, ReferenceStyle.pageWidth + 20, 558, in: content)
        let errorLabel = store.lastError.map { message -> NSTextField in
            let label = NSTextField(wrappingLabelWithString: message); label.textColor = .systemRed
            content.addSubview(label); return label
        }
        layoutLibraryToolbar = { [weak toolbar, weak scroll] in
            guard let toolbar, let scroll else { return }
            let gap: CGFloat = 8, groupGap: CGFloat = 16, rowHeight: CGFloat = 28
            func size(_ control: NSControl) -> NSSize {
                let natural = control.intrinsicContentSize
                let cell = control.cell?.cellSize ?? .zero
                var width = ceil(max(natural.width, cell.width))
                if let popup = control as? NSPopUpButton {
                    width = ceil(((popup.title as NSString).size(withAttributes: [.font: popup.font!])).width) + 32
                    popup.toolTip = popup.title
                }
                return control.alignmentRect(forFrame: NSRect(x: 0, y: 0, width: width, height: max(natural.height, cell.height))).size
            }
            let typeSize = size(type), statusSize = size(statuses), batchSize = size(batch), addSize = size(add)
            let cancelSize = size(cancel)
            let cancelWidth = selectionMode ? cancelSize.width + gap : 0
            let actionsWidth = cancelWidth + batchSize.width + gap + addSize.width
            let filtersWidth = typeSize.width + gap + statusSize.width
            let searchWidth = toolbar.bounds.width - filtersWidth - actionsWidth - groupGap - gap
            let oneRow = searchWidth >= 120
            let fieldWidth = min(180, oneRow ? searchWidth : toolbar.bounds.width - filtersWidth - gap)
            func place(_ control: NSControl, x: CGFloat, width: CGFloat, row: CGFloat = 0) {
                let measured = size(control)
                let rect = NSRect(x: x, y: row * rowHeight + (rowHeight - measured.height) / 2, width: width, height: measured.height)
                control.frame = control.frame(forAlignmentRect: rect)
            }
            place(field, x: 0, width: fieldWidth)
            place(type, x: fieldWidth + gap, width: typeSize.width)
            place(statuses, x: fieldWidth + gap * 2 + typeSize.width, width: statusSize.width)
            let actionsX = toolbar.bounds.width - actionsWidth
            if selectionMode { place(cancel, x: actionsX, width: cancelSize.width, row: oneRow ? 0 : 1) }
            place(batch, x: actionsX + cancelWidth, width: batchSize.width, row: oneRow ? 0 : 1)
            place(add, x: actionsX + cancelWidth + batchSize.width + gap, width: addSize.width, row: oneRow ? 0 : 1)
            toolbar.setFrameSize(NSSize(width: ReferenceStyle.pageWidth, height: rowHeight * (oneRow ? 1 : 2)))
            var scrollY = toolbar.frame.maxY + 14
            if let errorLabel {
                let size = referenceWrapLabel(errorLabel, width: ReferenceStyle.pageWidth)
                errorLabel.frame = NSRect(x: ReferenceStyle.pageInset, y: scrollY, width: size.width, height: size.height)
                scrollY += size.height + 10
            }
            scroll.frame = NSRect(x: ReferenceStyle.pageInset, y: scrollY, width: ReferenceStyle.pageWidth + 20, height: 670 - scrollY)
        }
        layoutLibraryToolbar?()
        let collection = NSCollectionView(); collection.dataSource = self; collection.delegate = self; collection.backgroundColors = [.clear]
        let flow = OperationLibraryFlowLayout(); flow.itemSize = NSSize(width: ReferenceStyle.pageWidth, height: 56); flow.minimumLineSpacing = 6
        flow.minimumInteritemSpacing = 1000; flow.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        collection.collectionViewLayout = flow; collection.register(OperationCardItem.self, forItemWithIdentifier: .init("operation-card"))
        collection.frame = NSRect(x: 0, y: 0, width: ReferenceStyle.pageWidth + 20, height: 518); scroll.documentView = collection; self.collection = collection
        applyFilters(); refreshSnapshot()
    }
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }; search = field.stringValue; applyFilters()
    }
    private func refreshSnapshot() {
        guard page == .library else { return }
        generation += 1; let expected = generation, configuration = store.configuration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let summaries = Dictionary(configuration.operations.map { op in
                (op.id, OperationUIRegistry.shared.adapter(op.parameters.kind)?.summary(op) ?? L("不受当前版本支持"))
            }, uniquingKeysWith: { first, _ in first })
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                ConfigurationStore.prepareAsync(configuration, isCancelled: { [weak self] in self?.generation != expected || self?.page != .library }) { [weak self] prepared in
                    guard let self, self.generation == expected, self.page == .library else { return }
                    var result: [String: CardSnapshot] = [:]
                    for operation in configuration.operations {
                        result[operation.id] = CardSnapshot(summary: summaries[operation.id] ?? "", reason: prepared.previews[operation.id]?.reason.map(L),
                            image: OperationImages.image(operation, configuration: prepared, size: 32, allowFileRead: false))
                    }
                    self.snapshots = result; self.applyFilters()
                }
            }
        }
    }
    private func applyFilters() {
        let config = store.configuration
        selectedIDs.formIntersection(Set(config.operations.filter { !$0.isBuiltIn }.map(\.id)))
        batchDeleteButton?.isEnabled = !selecting || !selectedIDs.isEmpty
        visibleOperations = config.operations.filter { op in
            if !typeFilter.isEmpty && op.parameters.kind != typeFilter { return false }
            if statusFilter == 1 && !op.enabled || statusFilter == 2 && op.enabled { return false }
            if statusFilter == 3 && snapshots[op.id]?.reason == nil { return false }
            if statusFilter == 4 && config.referenceCount(op.id) != 0 { return false }
            return search.isEmpty || (op.displayName + " " + (snapshots[op.id]?.summary ?? "")).localizedCaseInsensitiveContains(search)
        }
        collection?.reloadData()
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        let kind = visibleOperations[indexPath.item].parameters.kind
        return NSSize(width: ReferenceStyle.pageWidth, height: max(56, OperationUIRegistry.shared.adapter(kind)?.cardHeight ?? 56))
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { visibleOperations.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("operation-card"), for: indexPath) as! OperationCardItem
        let op = visibleOperations[indexPath.item]
        item.configure(op, snapshot: snapshots[op.id], references: store.configuration.referenceCount(op.id), selecting: selecting, selected: selectedIDs.contains(op.id),
                       edit: { [weak self] in self?.edit(op.id) }, toggle: { [weak self] value in
            guard let self, self.selecting,
                  self.store.configuration.operations.contains(where: { $0.id == op.id && !$0.isBuiltIn }) else { return }
            if value { self.selectedIDs.insert(op.id) } else { self.selectedIDs.remove(op.id) }
            self.applyFilters()
        }, action: { [weak self] command in self?.perform(command, ids: [op.id]) })
        return item
    }
    func addOperation(kind: String) {
        guard OperationFileImport.kinds.contains(kind) else {
            if let adapter = OperationUIRegistry.shared.adapter(kind) { openEditor(adapter.makeDraft(), existing: false) }
            return
        }
        if let operationFilePicker { importOperations(kind: kind, urls: operationFilePicker(kind)) }
        else {
            guard let window else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = kind == "directory" || kind == "transfer"
            panel.canChooseFiles = !panel.canChooseDirectories; panel.allowsMultipleSelection = kind != "application"
            panel.prompt = L("添加")
            if kind == "application" { panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true) }
            if kind == "image" { panel.allowedContentTypes = [.image] }
            if kind == "template" { panel.prompt = L("添加模板…") }
            if kind == "script" { panel.prompt = L("添加脚本…") }
            WindowDialogs.present(panel, for: window, store: store) { [weak self] response in
                guard response == .OK else { return }
                self?.importOperations(kind: kind, urls: panel.urls)
            }
        }
    }
    private func importOperations(kind: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try OperationFileImport.prepare(kind: kind, urls: urls, store: store) }
            DispatchQueue.main.async {
                do { try result.get().commit(to: store) }
                catch {
                    if let window = self?.window {
                        WindowDialogs.present(WindowAppearance.errorAlert(error, store: store), for: window, store: store)
                    }
                }
            }
        }
    }
    private func edit(_ id: String) { if let op = store.configuration.operations.first(where: { $0.id == id }) { openEditor(op, existing: true) } }
    private func openEditor(_ op: OperationRecord, existing: Bool) {
        guard let window, window.attachedSheet == nil,
              OperationUIRegistry.shared.adapter(op.parameters.kind) != nil else { return }
        editor = OperationEditor(operation: op, existing: existing, store: store)
        editor?.present(asSheetFor: window)
    }
    private func perform(_ command: Int, ids: Set<String>) {
        switch command {
        case 0: store.update { config in config.operations += config.operations.filter { ids.contains($0.id) && !$0.isBuiltIn }.map { $0.duplicated() } }
        case 1:
            guard let window else { return }
            MenuEditorView.addReferences(ids: store.configuration.operations.filter { ids.contains($0.id) }.map(\.id), store: store, for: window)
        default:
            let ids = Set(store.configuration.operations.filter { ids.contains($0.id) && !$0.isBuiltIn }.map(\.id))
            guard !ids.isEmpty, let window else { return }
            let count = ids.reduce(0) { $0 + store.configuration.referenceCount($1) }
            WindowDialogs.confirm(title: "删除操作", message: LF("将删除 %d 个操作及其 %d 处菜单引用；原始文件不受影响。", ids.count, count), button: "删除", for: window, store: store) { [weak self] confirmed in
                guard confirmed, let self else { return }
                self.store.update { $0.removeOperations(ids) }; self.selectedIDs.subtract(ids)
                self.applyFilters()
            }
        }
    }
    private func buildMenu() {
        let view = MenuEditorView(store: store)
        referencePlace(view, ReferenceStyle.pageInset, ReferenceStyle.pageTitleY, ReferenceStyle.pageWidth, 646, in: content)
        menuEditor = view
    }
    private func buildGeneral() {
        refreshFallbackPermissions()
        let config = store.configuration
        let title = referenceLabel("通用设置", size: 22, weight: .semibold)
        title.identifier = .init("settings-page-title")
        referencePlace(title, ReferenceStyle.pageInset, ReferenceStyle.pageTitleY, ReferenceStyle.pageWidth, 32, in: content)
        let scrollTop: CGFloat = 72
        let scroll = NSScrollView(frame: NSRect(x: 0, y: scrollTop, width: content.bounds.width,
            height: max(0, content.bounds.height - scrollTop)))
        scroll.identifier = .init("general-scroll")
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        referenceUseOverlayScrollers(scroll)
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.drawsBackground = false; scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        let document = ReferenceCanvas()
        document.frame = NSRect(origin: .zero, size: scroll.contentSize)
        scroll.documentView = document; content.addSubview(scroll)

        func heading(_ title: String, symbol: String, color: NSColor, identifier: String,
                     help: NSButton? = nil) -> ReferenceCanvas {
            let view = ReferenceCanvas()
            view.identifier = .init(identifier)
            let badge = ReferenceBadge(symbol: symbol, color: color)
            badge.iconStyle = config.iconStyle
            badge.identifier = .init(identifier + "-icon")
            let label = referenceLabel(title, size: 13, weight: .medium)
            label.identifier = .init(identifier + "-title")
            let availableWidth: CGFloat = help == nil ? 592 : 566
            let naturalWidth = ceil((label.stringValue as NSString).size(withAttributes: [.font: label.font!]).width) + 4
            let labelWidth = min(availableWidth, naturalWidth)
            referenceWrapLabel(label, width: labelWidth)
            let textHeight = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: 10000)).height)
            let rowHeight = max(22, textHeight)
            referencePlace(badge, 0, (rowHeight - 22) / 2, 22, 22, in: view)
            referencePlace(label, 28, (rowHeight - textHeight) / 2, labelWidth, textHeight, in: view)
            if let help { referencePlace(help, 28 + labelWidth + 6, (rowHeight - 20) / 2, 20, 20, in: view) }
            view.frame.size = NSSize(width: ReferenceStyle.pageWidth, height: rowHeight)
            document.addSubview(view)
            return view
        }
        let cloudHelp = helpButton("备用菜单", "仅在访达当前窗口打开 iCloud 或 OneDrive 文件夹时生效。先选中文件，再使用已启用的触发方式。菜单针对当前选中项；未选中时针对当前目录。需要辅助功能权限；三指轻点还需要支持的触控板。")
        cloudHelp.identifier = .init("general-cloud-help")
        let launchTitle = heading("启动与显示", symbol: "rocket", color: .systemPink, identifier: "general-heading-launch")
        let cloudTitle = heading("在 iCloud、One Drive 文件夹中显示菜单", symbol: "cloud", color: .systemCyan,
                                 identifier: "general-heading-cloud", help: cloudHelp)
        let permissionTitle = heading("权限", symbol: "key", color: .systemOrange, identifier: "general-heading-permissions")
        let launch = ReferenceMaterialCard(frame: .zero)
        let cloud = ReferenceMaterialCard(frame: .zero)
        let permissions = ReferenceMaterialCard(frame: .zero)
        launch.identifier = .init("general-launch-card")
        cloud.identifier = .init("general-cloud-card")
        permissions.identifier = .init("general-permissions-card")
        [launch, cloud, permissions].forEach { document.addSubview($0) }
        let showStatus = referenceCheck("显示菜单栏图标", value: config.showStatusItem) { [weak self] value in self?.store.update { $0.showStatusItem = value } }
        let languageLabel = referenceLabel("语言:", alignment: .right)
        let scopeLabel = referenceLabel("使用范围:", alignment: .right)
        let iconStyleLabel = referenceLabel("图标风格:", alignment: .right)
        let windowThemeLabel = referenceLabel("主题:", alignment: .right)
        let languages = AppLocalization.supportedLanguages
        let language = popup(languages.map(\.name), selected: languages.first { $0.code == config.languageCode }?.name ?? languages[0].name, key: "language")
        let iconStyle = popup(AppIconStyle.allCases.map(\.title), selected: config.iconStyle.title, key: "icon-style")
        let windowTheme = popup(WindowTheme.allCases.map(\.title), selected: config.windowTheme.title, key: "window-theme")
        let scope = popup(["系统磁盘", "系统磁盘+外接磁盘"], selected: config.monitorExternalDisks ? "系统磁盘+外接磁盘" : "系统磁盘", key: "scope")
        scope.target = self; scope.action = #selector(scopeChanged(_:))
        let scopeHelp = helpButton("使用范围", "访达扩展会监视本地用户目录；开启外接磁盘后也监视 /Volumes。请在扩展管理中启用 Crab Finder 菜单。")
        let shortcut = fallbackCheck("1. 按住修饰键", keyPath: \.fallbackShortcut, identifier: "fallbackShortcut")
        let modifier = popup(["Shift", "Control", "Option", "Command"], selected: config.fallbackModifier.rawValue, key: "modifier")
        let rightClick = referenceLabel("鼠标右键点击")
        rightClick.identifier = .init("fallback-right-click-label")
        let middle = fallbackCheck("2. 鼠标中键点击", keyPath: \.fallbackMiddleClick, identifier: "fallbackMiddleClick")
        let threeFinger = fallbackCheck("3. 触控板上三指轻点/三指点按", keyPath: \.fallbackThreeFingerTap, identifier: "fallbackThreeFingerTap")
        let statusLabel = referenceLabel("", size: 10, color: .secondaryLabelColor)
        fallbackStatusLabel = statusLabel
        let permissionRows = SettingsPermissionsView(refresh: { [weak self] in self?.refreshPermissionStatuses() },
                                                   action: { [weak self] permission in self?.activatePermission(permission) })
        permissionList = permissionRows

        layoutGeneral = { [weak self] in
            guard self != nil else { return }
            let fieldWidth = [languageLabel, scopeLabel, iconStyleLabel, windowThemeLabel].map { referenceFittingSize($0).width }.max() ?? 0
            let popupWidth = [language, scope, iconStyle, windowTheme].map { referenceFittingSize($0).width }.max() ?? 0
            var y: CGFloat = 16
            y += referenceFlowRow([showStatus], x: 20, y: y, width: 580, in: launch) + 8
            for (label, popup, help) in [(windowThemeLabel, windowTheme, nil as NSButton?), (languageLabel, language, nil), (iconStyleLabel, iconStyle, nil), (scopeLabel, scope, scopeHelp)] {
                let labelSize = referenceFittingSize(label), popupSize = referenceFittingSize(popup)
                let rowHeight = max(labelSize.height, popupSize.height)
                referencePlace(label, 20, y + (rowHeight - labelSize.height) / 2, fieldWidth, labelSize.height, in: launch)
                referencePlace(popup, 20 + fieldWidth + 10, y, popupWidth, rowHeight, in: launch)
                if let help { referencePlace(help, 20 + fieldWidth + 10 + popupWidth + 6, y + (rowHeight - 20) / 2, 20, 20, in: launch) }
                y += rowHeight + 6
            }
            launch.frame.size = NSSize(width: ReferenceStyle.pageWidth, height: y + 10)
            y = 16
            let triggers: [[NSView]] = [[shortcut, modifier, rightClick], [middle], [threeFinger]]
            for controls in triggers { y += referenceFlowRow(controls, x: 20, y: y, width: 580, in: cloud) + 10 }
            let statusSize = referenceWrapLabel(statusLabel, width: 580)
            referencePlace(statusLabel, 20, y, statusSize.width, statusSize.height, in: cloud)
            cloud.frame.size = NSSize(width: ReferenceStyle.pageWidth, height: y + statusSize.height + 16)
            let permissionsHeight = permissionRows.layoutRows(width: 580)
            referencePlace(permissionRows, 20, 16, 580, permissionsHeight, in: permissions)
            permissions.frame.size = NSSize(width: ReferenceStyle.pageWidth, height: permissionsHeight + 32)
            var top: CGFloat = 0
            for (title, card) in [(launchTitle, launch), (cloudTitle, cloud), (permissionTitle, permissions)] {
                title.setFrameOrigin(NSPoint(x: ReferenceStyle.pageInset, y: top))
                top += title.frame.height + 8
                card.setFrameOrigin(NSPoint(x: ReferenceStyle.pageInset, y: top))
                top += card.frame.height + 20
            }
            document.frame.size.height = max(scroll.contentSize.height, top)
        }
        layoutGeneral?()
        refreshPermissionStatuses()
        if let status = (NSApp.delegate as? AppDelegate)?.fallbackStatus { updateFallbackStatus(status) }
    }
    private func refreshPermissionStatuses() {
        guard page == .general, let list = permissionList else { return }
        if permissionQueryView === list {
            pendingPermissionRefreshView = list
            return
        }
        permissionQueryView = list
        let queryID = UUID()
        permissionQueryID = queryID
        list.beginRefresh()
        layoutGeneral?()
        loadPermissionStatuses { [weak self, weak list] statuses in
            let apply = { [weak self, weak list] in
                guard let self, let list, self.permissionList === list, self.permissionQueryID == queryID else { return }
                self.permissionQueryView = nil
                self.permissionQueryID = nil
                self.permissionStatuses = statuses
                list.show(statuses)
                self.layoutGeneral?()
                if self.pendingPermissionRefreshView === list {
                    self.pendingPermissionRefreshView = nil
                    self.refreshPermissionStatuses()
                }
            }
            if Thread.isMainThread { apply() }
            else { DispatchQueue.main.async(execute: apply) }
        }
    }
    private func activatePermission(_ permission: AppPermission) {
        beginPermissionWindowReturn()
        let state = permissionStatuses.first { $0.permission == permission }?.state
        let canRequest = state == .notDetermined || (state == .notAuthorized && [.accessibility, .inputMonitoring].contains(permission))
        guard canRequest else { openPermissionSettings(permission); return }
        requestPermission(permission) { [weak self] in
            guard let self else { return }
            if [.accessibility, .inputMonitoring].contains(permission) {
                self.beginPermissionWindowReturn()
                self.openPermissionSettings(permission)
            }
            self.refreshPermissionStatuses()
        }
    }
    private func beginPermissionWindowReturn() {
        permissionWindowReturn?.begin(windowIsVisible: window?.isVisible == true)
    }
    private func fallbackCheck(_ title: String, keyPath: WritableKeyPath<AppConfiguration, Bool>, identifier: String) -> ClosureCheck {
        let check = referenceCheck(title, value: store.configuration[keyPath: keyPath]) { _ in }
        check.identifier = .init(identifier)
        check.changed = { [weak self, weak check] value in
            guard let self, let check else { return }
            if value && !self.hasAccessibilityPermission() {
                check.state = .off
                self.beginPermissionWindowReturn()
                self.requestAccessibilityPermission()
            }
            let enabled = value && self.hasAccessibilityPermission()
            check.state = enabled ? .on : .off
            if self.store.configuration[keyPath: keyPath] != enabled {
                self.store.update { $0[keyPath: keyPath] = enabled }
            }
        }
        fallbackChecks[keyPath] = check
        return check
    }
    private func refreshFallbackPermissions() {
        if !hasAccessibilityPermission(), FinderFallbackTriggerSettings(store.configuration).anyEnabled {
            store.update {
                $0.fallbackShortcut = false
                $0.fallbackMiddleClick = false
                $0.fallbackThreeFingerTap = false
            }
        }
        for (keyPath, check) in fallbackChecks {
            check.state = store.configuration[keyPath: keyPath] ? .on : .off
        }
    }
    private func updateFallbackStatus(_ status: FinderFallbackStatus) {
        fallbackStatusLabel?.stringValue = L(status.message)
        fallbackStatusLabel?.textColor = status.requiresAttention ? .systemOrange : .secondaryLabelColor
        fallbackStatusLabel?.toolTip = L(status.message)
        layoutGeneral?()
    }
    private func popup(_ items: [String], selected: String, key: String) -> NSPopUpButton {
        let popup = NSPopUpButton(); popup.addItems(withTitles: items.map(L)); popup.selectItem(withTitle: L(selected))
        popup.font = .systemFont(ofSize: 13); popup.identifier = .init(key)
        popup.target = self; popup.action = #selector(preferenceChanged(_:)); return popup
    }
    @objc private func preferenceChanged(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue else { return }
        if key == "language" {
            let languages = AppLocalization.supportedLanguages
            guard languages.indices.contains(sender.indexOfSelectedItem) else { return }
            store.update { $0.languageCode = languages[sender.indexOfSelectedItem].code }
        } else if key == "modifier", FallbackModifier.allCases.indices.contains(sender.indexOfSelectedItem) {
            store.update { $0.fallbackModifier = FallbackModifier.allCases[sender.indexOfSelectedItem] }
        } else if key == "icon-style", AppIconStyle.allCases.indices.contains(sender.indexOfSelectedItem) {
            store.update { $0.iconStyle = AppIconStyle.allCases[sender.indexOfSelectedItem] }
        } else if key == "window-theme", WindowTheme.allCases.indices.contains(sender.indexOfSelectedItem) {
            store.update { $0.windowTheme = WindowTheme.allCases[sender.indexOfSelectedItem] }
        }
    }
    @objc private func scopeChanged(_ sender: NSPopUpButton) { store.update { $0.monitorExternalDisks = sender.indexOfSelectedItem == 1 } }
    private func helpButton(_ title: String, _ message: String) -> NSButton {
        HoverHelpButton(title: title, message: message)
    }
}
/// Shared by the operation library and its picker sheet. End search editing
/// before dispatching an outside click, so the original target still handles it.
final class SearchFocusWindow: NSWindow {
    weak var searchField: NSSearchField?
    weak var unfocusedView: NSView?

    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           event.window === self, attachedSheet == nil,
           let search = searchField, search.window === self,
           let editor = search.currentEditor(), firstResponder === editor,
           !search.bounds.contains(search.convert(event.locationInWindow, from: nil)) {
            makeFirstResponder(unfocusedView)
        }
        super.sendEvent(event)
    }
}

final class UnfocusedContentCanvas: ReferenceCanvas {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { false }
}

final class OperationLibrarySearchField: NSSearchField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = OperationLibrarySearchCell(textCell: "")
        isEditable = true; isSelectable = true
        isBezeled = true; drawsBackground = false
        focusRingType = .default
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width, height: 24)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}

private final class OperationLibraryFlowLayout: NSCollectionViewFlowLayout {
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        super.layoutAttributesForElements(in: rect).map(leftAligned)
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: indexPath).map(leftAligned)
    }
    private func leftAligned(_ attributes: NSCollectionViewLayoutAttributes) -> NSCollectionViewLayoutAttributes {
        guard attributes.representedElementCategory == .item,
              let copy = attributes.copy() as? NSCollectionViewLayoutAttributes else { return attributes }
        copy.frame.origin.x = sectionInset.left
        return copy
    }
}

private final class OperationLibrarySearchCell: NSSearchFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        controlView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            let tint = NSColor.controlBackgroundColor
            NSGradient(starting: tint.withAlphaComponent(0.22), ending: tint.withAlphaComponent(0.06))?.draw(in: path, angle: 0)
            NSColor.labelColor.withAlphaComponent(0.12).setStroke(); path.lineWidth = 0.5; path.stroke()
            super.drawInterior(withFrame: cellFrame, in: controlView)
        }
    }
    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
    }
    override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect {
        cellFrame
    }
}

private final class ReferenceNavigationButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    private var callback: () -> Void
    init(page: SettingsPage, iconStyle: AppIconStyle = .color, action: @escaping () -> Void) {
        callback = action; super.init(frame: .zero); title = ""; isBordered = false
        target = self; self.action = #selector(activate)
        let badge = ReferenceBadge(icon: page.categoryIcon)
        badge.iconStyle = iconStyle
        referencePlace(badge, 32, 6, 22, 22, in: self)
        referencePlace(referenceLabel(L(page.rawValue), size: 13, color: .labelColor), 61, 9, 119, 20, in: self)
        setAccessibilityLabel(L(page.rawValue)); setAccessibilityIdentifier("nav-\(page.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func draw(_ dirtyRect: NSRect) {
        if selected { NSColor.labelColor.withAlphaComponent(0.09).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    @objc private func activate() { callback() }
}

