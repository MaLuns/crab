import AppKit
import XCTest
@testable import Crab

@MainActor
final class OperationPickerTests: XCTestCase {
    private var directory: URL!
    private var language = ""
    private var windows: [NSWindow] = []
    private var pickers: [OperationPickerWindowController] = []

    private struct Scene {
        let store: ConfigurationStore
        let owner: NSWindow
        let menu: MenuEditorView
        let groupID: String
        let toolID: String
        let directoryID: String
        let scriptID: String
        let builtInID: String
    }

    override func setUpWithError() throws {
        language = AppLocalization.languageCode
        AppLocalization.languageCode = "zh-Hans"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-OperationPicker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for picker in pickers { picker.close() }
        for window in windows.reversed() {
            for sheet in window.sheets { window.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
            window.close()
        }
        pickers = []; windows = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        AppLocalization.languageCode = language
        try? FileManager.default.removeItem(at: directory)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func find<T: NSView>(_ identifier: String, in root: NSView, as type: T.Type = T.self) throws -> T {
        try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == identifier } as? T, identifier)
    }

    private func pump(until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func makeScene() throws -> Scene {
        let location = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        let script = location.appendingPathComponent("sample-script.sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        let tool = OperationRecord(id: "picker.tool", name: "路径操作", parameters: .tool(.init(action: .copyPath, hideOriginals: false, confirmDeletion: false, newTab: true)))
        let folder = OperationRecord(id: "picker.directory", name: "目标目录", parameters: .directory(location.path))
        let scriptOperation = OperationRecord(id: "picker.script", name: "脚本样例", parameters: .script(script.path))
        let builtIn = OperationRecord(id: "builtin.tool.copyName", name: "内置拷贝名称", parameters: .tool(.init(action: .copyName)))
        let group = MenuNode(id: "picker.group", kind: .group, name: "目标分组")
        let store = ConfigurationStore(directory: location.appendingPathComponent("configuration", isDirectory: true))
        XCTAssertTrue(store.update {
            $0.operations = [tool, folder, scriptOperation, builtIn]
            $0.menu = [group, .reference(tool.id)]
            $0.languageCode = "zh-Hans"
        })
        let owner = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 760),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        owner.title = "Crab · 添加操作验收"; owner.isReleasedWhenClosed = false; owner.animationBehavior = .none
        WindowAppearance.bind(owner, to: store)
        let menu = MenuEditorView(store: store); owner.contentView = menu
        windows.append(owner); owner.makeKeyAndOrderFront(nil); menu.layoutSubtreeIfNeeded()
        let primary: NSTableView = try find("menu-primary", in: menu)
        _ = primary.view(atColumn: 0, row: 0, makeIfNecessary: true)
        primary.selectRowIndexes([0], byExtendingSelection: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return Scene(store: store, owner: owner, menu: menu, groupID: group.id, toolID: tool.id,
                     directoryID: folder.id, scriptID: scriptOperation.id, builtInID: builtIn.id)
    }

    private func sheet(in scene: Scene) throws -> NSWindow {
        pump { scene.owner.attachedSheet != nil }
        let sheet = try XCTUnwrap(scene.owner.attachedSheet)
        XCTAssertTrue(sheet.sheetParent === scene.owner)
        sheet.animationBehavior = .none
        try XCTUnwrap(sheet.contentView).layoutSubtreeIfNeeded()
        return sheet
    }

    private func root(of sheet: NSWindow) throws -> NSView { try XCTUnwrap(sheet.contentView) }

    private func waitForCard(_ operationID: String, in sheet: NSWindow) throws -> NSButton {
        let root = try root(of: sheet)
        pump { self.descendants(root).contains { $0.identifier?.rawValue == "operation-picker-toggle-" + operationID } }
        return try find("operation-picker-toggle-" + operationID, in: root)
    }

    private func toggle(_ operationID: String, in sheet: NSWindow) throws {
        _ = try waitForCard(operationID, in: sheet)
        let expected = try !selected(operationID, in: sheet)
        try waitForCard(operationID, in: sheet).performClick(nil)
        let content = try root(of: sheet)
        content.layoutSubtreeIfNeeded()
        pump {
            guard let badge = self.descendants(content).first(where: { $0.identifier?.rawValue == "operation-picker-selected-" + operationID }) else { return false }
            return !badge.isHidden == expected
        }
    }

    private func selected(_ operationID: String, in sheet: NSWindow) throws -> Bool {
        let content = try root(of: sheet)
        let collection: NSCollectionView = try find("operation-picker-list", in: content)
        content.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(collection.visibleItems().first { $0.view.identifier?.rawValue == "operation-picker-card-" + operationID })
        let badge: NSView = try find("operation-picker-selected-" + operationID, in: item.view)
        return !badge.isHidden
    }

    private func cancel(_ sheet: NSWindow, scene: Scene) throws {
        let cancel: NSButton = try find("operation-picker-cancel", in: root(of: sheet))
        cancel.performClick(nil)
        pump { scene.owner.attachedSheet == nil && sheet.sheetParent == nil }
    }

    private func confirm(_ sheet: NSWindow, scene: Scene) throws {
        let add: NSButton = try find("operation-picker-add", in: root(of: sheet))
        XCTAssertTrue(add.isEnabled)
        add.performClick(nil)
        pump { scene.owner.attachedSheet == nil && sheet.sheetParent == nil }
    }

    private func directPicker(in scene: Scene, completion: @escaping ([String]) -> Void) throws -> (OperationPickerWindowController, NSWindow) {
        let picker = OperationPickerWindowController(store: scene.store)
        pickers.append(picker)
        picker.present(asSheetFor: scene.owner, completion: completion)
        return (picker, try sheet(in: scene))
    }

    private func setSearch(_ text: String, picker: OperationPickerWindowController, sheet: NSWindow) throws {
        let search: NSSearchField = try find("operation-picker-search", in: root(of: sheet))
        search.stringValue = text
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        try root(of: sheet).layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func setType(_ kind: String?, sheet: NSWindow) throws {
        let popup: NSPopUpButton = try find("operation-picker-type", in: root(of: sheet))
        if let kind {
            let index = try XCTUnwrap(OperationRegistry.shared.definitions.firstIndex { $0.kind == kind })
            popup.selectItem(at: index + 1)
        } else { popup.selectItem(at: 0) }
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup))
        try root(of: sheet).layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func click(_ view: NSView, in sheet: NSWindow, at point: NSPoint? = nil) throws {
        let location = view.convert(point ?? NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }
        NSApp.postEvent(try event(.leftMouseUp), atStart: true)
        sheet.sendEvent(try event(.leftMouseDown))
    }

    private func captureFocusPreview(_ name: String, sheet: NSWindow) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["CRAB_PICKER_FOCUS_PREVIEW_DIR"] ?? environment["TEST_RUNNER_CRAB_PICKER_FOCUS_PREVIEW_DIR"] else { return }
        let content = try root(of: sheet)
        content.layoutSubtreeIfNeeded()
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }

    func testSearchStartsUnfocusedOnPresentationAndReopeningButTabCanEdit() throws {
        let scene = try makeScene(), original = scene.store.configuration
        var callbacks = 0
        let (picker, sheet) = try directPicker(in: scene) { _ in callbacks += 1 }
        let content = try root(of: sheet)
        let search: NSSearchField = try find("operation-picker-search", in: content)
        XCTAssertTrue(sheet.initialFirstResponder === content)
        XCTAssertTrue(sheet.firstResponder === content)
        XCTAssertNil(search.currentEditor())

        sheet.selectNextKeyView(nil)
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        XCTAssertTrue(sheet.firstResponder === editor)
        editor.insertText("目录", replacementRange: NSRange(location: 0, length: 0))
        _ = try waitForCard(scene.directoryID, in: sheet)
        let collection: NSCollectionView = try find("operation-picker-list", in: content)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)

        // Refresh the real picker through its notification path without writing configuration.
        NotificationCenter.default.post(name: AppConstants.localConfigChanged, object: scene.store)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertTrue(search.currentEditor() === editor)
        XCTAssertTrue(sheet.firstResponder === editor)
        XCTAssertEqual(search.stringValue, "目录")
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)

        try cancel(sheet, scene: scene)
        picker.present(asSheetFor: scene.owner) { _ in callbacks += 1 }
        let reopened = try self.sheet(in: scene)
        XCTAssertTrue(reopened === sheet)
        XCTAssertTrue(reopened.firstResponder === content)
        XCTAssertNil(search.currentEditor())
        XCTAssertEqual(search.stringValue, "目录")
        reopened.selectNextKeyView(nil)
        XCTAssertNotNil(search.currentEditor())
        try cancel(reopened, scene: scene)
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(scene.store.configuration, original)
    }

    func testOutsideClicksBlurSearchPreserveFiltersAndStillSelectTheClickedCard() throws {
        let scene = try makeScene(), original = scene.store.configuration
        var received: [String]?
        let (_, sheet) = try directPicker(in: scene) { received = $0 }
        let content = try root(of: sheet)
        let search: NSSearchField = try find("operation-picker-search", in: content)
        let collection: NSCollectionView = try find("operation-picker-list", in: content)
        let title = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == L("添加操作…") })
        try toggle(scene.toolID, in: sheet)
        try setType("directory", sheet: sheet)
        _ = try waitForCard(scene.directoryID, in: sheet)
        search.selectText(nil)
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        editor.insertText("目录", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try click(search, in: sheet)
        XCTAssertTrue(search.currentEditor() === editor, "A click inside the search field keeps its editor active.")
        try captureFocusPreview("picker-search-focused", sheet: sheet)

        try click(title, in: sheet)
        XCTAssertNil(search.currentEditor())
        XCTAssertEqual(search.stringValue, "目录")
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        search.selectText(nil)
        XCTAssertNotNil(search.currentEditor())
        // This point is in the empty collection area below the single visible result.
        try click(content, in: sheet, at: NSPoint(x: 320, y: 450))
        XCTAssertNil(search.currentEditor())
        XCTAssertEqual(search.stringValue, "目录")
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)

        search.selectText(nil)
        XCTAssertNotNil(search.currentEditor())
        content.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        let currentItem = try XCTUnwrap(collection.item(at: IndexPath(item: 0, section: 0)))
        let card: NSButton = try find("operation-picker-toggle-" + scene.directoryID, in: currentItem.view)
        let cardPoint = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: content.superview)
        let hit = try XCTUnwrap(content.hitTest(cardPoint))
        XCTAssertTrue(hit === card || hit.isDescendant(of: card), "Card hit target: \(type(of: hit))")
        XCTAssertTrue(card.window === sheet)
        try click(card, in: sheet)
        pump { (try? self.selected(scene.directoryID, in: sheet)) == true }
        XCTAssertNil(search.currentEditor())
        XCTAssertEqual(search.stringValue, "目录")
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        let count: NSTextField = try find("operation-picker-count", in: content)
        XCTAssertEqual(count.stringValue, LF("已选择 %d 项", 2))
        try captureFocusPreview("picker-search-unfocused", sheet: sheet)

        XCTAssertEqual(scene.store.configuration, original)
        try confirm(sheet, scene: scene)
        XCTAssertEqual(received, [scene.toolID, scene.directoryID])
        XCTAssertEqual(scene.store.configuration, original, "A directly presented picker only returns IDs; it must not write configuration.")
    }

    func testPickerBelongsToOwnerStartsWithDisabledAddAndHasNoManagementActions() throws {
        let scene = try makeScene(), original = scene.store.configuration
        var calls = 0
        let (_, sheet) = try directPicker(in: scene) { _ in calls += 1 }
        let content = try root(of: sheet)
        let add: NSButton = try find("operation-picker-add", in: content)
        XCTAssertFalse(add.isEnabled)
        for id in [scene.toolID, scene.directoryID, scene.scriptID, scene.builtInID] {
            _ = try waitForCard(id, in: sheet)
            XCTAssertFalse(try selected(id, in: sheet))
            let card: NSView = try find("operation-picker-card-" + id, in: content)
            for view in descendants(card) { XCTAssertNil(view.menu, id + " must not expose operation management.") }
        }
        let forbidden = Set([L("新增操作…"), L("编辑"), L("复制"), L("删除")])
        XCTAssertFalse(descendants(content).compactMap { ($0 as? NSButton)?.title }.contains { forbidden.contains($0) })
        add.performClick(nil)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(scene.store.configuration, original)
        try cancel(sheet, scene: scene)
    }

    func testCardMultiselectionBadgesAndStableIDsSurviveSearchAndTypeFilters() throws {
        let scene = try makeScene()
        var received: [String]?
        let (picker, sheet) = try directPicker(in: scene) { received = $0 }
        try toggle(scene.directoryID, in: sheet); try toggle(scene.toolID, in: sheet)
        XCTAssertTrue(try selected(scene.directoryID, in: sheet)); XCTAssertTrue(try selected(scene.toolID, in: sheet))
        let add: NSButton = try find("operation-picker-add", in: root(of: sheet))
        XCTAssertTrue(add.isEnabled)
        try setSearch("脚本样例", picker: picker, sheet: sheet)
        _ = try waitForCard(scene.scriptID, in: sheet)
        try setType("script", sheet: sheet)
        _ = try waitForCard(scene.scriptID, in: sheet)
        try setSearch("", picker: picker, sheet: sheet)
        try setType(nil, sheet: sheet)
        _ = try waitForCard(scene.toolID, in: sheet)
        XCTAssertTrue(try selected(scene.toolID, in: sheet)); XCTAssertTrue(try selected(scene.directoryID, in: sheet))
        XCTAssertFalse(try selected(scene.scriptID, in: sheet))
        try confirm(sheet, scene: scene)
        XCTAssertEqual(received, [scene.toolID, scene.directoryID])
    }

    func testCancelClosesSheetWithoutChangingMenuOrOperationLibrary() throws {
        let scene = try makeScene(), original = scene.store.configuration
        var received: [String]?
        let (picker, sheet) = try directPicker(in: scene) { received = $0 }
        var closes = 0; picker.didClose = { closes += 1 }
        try toggle(scene.toolID, in: sheet); try toggle(scene.scriptID, in: sheet)
        try cancel(sheet, scene: scene)
        XCTAssertNil(received)
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(scene.store.configuration, original)
    }

    func testRootAndGroupBatchAdditionEachCommitOnceAndKeepOperationParameters() throws {
        for destinationIsGroup in [false, true] {
            let scene = try makeScene(), original = scene.store.configuration
            let identifier = destinationIsGroup ? "menu-secondary-add" : "menu-primary-add"
            let open: NSButton = try find(identifier, in: scene.menu)
            XCTAssertTrue(open.isEnabled); open.performClick(nil)
            let sheet = try sheet(in: scene)
            try toggle(scene.scriptID, in: sheet); try toggle(scene.toolID, in: sheet)
            XCTAssertEqual(scene.store.configuration, original)
            var updates = 0
            let observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged, object: scene.store, queue: nil) { _ in updates += 1 }
            try confirm(sheet, scene: scene)
            NotificationCenter.default.removeObserver(observer)
            XCTAssertEqual(updates, 1, destinationIsGroup ? "group" : "root")
            XCTAssertEqual(scene.store.configuration.operations, original.operations)
            if destinationIsGroup {
                XCTAssertEqual(scene.store.configuration.menu.map(\.id), original.menu.map(\.id))
                XCTAssertEqual(scene.store.configuration.menuNode(scene.groupID)?.children.map(\.operationID), [scene.toolID, scene.scriptID])
            } else {
                XCTAssertEqual(Array(scene.store.configuration.menu.prefix(original.menu.count)), original.menu)
                XCTAssertEqual(scene.store.configuration.menu.suffix(2).map(\.operationID), [scene.toolID, scene.scriptID])
                XCTAssertEqual(scene.store.configuration.menuNode(scene.groupID)?.children, [])
            }
            XCTAssertEqual(scene.store.configuration.menu.flatMap { [$0.id] + $0.children.map(\.id) }.count,
                           Set(scene.store.configuration.menu.flatMap { [$0.id] + $0.children.map(\.id) }).count)
        }
    }

    func testDeletedOperationsAreIgnoredAndDeletedDestinationNeverFallsBackToRoot() throws {
        let rootScene = try makeScene()
        let rootOpen: NSButton = try find("menu-primary-add", in: rootScene.menu)
        rootOpen.performClick(nil)
        let rootSheet = try sheet(in: rootScene)
        try toggle(rootScene.toolID, in: rootSheet); try toggle(rootScene.scriptID, in: rootSheet)
        XCTAssertTrue(rootScene.store.update { $0.removeOperations([rootScene.toolID]) })
        try confirm(rootSheet, scene: rootScene)
        XCTAssertNil(rootScene.store.configuration.menu.last?.children.first)
        XCTAssertEqual(rootScene.store.configuration.menu.last?.operationID, rootScene.scriptID)
        XCTAssertFalse(rootScene.store.configuration.menu.contains { $0.operationID == rootScene.toolID })

        let groupScene = try makeScene()
        let groupOpen: NSButton = try find("menu-secondary-add", in: groupScene.menu)
        groupOpen.performClick(nil)
        let groupSheet = try sheet(in: groupScene)
        try toggle(groupScene.toolID, in: groupSheet); try toggle(groupScene.scriptID, in: groupSheet)
        XCTAssertTrue(groupScene.store.update { $0.removeMenuNode(groupScene.groupID) })
        let afterDeletion = groupScene.store.configuration
        try confirm(groupSheet, scene: groupScene)
        XCTAssertEqual(groupScene.store.configuration, afterDeletion)
        XCTAssertNil(groupScene.store.configuration.menuNode(groupScene.groupID))
    }
}
