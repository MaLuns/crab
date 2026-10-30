import AppKit

final class OperationPickerWindowController: NSWindowController, NSWindowDelegate,
    NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSSearchFieldDelegate {
    private let store: ConfigurationStore
    private let collection = NSCollectionView()
    private let countLabel = NSTextField(labelWithString: "")
    private var addButton: NSButton!
    private var operations: [OperationRecord] = []
    private var visibleOperations: [OperationRecord] = []
    private var snapshots: [String: CardSnapshot] = [:]
    private var selectedIDs = Set<String>()
    private var search = ""
    private var typeFilter = ""
    private var generation = 0
    private var refreshScheduled = false
    private var dismissing = false
    private var observer: NSObjectProtocol?
    private var completion: (([String]) -> Void)?
    private var submittedIDs: [String]?
    var didClose: (() -> Void)?

    init(store: ConfigurationStore) {
        self.store = store
        let window = SearchFocusWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("添加操作…"); window.identifier = .init("operation-picker")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; WindowAppearance.bind(window, to: store)
        buildContent()
        observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged,
            object: store, queue: .main) { [weak self] _ in self?.reloadOperations() }
        reloadOperations()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func present(asSheetFor parent: NSWindow, completion: @escaping ([String]) -> Void) {
        guard let window, parent.attachedSheet == nil, window.sheetParent == nil else { return }
        self.completion = completion; submittedIDs = nil; dismissing = false
        window.makeFirstResponder(window.initialFirstResponder)
        parent.beginSheet(window) { [self] response in
            self.window?.orderOut(nil)
            let callback = self.completion
            self.completion = nil
            if response == .OK, let ids = self.submittedIDs { callback?(ids) }
            self.submittedIDs = nil
            self.didClose?()
        }
        window.makeFirstResponder(window.initialFirstResponder)
    }
    override func close() { dismiss(response: .cancel) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.sheetParent != nil else { return true }
        close(); return false
    }
    private func dismiss(response: NSApplication.ModalResponse) {
        guard !dismissing else { return }
        dismissing = true; generation += 1
        if let window, let parent = window.sheetParent { parent.endSheet(window, returnCode: response) }
        else { super.close(); didClose?() }
    }
    private func submit() {
        let ids = store.configuration.operations.filter { selectedIDs.contains($0.id) }.map(\.id)
        guard !ids.isEmpty else { return }
        submittedIDs = ids; dismiss(response: .OK)
    }

    private func buildContent() {
        let root = UnfocusedContentCanvas(color: .windowBackgroundColor)
        window?.contentView = root
        window?.initialFirstResponder = root
        (window as? SearchFocusWindow)?.unfocusedView = root
        referencePlace(referenceLabel("添加操作…", size: 20, weight: .semibold), 20, 16, 620, 30, in: root)
        let field = OperationLibrarySearchField(frame: .zero)
        field.delegate = self; field.placeholderString = L("搜索名称或内容")
        field.identifier = .init("operation-picker-search"); field.setAccessibilityLabel(L("搜索名称或内容"))
        referencePlace(field, 20, 58, 360, 28, in: root)
        (window as? SearchFocusWindow)?.searchField = field
        root.nextKeyView = field
        let definitions = OperationRegistry.shared.definitions
        let type = ActionPopup(titles: [L("全部类型")] + definitions.map { L($0.title) }, selected: 0) { [weak self] index in
            self?.typeFilter = index == 0 ? "" : definitions[index - 1].kind
            self?.applyFilters()
        }
        type.identifier = .init("operation-picker-type"); type.setAccessibilityLabel(L("全部类型"))
        referencePlace(type, 392, 58, 248, 28, in: root)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        referenceUseOverlayScrollers(scroll)
        scroll.identifier = .init("operation-picker-scroll")
        referencePlace(scroll, 10, 100, 640, 440, in: root)
        collection.identifier = .init("operation-picker-list")
        collection.dataSource = self; collection.delegate = self; collection.backgroundColors = [.clear]
        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: 620, height: 56); flow.minimumLineSpacing = 6
        flow.minimumInteritemSpacing = 1000
        flow.sectionInset = NSEdgeInsets(top: 0, left: 10, bottom: 12, right: 10)
        collection.collectionViewLayout = flow
        collection.register(OperationCardItem.self, forItemWithIdentifier: .init("operation-picker-card"))
        collection.frame = NSRect(x: 0, y: 0, width: 640, height: 440)
        scroll.documentView = collection
        countLabel.identifier = .init("operation-picker-count")
        countLabel.font = .systemFont(ofSize: 12); countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        referencePlace(countLabel, 20, 556, 350, 24, in: root)
        let cancel = referenceButton("取消") { [weak self] in self?.close() }
        cancel.identifier = .init("operation-picker-cancel"); cancel.keyEquivalent = "\u{1b}"
        referencePlace(cancel, 422, 552, 102, 32, in: root)
        let add = referenceButton("添加") { [weak self] in self?.submit() }
        add.identifier = .init("operation-picker-add"); add.keyEquivalent = "\r"
        referencePlace(add, 536, 552, 104, 32, in: root); addButton = add
    }

    private func reloadOperations() {
        guard !dismissing else { return }
        operations = store.configuration.operations
        selectedIDs.formIntersection(Set(operations.map(\.id)))
        applyFilters(); refreshSnapshots()
    }
    private func refreshSnapshots() {
        generation += 1
        let expected = generation, configuration = store.configuration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let prepared = ConfigurationStore.prepare(configuration)
            let result = Dictionary(configuration.operations.map { operation in
                let summary = OperationUIRegistry.shared.adapter(operation.parameters.kind)?.summary(operation)
                    ?? L("不受当前版本支持")
                return (operation.id, CardSnapshot(summary: summary,
                    reason: prepared.previews[operation.id]?.reason.map(L),
                    image: OperationImages.image(operation, configuration: prepared, size: 24, allowFileRead: false)))
            }, uniquingKeysWith: { first, _ in first })
            DispatchQueue.main.async {
                guard let self, self.generation == expected, !self.dismissing else { return }
                self.snapshots = result; self.applyFilters()
            }
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        search = field.stringValue; applyFilters()
    }
    private func applyFilters() {
        visibleOperations = operations.filter { operation in
            if !typeFilter.isEmpty && operation.parameters.kind != typeFilter { return false }
            let text = operation.displayName + " " + (snapshots[operation.id]?.summary ?? "")
            return search.isEmpty || text.localizedCaseInsensitiveContains(search)
        }
        updateSelectionStatus(); collection.reloadData()
    }
    private func toggleSelection(_ id: String) {
        guard operations.contains(where: { $0.id == id }) else { return }
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        updateSelectionStatus()
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false; self.collection.reloadData()
        }
    }
    private func updateSelectionStatus() {
        countLabel.stringValue = LF("已选择 %d 项", selectedIDs.count)
        addButton.isEnabled = !selectedIDs.isEmpty
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleOperations.count
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("operation-picker-card"), for: indexPath) as! OperationCardItem
        let operation = visibleOperations[indexPath.item]
        item.configurePicker(operation, snapshot: snapshots[operation.id], selected: selectedIDs.contains(operation.id)) { [weak self] in
            self?.toggleSelection(operation.id)
        }
        return item
    }
}
