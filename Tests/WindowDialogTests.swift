import AppKit
import XCTest
@testable import Crab

@MainActor
final class WindowDialogTests: XCTestCase {
    private var directory: URL!
    private var windows: [NSWindow] = []
    private var language = ""

    override func setUpWithError() throws {
        language = AppLocalization.languageCode
        AppLocalization.languageCode = "zh-Hans"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-WindowDialogs-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for window in windows.reversed() {
            for sheet in window.sheets { window.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
            window.close()
        }
        windows = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        AppLocalization.languageCode = language
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> ConfigurationStore {
        ConfigurationStore(directory: directory.appendingPathComponent(UUID().uuidString))
    }

    private func operation(_ id: String = UUID().uuidString) -> OperationRecord {
        .init(id: id, parameters: .tool(.init(action: .copyPath)))
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 700),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        windows.append(window)
        window.orderFront(nil)
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func button(_ identifier: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == identifier })
    }

    private func pump(until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func sheet(of parent: NSWindow) throws -> NSWindow {
        pump { parent.attachedSheet != nil }
        let sheet = try XCTUnwrap(parent.attachedSheet)
        XCTAssertTrue(sheet.sheetParent === parent)
        sheet.animationBehavior = .none
        return sheet
    }

    private func dismiss(_ sheet: NSWindow, from parent: NSWindow, response: NSApplication.ModalResponse) {
        parent.endSheet(sheet, returnCode: response)
        pump { sheet.sheetParent == nil && parent.attachedSheet !== sheet }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testLibrarySearchStartsUnfocusedAfterOpeningAndRebuildingAndRemainsKeyboardAccessible() throws {
        let store = store()
        let settings = SettingsWindowController(store: store,
                                                loadPermissionStatuses: { $0([]) })
        let owner = try XCTUnwrap(settings.window)
        windows.append(owner); owner.animationBehavior = .none; owner.isMovableByWindowBackground = false
        let root = try XCTUnwrap(owner.contentView)
        let content = try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == "settings-content" })
        func search() throws -> NSSearchField {
            try XCTUnwrap(descendants(root).compactMap { $0 as? NSSearchField }.first { $0.identifier?.rawValue == "library-search" })
        }
        let configuration = store.configuration
        XCTAssertTrue(owner.initialFirstResponder === content)
        settings.showWindow(nil)
        XCTAssertTrue(owner.firstResponder === content)
        XCTAssertNil(try search().currentEditor())
        owner.selectNextKeyView(nil)
        let editor = try XCTUnwrap(try search().currentEditor() as? NSTextView)
        XCTAssertTrue(owner.firstResponder === editor)
        editor.insertText("Crab", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(owner.makeFirstResponder(content))
        XCTAssertNil(try search().currentEditor())
        XCTAssertEqual(try search().stringValue, "Crab")

        settings.selectPage(SettingsPage.menu.rawValue)
        settings.selectPage(SettingsPage.library.rawValue)
        XCTAssertTrue(owner.firstResponder === content)
        XCTAssertNil(try search().currentEditor())
        XCTAssertEqual(try search().stringValue, "Crab")
        let oldSearch = try search()
        let batch = try button("library-batch", in: root)
        XCTAssertNil(batch.menu)
        batch.performClick(nil)
        pump { !descendants(root).contains { $0 === oldSearch } }
        XCTAssertTrue(owner.firstResponder === content)
        XCTAssertNil(try search().currentEditor())
        XCTAssertEqual(try search().stringValue, "Crab")

        try search().selectText(nil)
        XCTAssertNotNil(try search().currentEditor())
        owner.close(); settings.showWindow(nil)
        XCTAssertTrue(owner.firstResponder === content)
        XCTAssertNil(try search().currentEditor())
        XCTAssertEqual(try search().stringValue, "Crab")
        XCTAssertEqual(store.configuration, configuration)
    }

    func testOutsideMouseClickEndsOnlyTheLibrarySearchEditorAndStillReachesItsTarget() throws {
        let store = store()
        let settings = SettingsWindowController(store: store,
                                                loadPermissionStatuses: { $0([]) })
        let owner = try XCTUnwrap(settings.window)
        windows.append(owner); owner.animationBehavior = .none; owner.isMovableByWindowBackground = false
        settings.showWindow(nil)
        let root = try XCTUnwrap(owner.contentView)
        let content = try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == "settings-content" })
        let search = try XCTUnwrap(descendants(root).compactMap { $0 as? NSSearchField }.first { $0.identifier?.rawValue == "library-search" })
        let target = SearchFocusMouseTarget(frame: .zero)
        content.addSubview(target)
        let configuration = store.configuration
        func click(_ view: NSView) throws {
            NSApp.postEvent(try mouseEvent(.leftMouseUp, on: view, clicks: 1), atStart: true)
            owner.sendEvent(try mouseEvent(on: view, clicks: 1))
        }
        for (index, point) in [NSPoint(x: 30, y: 24), NSPoint(x: 30, y: 130), NSPoint(x: 30, y: 620)].enumerated() {
            target.frame = NSRect(origin: point, size: NSSize(width: 100, height: 28))
            search.selectText(nil)
            let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
            editor.insertText("Crab", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            try click(search)
            XCTAssertTrue(search.currentEditor() === editor, "Clicks inside the search field must retain editing.")
            let clicks = target.mouseDownCount
            try click(target)
            XCTAssertNil(search.currentEditor())
            XCTAssertTrue(owner.firstResponder === content)
            XCTAssertEqual(search.stringValue, "Crab")
            XCTAssertEqual(target.mouseDownCount, clicks + 1, "The outside click must continue to its target: \(index)")
        }
        let ordinary = NSTextField(string: "Unrelated editing")
        ordinary.frame = NSRect(x: 400, y: 24, width: 160, height: 24); content.addSubview(ordinary)
        ordinary.selectText(nil)
        let ordinaryEditor = try XCTUnwrap(ordinary.currentEditor())
        try click(target)
        XCTAssertTrue(owner.firstResponder === ordinaryEditor)
        XCTAssertTrue(ordinary.currentEditor() === ordinaryEditor)
        XCTAssertNil(search.currentEditor())
        XCTAssertEqual(store.configuration, configuration)
    }

    func testAlertAttachesToExplicitOwnerAndCompletesAfterResponseWithItsStoreTheme() throws {
        let store = store(), owner = window(), unrelated = window()
        store.update { $0.windowTheme = .dark }
        let originalAppearance = NSApp.appearance
        let alert = NSAlert()
        alert.messageText = "Test"
        alert.addButton(withTitle: "OK")
        var response: NSApplication.ModalResponse?

        WindowDialogs.present(alert, for: owner, store: store) { response = $0 }

        XCTAssertTrue(try sheet(of: owner) === alert.window)
        XCTAssertNil(unrelated.attachedSheet)
        XCTAssertNil(response)
        XCTAssertEqual(alert.window.appearance?.name, .darkAqua)
        store.update { $0.windowTheme = .light }
        XCTAssertEqual(alert.window.appearance?.name, .aqua)
        XCTAssertTrue(NSApp.appearance === originalAppearance)
        dismiss(alert.window, from: owner, response: .alertFirstButtonReturn)
        pump { response != nil }
        XCTAssertEqual(response, .alertFirstButtonReturn)
    }

    func testNewGroupInsertsImmediatelyAndEditsItsNameWithoutASheet() throws {
        let store = store(), owner = window(), menu = MenuEditorView(store: store)
        owner.contentView = menu; owner.makeKeyAndOrderFront(nil)
        let operations = store.configuration.operations
        let originalMenu = store.configuration.menu
        try button("menu-new-group", in: menu).performClick(nil)
        XCTAssertNil(owner.attachedSheet)
        XCTAssertEqual(store.configuration.menu.count, originalMenu.count + 1)
        XCTAssertEqual(Array(store.configuration.menu.dropLast()), originalMenu)
        let node = try XCTUnwrap(store.configuration.menu.last)
        XCTAssertEqual(node.kind, .group); XCTAssertEqual(node.name, L("新建分组"))
        pump { owner.firstResponder is NSTextView }
        let field = try XCTUnwrap(descendants(menu).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "menu-name-" + node.id })
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(owner.firstResponder === editor)
        editor.string = "输入的新分组"
        owner.makeFirstResponder(owner.contentView)
        pump { store.configuration.menu.last?.name == "输入的新分组" }
        XCTAssertEqual(store.configuration.menu.last?.name, "输入的新分组")
        XCTAssertEqual(store.configuration.operations, operations)
    }

    private func mouseEvent(_ type: NSEvent.EventType = .leftMouseDown, on view: NSView, clicks: Int) throws -> NSEvent {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: try XCTUnwrap(view.window).windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1))
    }
    func testMenuVisibilityMouseClickPersistsAndKeepsOtherReferencesIndependent() throws {
        let location = directory.appendingPathComponent("visibility")
        let store = ConfigurationStore(directory: location), owner = window(), op = operation()
        let child = MenuNode.reference(op.id), root = MenuNode.reference(op.id)
        let group = MenuNode(kind: .group, name: "Group", children: [child])
        store.update { $0.operations = [op]; $0.menu = [group, root] }
        let menu = MenuEditorView(store: store); owner.contentView = menu; owner.makeKeyAndOrderFront(nil)
        let table = try XCTUnwrap(descendants(menu).compactMap { $0 as? NSTableView }.first { $0.identifier?.rawValue == "menu-primary" })
        _ = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let check = try button("menu-visible-" + group.id, in: menu)
        XCTAssertTrue(table.validateProposedFirstResponder(check, for: nil))
        NSApp.postEvent(try mouseEvent(.leftMouseUp, on: check, clicks: 1), atStart: true)
        check.mouseDown(with: try mouseEvent(on: check, clicks: 1))
        XCTAssertEqual(store.configuration.menuNode(group.id)?.visible, false)
        XCTAssertEqual(ConfigurationStore(directory: location).configuration.menuNode(group.id)?.visible, false)
        XCTAssertEqual(store.configuration.menuNode(root.id)?.visible, true)
        XCTAssertEqual(store.configuration.menuNode(child.id)?.visible, true)
        let planned = MenuPlanner.items(configuration: store.configuration, context: .init(urls: [directory.appendingPathComponent("sample.txt")], directory: directory))
        XCTAssertEqual(planned.map { $0.node.id }, [root.id])
        check.performClick(nil)
        XCTAssertEqual(store.configuration.menuNode(group.id)?.visible, true)
    }
    func testMenuNameReceivesDoubleClickAndIconRequiresDoubleClick() throws {
        let store = store(), owner = window(), op = operation()
        let child = MenuNode.reference(op.id), group = MenuNode(kind: .group, name: "Group", children: [])
        store.update { $0.operations = [op]; $0.menu = [child, group] }
        let menu = MenuEditorView(store: store); owner.contentView = menu; owner.makeKeyAndOrderFront(nil)
        let table = try XCTUnwrap(descendants(menu).compactMap { $0 as? NSTableView }.first { $0.identifier?.rawValue == "menu-primary" })
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let name = try XCTUnwrap(cell.textField)
        XCTAssertTrue(table.validateProposedFirstResponder(name, for: nil))
        name.mouseDown(with: try mouseEvent(on: name, clicks: 2))
        let editor = try XCTUnwrap(name.currentEditor() as? NSTextView)
        XCTAssertTrue(owner.firstResponder === editor)
        editor.string = "仅修改菜单名称"
        owner.makeFirstResponder(table)
        pump { store.configuration.menuNode(child.id)?.name == "仅修改菜单名称" }
        XCTAssertEqual(store.configuration.menuNode(child.id)?.name, "仅修改菜单名称")
        XCTAssertEqual(store.configuration.operations, [op])
        let icon = try button("menu-icon-" + group.id, in: menu)
        icon.mouseDown(with: try mouseEvent(on: icon, clicks: 1))
        func catalogButton() -> NSButton? {
            NSApp.windows.compactMap(\.contentView).flatMap(descendants).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "catalog-icon-crab.star" }
        }
        XCTAssertNil(catalogButton())
        icon.mouseDown(with: try mouseEvent(on: icon, clicks: 2))
        pump { catalogButton() != nil }
        try XCTUnwrap(catalogButton()).performClick(nil)
        XCTAssertEqual(store.configuration.menuNode(group.id)?.iconID, "crab.star")
    }

    func testRemoveGroupSheetCancelsAndThenRemovesOnlyItsReferences() throws {
        let store = store(), owner = window(), op = operation("kept-operation")
        let group = MenuNode(kind: .group, name: "待移除分组", children: [.reference(op.id)])
        store.update { $0.operations = [op]; $0.menu = [group, .reference(op.id)] }
        let snapshot = store.configuration, menu = MenuEditorView(store: store)
        owner.contentView = menu
        let table = try XCTUnwrap(descendants(menu).compactMap { $0 as? NSTableView }.first { $0.identifier?.rawValue == "menu-primary" })
        table.selectRowIndexes([0], byExtendingSelection: false)
        try button("menu-primary-remove", in: menu).performClick(nil)
        var dialog = try sheet(of: owner)
        XCTAssertEqual(store.configuration, snapshot)
        dismiss(dialog, from: owner, response: .alertSecondButtonReturn)
        XCTAssertEqual(store.configuration, snapshot)

        table.selectRowIndexes([0], byExtendingSelection: false)
        try button("menu-primary-remove", in: menu).performClick(nil)
        dialog = try sheet(of: owner)
        dismiss(dialog, from: owner, response: .alertFirstButtonReturn)
        pump { store.configuration.menuNode(group.id) == nil }
        XCTAssertEqual(store.configuration.operations, [op])
        XCTAssertEqual(store.configuration.referenceCount(op.id), 1)
        XCTAssertEqual(store.configuration.menu, Array(snapshot.menu.suffix(1)))
    }

    func testPrimaryMenuResetConfirmsOnOwnerCancelsWithoutSavingAndCommitsOnlyMenuOnce() throws {
        let location = directory.appendingPathComponent("primary-reset")
        let store = ConfigurationStore(directory: location), owner = window(), unrelated = window()
        let builtIn = try XCTUnwrap(store.configuration.operations.first { $0.id == "builtin.template.txt" })
        let custom = operation("retained-custom")
        XCTAssertTrue(store.update {
            $0.operations = [builtIn, custom]
            $0.menu = [.init(kind: .group, name: "Custom group", children: [.reference(custom.id)])]
            $0.languageCode = "zh-Hans"; $0.windowTheme = .dark
        })
        let original = store.configuration
        let file = location.appendingPathComponent("operations-v1.json")
        let originalBytes = try Data(contentsOf: file)
        let editor = MenuEditorView(store: store); owner.contentView = editor
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged,
            object: store, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        try button("menu-primary-reset", in: editor).performClick(nil)
        var dialog = try sheet(of: owner)
        XCTAssertNil(unrelated.attachedSheet)
        XCTAssertEqual(dialog.appearance?.name, .darkAqua)
        XCTAssertEqual(store.configuration, original)
        dismiss(dialog, from: owner, response: .alertSecondButtonReturn)
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        XCTAssertEqual(updates, 0)

        try button("menu-primary-reset", in: editor).performClick(nil)
        dialog = try sheet(of: owner)
        dismiss(dialog, from: owner, response: .alertFirstButtonReturn)
        var expected = original; expected.menu = DefaultMenuLayout.nodes(for: original.operations)
        pump { store.configuration == expected }
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(ConfigurationStore(directory: location).configuration, expected)
    }

    func testSecondaryMenuResetCancelsRestoresOnlySelectedGroupAndIgnoresDeletedTarget() throws {
        let location = directory.appendingPathComponent("secondary-reset")
        let store = ConfigurationStore(directory: location), owner = window()
        let defaultGroup = try XCTUnwrap(store.configuration.menu.first)
        let custom = operation("kept-custom")
        var selectedGroup = defaultGroup
        selectedGroup.name = "Renamed default group"; selectedGroup.iconID = "crab.heart"; selectedGroup.visible = false
        selectedGroup.children = [.reference(custom.id)]
        let otherGroup = MenuNode(kind: .group, name: "Other group", children: [.reference(custom.id)])
        XCTAssertTrue(store.update { $0.operations.append(custom); $0.menu = [selectedGroup, otherGroup] })
        let original = store.configuration
        let file = location.appendingPathComponent("operations-v1.json")
        let originalBytes = try Data(contentsOf: file)
        let editor = MenuEditorView(store: store); owner.contentView = editor
        let table = try XCTUnwrap(descendants(editor).compactMap { $0 as? NSTableView }.first { $0.identifier?.rawValue == "menu-primary" })
        table.selectRowIndexes([0], byExtendingSelection: false)
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged,
            object: store, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        try button("menu-secondary-reset", in: editor).performClick(nil)
        var dialog = try sheet(of: owner)
        dismiss(dialog, from: owner, response: .alertSecondButtonReturn)
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        XCTAssertEqual(updates, 0)

        try button("menu-secondary-reset", in: editor).performClick(nil)
        dialog = try sheet(of: owner)
        dismiss(dialog, from: owner, response: .alertFirstButtonReturn)
        var expected = original; expected.menu[0].children = defaultGroup.children
        pump { store.configuration == expected }
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(ConfigurationStore(directory: location).configuration, expected)

        try button("menu-secondary-reset", in: editor).performClick(nil)
        dialog = try sheet(of: owner)
        let replacement = MenuNode(kind: .group, name: selectedGroup.name, children: [.reference(custom.id)])
        XCTAssertTrue(store.update { $0.removeMenuNode(selectedGroup.id); $0.menu.insert(replacement, at: 0) })
        editor.reload(); table.selectRowIndexes([0], byExtendingSelection: false)
        let whileConfirming = store.configuration
        let whileConfirmingBytes = try Data(contentsOf: file)
        let updatesBeforeConfirmation = updates
        dismiss(dialog, from: owner, response: .alertFirstButtonReturn)
        XCTAssertEqual(store.configuration, whileConfirming)
        XCTAssertEqual(try Data(contentsOf: file), whileConfirmingBytes)
        XCTAssertEqual(updates, updatesBeforeConfirmation, "A removed target must not produce a save or reset its replacement at the same row.")
    }

    func testAddReferencesSheetCancelsAndUsesStableIDsAfterConfigurationChanges() throws {
        let store = store(), owner = window(), kept = operation("kept"), removed = operation("removed")
        let group = MenuNode(kind: .group, name: "目标分组")
        store.update { $0.operations = [kept, removed]; $0.menu = [group] }
        let snapshot = store.configuration
        MenuEditorView.addReferences(ids: [kept.id, removed.id], store: store, for: owner)
        var dialog = try sheet(of: owner)
        XCTAssertEqual(store.configuration, snapshot)
        dismiss(dialog, from: owner, response: .alertSecondButtonReturn)
        XCTAssertEqual(store.configuration, snapshot)

        MenuEditorView.addReferences(ids: [kept.id, removed.id], store: store, for: owner)
        dialog = try sheet(of: owner)
        let picker = try XCTUnwrap(descendants(try XCTUnwrap(dialog.contentView)).compactMap { $0 as? NSPopUpButton }.first)
        picker.selectItem(at: 1)
        store.update { $0.removeOperations([removed.id]) }
        dismiss(dialog, from: owner, response: .alertFirstButtonReturn)
        pump { store.configuration.referenceCount(kept.id) == 1 }
        XCTAssertEqual(store.configuration.menu.count, 1)
        XCTAssertEqual(store.configuration.menu[0].id, group.id)
        XCTAssertEqual(store.configuration.menu[0].children.map(\.operationID), [kept.id])
        XCTAssertEqual(store.configuration.referenceCount(removed.id), 0)
    }

    func testLibraryBatchDeleteCancelsThenRemovesOnlySelectedCustomOperationsAndReferencesOnce() throws {
        let location = directory.appendingPathComponent("batch-delete")
        let store = ConfigurationStore(directory: location)
        let builtIn = try XCTUnwrap(OperationRegistry.defaults().first)
        let removed = operation("batch-selected-custom"), kept = operation("batch-unselected-custom")
        let builtInReference = MenuNode.reference(builtIn.id)
        let removedRoot = MenuNode.reference(removed.id), removedChild = MenuNode.reference(removed.id)
        let keptChild = MenuNode.reference(kept.id)
        let group = MenuNode(kind: .group, name: "保留分组", children: [removedChild, keptChild])
        XCTAssertTrue(store.update {
            $0.operations = [builtIn, removed, kept]
            $0.menu = [builtInReference, removedRoot, group]
        })
        let original = store.configuration
        let file = location.appendingPathComponent("operations-v1.json")
        let originalBytes = try Data(contentsOf: file)
        let settings = SettingsWindowController(store: store, loadPermissionStatuses: { $0([]) })
        let owner = try XCTUnwrap(settings.window)
        windows.append(owner); owner.animationBehavior = .none
        settings.showWindow(nil)
        let root = try XCTUnwrap(owner.contentView)
        func batch() throws -> NSButton { try button("library-batch", in: root) }
        func clickBatch() throws {
            let control = try batch()
            XCTAssertTrue(control.isEnabled)
            XCTAssertNil(control.menu)
            control.performClick(nil)
        }
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged,
            object: store, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertEqual(try batch().title, L("批量删除"))
        XCTAssertTrue(try batch().isEnabled)
        XCTAssertFalse(try batch() is OperationAddButton)
        try clickBatch()
        XCTAssertEqual(try batch().title, L("删除"))
        XCTAssertFalse(try batch().isEnabled)
        XCTAssertTrue(try button("library-batch-cancel", in: root).isEnabled)
        root.layoutSubtreeIfNeeded()
        let collection = try XCTUnwrap(descendants(root).compactMap { $0 as? NSCollectionView }.first)
        collection.layoutSubtreeIfNeeded()
        pump { (0..<3).allSatisfy { collection.item(at: IndexPath(item: $0, section: 0)) != nil } }
        let builtInCard = try XCTUnwrap(collection.item(at: IndexPath(item: 0, section: 0)))
        XCTAssertFalse(descendants(builtInCard.view).contains { $0.identifier?.rawValue == "operation-select-" + builtIn.id })
        let selectedCard = try XCTUnwrap(collection.item(at: IndexPath(item: 1, section: 0)))
        try button("operation-select-" + removed.id, in: selectedCard.view).performClick(nil)
        XCTAssertTrue(try batch().isEnabled)
        XCTAssertEqual(updates, 0)

        try clickBatch()
        var dialog = try sheet(of: owner)
        let dialogText = descendants(try XCTUnwrap(dialog.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")
        XCTAssertTrue(dialogText.contains(LF("将删除 %d 个操作及其 %d 处菜单引用；原始文件不受影响。", 1, 2)))
        dismiss(dialog, from: owner, response: .alertSecondButtonReturn)
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(try batch().title, L("删除"))
        XCTAssertTrue(try batch().isEnabled, "Cancelling confirmation must retain the selected custom operation.")
        let retainedSelection = try XCTUnwrap(collection.item(at: IndexPath(item: 1, section: 0)))
        XCTAssertEqual(try button("operation-select-" + removed.id, in: retainedSelection.view).state, .on)

        try clickBatch()
        dialog = try sheet(of: owner)
        dismiss(dialog, from: owner, response: .alertFirstButtonReturn)
        pump { store.configuration.operations.count == 2 }
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(store.configuration.operations, [builtIn, kept])
        var keptGroup = group; keptGroup.children = [keptChild]
        XCTAssertEqual(store.configuration.menu, [builtInReference, keptGroup])
        XCTAssertEqual(store.configuration.referenceCount(removed.id), 0)
        XCTAssertEqual(store.configuration.referenceCount(builtIn.id), 1)
        XCTAssertEqual(store.configuration.referenceCount(kept.id), 1)
        XCTAssertEqual(ConfigurationStore(directory: location).configuration, store.configuration)
        XCTAssertEqual(try batch().title, L("删除"))
        XCTAssertFalse(try batch().isEnabled)
        XCTAssertTrue(try button("library-batch-cancel", in: root).isEnabled)
        let afterDeletion = store.configuration
        let afterDeletionBytes = try Data(contentsOf: file)
        try button("library-batch-cancel", in: root).performClick(nil)
        XCTAssertEqual(try batch().title, L("批量删除"))
        XCTAssertTrue(try batch().isEnabled)
        XCTAssertFalse(descendants(root).contains { $0.identifier?.rawValue == "library-batch-cancel" && !$0.isHidden })
        XCTAssertEqual(store.configuration, afterDeletion)
        XCTAssertEqual(try Data(contentsOf: file), afterDeletionBytes)
        XCTAssertEqual(updates, 1)
    }

    func testOperationEditorCancelEndsSheetWithoutSavingDraft() throws {
        let store = store(), owner = window(), op = operation()
        let snapshot = store.configuration
        let editor = OperationEditor(operation: op, existing: false, store: store)
        editor.present(asSheetFor: owner)
        let dialog = try sheet(of: owner)
        editor.updateDraft { $0.name = "取消的修改" }
        XCTAssertEqual(store.configuration, snapshot)
        editor.close()
        pump { dialog.sheetParent == nil && owner.attachedSheet == nil }
        XCTAssertEqual(store.configuration, snapshot)
    }

    func testLibraryDoubleClickOpensBuiltInReadOnlyDetailsAndCustomEditor() throws {
        let location = directory.appendingPathComponent("library-details")
        let store = ConfigurationStore(directory: location)
        let builtIn = try XCTUnwrap(OperationRegistry.defaults().first)
        let custom = operation("editable-custom")
        XCTAssertTrue(store.update { $0.operations = [builtIn, custom]; $0.menu = [] })
        let snapshot = store.configuration
        let file = location.appendingPathComponent("operations-v1.json")
        let savedBytes = try Data(contentsOf: file)
        let settings = SettingsWindowController(store: store,
                                                loadPermissionStatuses: { $0([]) })
        let owner = try XCTUnwrap(settings.window)
        windows.append(owner); owner.animationBehavior = .none
        settings.showWindow(nil)
        let root = try XCTUnwrap(owner.contentView)
        let collection = try XCTUnwrap(descendants(root).compactMap { $0 as? NSCollectionView }.first)
        collection.layoutSubtreeIfNeeded()
        let firstIndex = IndexPath(item: 0, section: 0)
        pump { collection.item(at: firstIndex) != nil }
        let builtInCard = try XCTUnwrap(collection.item(at: firstIndex))
        let body = try XCTUnwrap(descendants(builtInCard.view).compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(builtInCard.view.menu?.items.map(\.title), [L("加入菜单…")])
        body.mouseDown(with: try mouseEvent(on: body, clicks: 1))
        XCTAssertNil(owner.attachedSheet)
        body.mouseDown(with: try mouseEvent(on: body, clicks: 2))
        let details = try sheet(of: owner)
        XCTAssertEqual(details.title, L("查看操作"))
        let detailsRoot = try XCTUnwrap(details.contentView)
        let name = try XCTUnwrap(descendants(detailsRoot).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "operation-name" })
        XCTAssertFalse(name.isEditable)
        XCTAssertTrue(name.isSelectable)
        XCTAssertFalse(descendants(detailsRoot).contains { $0.identifier?.rawValue == "operation-save" })
        try button("operation-close", in: detailsRoot).performClick(nil)
        pump { owner.attachedSheet == nil && details.sheetParent == nil }
        XCTAssertEqual(store.configuration, snapshot)
        XCTAssertEqual(try Data(contentsOf: file), savedBytes)

        let customIndex = IndexPath(item: 1, section: 0)
        pump { collection.item(at: customIndex) != nil }
        let customCard = try XCTUnwrap(collection.item(at: customIndex))
        let customBody = try XCTUnwrap(descendants(customCard.view).compactMap { $0 as? NSButton }.first)
        customBody.mouseDown(with: try mouseEvent(on: customBody, clicks: 2))
        let editor = try sheet(of: owner)
        XCTAssertEqual(editor.title, L("编辑操作"))
        let editorRoot = try XCTUnwrap(editor.contentView)
        let editableName = try XCTUnwrap(descendants(editorRoot).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "operation-name" })
        XCTAssertTrue(editableName.isEditable)
        XCTAssertTrue(try button("operation-save", in: editorRoot).isEnabled)
        let cancel = try XCTUnwrap(descendants(editorRoot).compactMap { $0 as? NSButton }.first { $0.title == L("取消") })
        cancel.performClick(nil)
        pump { owner.attachedSheet == nil }
        XCTAssertEqual(store.configuration, snapshot)
    }

    func testOperationEditorSaveEndsSheetAndPersistsDraftOnce() throws {
        let store = store(), owner = window(), op = operation()
        let snapshot = store.configuration
        let editor = OperationEditor(operation: op, existing: false, store: store)
        editor.present(asSheetFor: owner)
        let dialog = try sheet(of: owner)
        editor.updateDraft { $0.name = "保存的修改" }
        XCTAssertEqual(store.configuration, snapshot)
        XCTAssertTrue(editor.save())
        pump { dialog.sheetParent == nil && owner.attachedSheet == nil }
        XCTAssertEqual(store.configuration.operations.filter { $0.id == op.id }.count, 1)
        XCTAssertEqual(store.configuration.operations.first { $0.id == op.id }?.name, "保存的修改")
        XCTAssertEqual(store.configuration.menu, snapshot.menu)
    }

    func testSettingsKeepsOneEditorSheetWhenAddIsTriggeredTwice() throws {
        let store = store()
        let settings = SettingsWindowController(store: store)
        let owner = try XCTUnwrap(settings.window)
        windows.append(owner)
        owner.orderFront(nil)
        settings.addOperation(kind: "tool")
        let first = try sheet(of: owner)
        settings.addOperation(kind: "tool")
        XCTAssertTrue(owner.attachedSheet === first)
        XCTAssertEqual(owner.sheets.count, 1)
        let cancel = try XCTUnwrap(descendants(try XCTUnwrap(first.contentView)).compactMap { $0 as? NSButton }.first { $0.title == L("取消") })
        cancel.performClick(nil)
        pump { owner.attachedSheet == nil }
        settings.addOperation(kind: "tool")
        let second = try sheet(of: owner)
        XCTAssertFalse(first === second)
        dismiss(second, from: owner, response: .cancel)
    }

    func testFilePickerOnEditorSheetRetainsTheNestedOwnerAndCancelRestoresEditor() throws {
        let store = store(), owner = window()
        let editor = OperationEditor(operation: operation(), existing: false, store: store)
        editor.present(asSheetFor: owner)
        let editorWindow = try sheet(of: owner)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = directory
        var response: NSApplication.ModalResponse?
        WindowDialogs.present(panel, for: editorWindow, store: store) { response = $0 }
        XCTAssertTrue(try sheet(of: editorWindow) === panel)
        XCTAssertTrue(owner.attachedSheet === editorWindow)
        XCTAssertTrue(editorWindow.sheetParent === owner)
        panel.cancel(nil)
        pump { response != nil && editorWindow.attachedSheet == nil }
        XCTAssertEqual(response, .cancel)
        XCTAssertTrue(owner.attachedSheet === editorWindow)
        XCTAssertTrue(editorWindow.sheetParent === owner)
        editor.close()
        pump { owner.attachedSheet == nil }
    }
}

private final class SearchFocusMouseTarget: NSView {
    private(set) var mouseDownCount = 0
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { mouseDownCount += 1 }
}
