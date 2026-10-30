import AppKit
import XCTest
@testable import Crab

@MainActor
final class MenuEditorInteractionTests: XCTestCase {
    private var directory: URL!
    private var language = ""
    private var controllers: [SettingsWindowController] = []

    private struct Scene {
        let controller: SettingsWindowController
        let store: ConfigurationStore
        let directory: URL
        let window: NSWindow
        let root: NSView
        let menu: MenuEditorView
        let primary: NSTableView
        let operationID: String
        let groupID: String
        let childID: String
        let otherGroupID: String
        let otherChildID: String
        let rootID: String
    }

    override func setUpWithError() throws {
        language = AppLocalization.languageCode
        AppLocalization.languageCode = "zh-Hans"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-MenuInteraction-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for controller in controllers {
            if let window = controller.window {
                window.makeFirstResponder(nil)
                for sheet in window.sheets { window.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
                window.close()
            }
        }
        controllers = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        AppLocalization.languageCode = language
        try? FileManager.default.removeItem(at: directory)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func view<T: NSView>(_ identifier: String, in root: NSView, as type: T.Type = T.self) throws -> T {
        try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == identifier } as? T)
    }

    private func pump(until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func makeScene() throws -> Scene {
        let location = directory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(directory: location)
        let op = OperationRecord(id: "qa.copy-path", name: "拷贝路径", parameters: .tool(.init(action: .copyPath)))
        let child = MenuNode(id: "qa.child-a", kind: .operation, operationID: op.id, name: "分组中的操作")
        let otherChild = MenuNode(id: "qa.child-b", kind: .operation, operationID: op.id, name: "另一处引用")
        let group = MenuNode(id: "qa.group-a", kind: .group, name: "文件操作", children: [child])
        let otherGroup = MenuNode(id: "qa.group-b", kind: .group, name: "第二分组", children: [otherChild])
        let root = MenuNode(id: "qa.root", kind: .operation, operationID: op.id, name: "一级菜单操作")
        XCTAssertTrue(store.update { $0.operations = [op]; $0.menu = [group, otherGroup, root]; $0.languageCode = "zh-Hans" })
        let controller = SettingsWindowController(store: store,
                                                  hasAccessibilityPermission: { true }, loadPermissionStatuses: { $0([]) })
        controllers.append(controller)
        controller.selectPage(SettingsPage.menu.rawValue)
        let window = try XCTUnwrap(controller.window)
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let menu = try XCTUnwrap(descendants(content).compactMap { $0 as? MenuEditorView }.first)
        let table: NSTableView = try view("menu-primary", in: content)
        _ = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        table.selectRowIndexes([0], byExtendingSelection: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        content.layoutSubtreeIfNeeded()
        return Scene(controller: controller, store: store, directory: location, window: window, root: content,
                     menu: menu, primary: table, operationID: op.id, groupID: group.id, childID: child.id,
                     otherGroupID: otherGroup.id, otherChildID: otherChild.id, rootID: root.id)
    }

    private func event(_ type: NSEvent.EventType, on view: NSView, clicks: Int = 1) throws -> NSEvent {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: try XCTUnwrap(view.window).windowNumber,
            context: nil, eventNumber: 1, clickCount: clicks, pressure: type == .leftMouseDown ? 1 : 0))
    }

    private func clickThroughWindow(_ button: NSButton, scene: Scene) throws {
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: scene.root.superview)
        let hit = try XCTUnwrap(scene.root.hitTest(point))
        XCTAssertTrue(hit === button || hit.isDescendant(of: button), "The native hit path must reach the checkbox rather than the table or its background.")
        NSApp.postEvent(try event(.leftMouseUp, on: button), atStart: true)
        scene.window.sendEvent(try event(.leftMouseDown, on: button))
    }

    private func beginEditing(_ nodeID: String, scene: Scene) throws -> (NSTextField, NSTextView) {
        let field: NSTextField = try view("menu-name-" + nodeID, in: scene.root)
        field.mouseDown(with: try event(.leftMouseDown, on: field, clicks: 2))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(scene.window.firstResponder === editor)
        return (field, editor)
    }

    func testCheckboxHitPathPersistsVisibilityAndKeepsItsCurrentControlAlive() throws {
        let scene = try makeScene()
        let check: NSButton = try view("menu-visible-" + scene.groupID, in: scene.root)
        let operations = scene.store.configuration.operations
        try clickThroughWindow(check, scene: scene)
        XCTAssertEqual(scene.store.configuration.menuNode(scene.groupID)?.visible, false)
        XCTAssertEqual(ConfigurationStore(directory: scene.directory).configuration.menuNode(scene.groupID)?.visible, false)
        XCTAssertEqual(check.state, .off)
        let tracked: NSButton = try view("menu-visible-" + scene.groupID, in: scene.root)
        XCTAssertTrue(tracked === check, "The native tracking callback must finish before rebuilding its control.")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let current: NSButton = try view("menu-visible-" + scene.groupID, in: scene.root)
        XCTAssertEqual(current.state, .off)
        XCTAssertEqual(scene.store.configuration.menuNode(scene.childID)?.visible, true)
        XCTAssertEqual(scene.store.configuration.menuNode(scene.otherGroupID)?.visible, true)
        XCTAssertEqual(scene.store.configuration.menuNode(scene.rootID)?.visible, true)
        XCTAssertEqual(scene.store.configuration.operations, operations)
        try clickThroughWindow(current, scene: scene)
        XCTAssertEqual(scene.store.configuration.menuNode(scene.groupID)?.visible, true)
        XCTAssertEqual(current.state, .on)
    }

    func testCheckedRootAndChildReferencesAloneAppearInTheNativeMenu() throws {
        let scene = try makeScene()
        let operations = scene.store.configuration.operations
        let child: NSButton = try view("menu-visible-" + scene.childID, in: scene.root)
        try clickThroughWindow(child, scene: scene)
        let root: NSButton = try view("menu-visible-" + scene.rootID, in: scene.root)
        try clickThroughWindow(root, scene: scene)
        let context = OperationContext(urls: [directory.appendingPathComponent("sample.txt")], directory: directory)
        let planned = MenuPlanner.items(configuration: scene.store.configuration, context: context)
        XCTAssertEqual(planned.map { $0.node.id }, [scene.otherGroupID])
        XCTAssertEqual(planned.first?.children.map { $0.node.id }, [scene.otherChildID])
        let menu = ContextMenuBuilder(configuration: scene.store.configuration, handler: { _ in }).menu(
            selectedURLs: context.urls, directory: try XCTUnwrap(directory))
        XCTAssertEqual(menu.items.map(\.title), ["第二分组"])
        XCTAssertEqual(menu.items.first?.submenu?.items.map(\.title), ["另一处引用"])
        XCTAssertEqual(scene.store.configuration.operations, operations)
        XCTAssertNotNil(scene.store.configuration.menuNode(scene.childID))
        XCTAssertNotNil(scene.store.configuration.menuNode(scene.rootID))
    }

    func testConfigurationRefreshPreservesActiveNameEditorAndItsDraft() throws {
        let scene = try makeScene()
        let (field, editor) = try beginEditing(scene.groupID, scene: scene)
        let originalFrame = field.convert(field.bounds, to: scene.root)
        editor.string = "正在编辑的名称"
        editor.setSelectedRange(NSRange(location: 3, length: 2))
        let selection = editor.selectedRange()
        scene.menu.reload()
        scene.store.update { $0.updateMenuNode(scene.otherGroupID) { $0.name = "外部刷新后的分组" } }
        scene.store.update { $0.operations[0].name = "操作信息刷新" }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let current: NSTextField = try view("menu-name-" + scene.groupID, in: scene.root)
        XCTAssertTrue(current === field)
        XCTAssertTrue(scene.window.firstResponder === editor)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "正在编辑的名称")
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(field.convert(field.bounds, to: scene.root), originalFrame)
        scene.window.makeFirstResponder(scene.primary)
        pump { scene.store.configuration.menuNode(scene.groupID)?.name == "正在编辑的名称" }
        XCTAssertEqual(scene.store.configuration.menuNode(scene.otherGroupID)?.name, "外部刷新后的分组")
        XCTAssertEqual(scene.store.configuration.operations.first?.name, "操作信息刷新")
    }

    func testNameTextGeometryRemainsStableWhenEnteringAndLeavingEditing() throws {
        let scene = try makeScene()
        let field: NSTextField = try view("menu-name-" + scene.groupID, in: scene.root)
        let originalFrame = field.convert(field.bounds, to: scene.root)
        let originalDrawingRect = try XCTUnwrap(field.cell).drawingRect(forBounds: field.bounds)
        let originalFont = field.font
        let (_, editor) = try beginEditing(scene.groupID, scene: scene)
        XCTAssertEqual(field.convert(field.bounds, to: scene.root), originalFrame)
        XCTAssertEqual(try XCTUnwrap(field.cell).drawingRect(forBounds: field.bounds), originalDrawingRect)
        XCTAssertEqual(field.font, originalFont)
        editor.string = "稳定的名称"
        scene.window.makeFirstResponder(scene.primary)
        pump { scene.store.configuration.menuNode(scene.groupID)?.name == "稳定的名称" }
        let ended: NSTextField = try view("menu-name-" + scene.groupID, in: scene.root)
        XCTAssertEqual(ended.convert(ended.bounds, to: scene.root), originalFrame)
        XCTAssertEqual(try XCTUnwrap(ended.cell).drawingRect(forBounds: ended.bounds), originalDrawingRect)
        XCTAssertEqual(ended.font, originalFont)
    }

    func testBothMenuColumnsHaveMaterialBackgroundsContainingTheirListsInBothThemes() throws {
        let scene = try makeScene()
        let first: ReferenceMaterialCard = try view("menu-primary-panel", in: scene.root)
        let second: ReferenceMaterialCard = try view("menu-secondary-panel", in: scene.root)
        XCTAssertFalse(first.frame.intersects(second.frame))
        for (theme, expected) in [(WindowTheme.light, NSAppearance.Name.aqua), (.dark, .darkAqua)] {
            scene.store.update { $0.windowTheme = theme }
            scene.root.layoutSubtreeIfNeeded()
            for (panel, identifier) in [(first, "menu-primary"), (second, "menu-secondary")] {
                let table: NSTableView = try view(identifier, in: scene.root)
                let scroll = try XCTUnwrap(table.enclosingScrollView)
                let cardRect = panel.convert(panel.bounds, to: scene.menu)
                let scrollRect = scroll.convert(scroll.bounds, to: scene.menu)
                XCTAssertTrue(cardRect.contains(scrollRect), identifier)
                XCTAssertGreaterThan(cardRect.height, 300)
                XCTAssertFalse(panel.isOpaque)
                XCTAssertNil(panel.appearance)
                XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            }
        }
    }

    func testNativeNameFieldEditorIsTransparentAndVerticallyCenteredInBothThemes() throws {
        let scene = try makeScene()
        for (theme, label) in [(WindowTheme.light, "light"), (.dark, "dark")] {
            scene.store.update { $0.windowTheme = theme }
            scene.root.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let field: NSTextField = try view("menu-name-" + scene.groupID, in: scene.root)
            let originalFrame = field.convert(field.bounds, to: scene.root)
            let beforeDrawing = try XCTUnwrap(field.cell).drawingRect(forBounds: field.bounds)
            let beforeTitle = try XCTUnwrap(field.cell).titleRect(forBounds: field.bounds)
            XCTAssertEqual(beforeDrawing.midY, field.bounds.midY, accuracy: 1, label)
            XCTAssertEqual(beforeTitle.midY, field.bounds.midY, accuracy: 1, label)

            let (_, editor) = try beginEditing(scene.groupID, scene: scene)
            let actualEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            XCTAssertTrue(actualEditor === editor)
            XCTAssertTrue(scene.window.firstResponder === actualEditor)
            XCTAssertFalse(field.drawsBackground, label)
            XCTAssertFalse(actualEditor.drawsBackground, "The actual shared AppKit field editor must not introduce a white/black rectangle (" + label + ").")
            XCTAssertFalse(actualEditor.isOpaque, label)
            XCTAssertEqual(field.convert(field.bounds, to: scene.root), originalFrame)
            let editingDrawing = try XCTUnwrap(field.cell).drawingRect(forBounds: field.bounds)
            let editingTitle = try XCTUnwrap(field.cell).titleRect(forBounds: field.bounds)
            let editorRect = actualEditor.convert(actualEditor.bounds, to: field)
            XCTAssertEqual(editingDrawing.midY, field.bounds.midY, accuracy: 1, label)
            XCTAssertEqual(editingTitle.midY, field.bounds.midY, accuracy: 1, label)
            XCTAssertEqual(editorRect.midY, field.bounds.midY, accuracy: 1, label)
            XCTAssertEqual(editingDrawing, beforeDrawing)
            XCTAssertEqual(editingTitle, beforeTitle)

            let layout = try XCTUnwrap(actualEditor.layoutManager)
            let container = try XCTUnwrap(actualEditor.textContainer)
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            let origin = actualEditor.textContainerOrigin
            let textRect = actualEditor.convert(used.offsetBy(dx: origin.x, dy: origin.y), to: field)
            XCTAssertGreaterThan(textRect.height, 0, label)
            XCTAssertEqual(textRect.midY, field.bounds.midY, accuracy: 1, label)

            for (variant, text) in [("empty", ""), ("chinese", "正在输入的中文名称"), ("long", String(repeating: "很长的名称Abc123", count: 30))] {
                actualEditor.string = text
                let insertion = NSRange(location: (text as NSString).length, length: 0)
                actualEditor.setSelectedRange(insertion)
                layout.ensureLayout(for: container)
                actualEditor.scrollRangeToVisible(insertion)
                scene.root.layoutSubtreeIfNeeded()
                scene.root.displayIfNeeded()
                XCTAssertTrue(field.currentEditor() === actualEditor)
                XCTAssertTrue(scene.window.firstResponder === actualEditor)
                XCTAssertEqual(actualEditor.selectedRange(), insertion)
                XCTAssertFalse(actualEditor.drawsBackground)
                XCTAssertFalse(actualEditor.isOpaque)
                XCTAssertGreaterThan(actualEditor.visibleRect.width, 0)
                XCTAssertGreaterThan(actualEditor.visibleRect.height, 0)
                let caretScreen = actualEditor.firstRect(forCharacterRange: insertion, actualRange: nil)
                let caret = field.convert(scene.window.convertFromScreen(caretScreen), from: nil)
                XCTAssertGreaterThan(caret.height, 0, label + "/" + variant)
                XCTAssertEqual(caret.midY, field.bounds.midY, accuracy: 1, label + "/" + variant)
                XCTAssertGreaterThanOrEqual(caret.minX, field.bounds.minX - 2, label + "/" + variant)
                XCTAssertLessThanOrEqual(caret.maxX, field.bounds.maxX + 2, label + "/" + variant)
            }

            let savedName = label == "light" ? "亮色编辑后的名称" : "暗色编辑后的名称"
            actualEditor.string = savedName
            scene.window.makeFirstResponder(scene.primary)
            pump { scene.store.configuration.menuNode(scene.groupID)?.name == savedName }
            scene.root.layoutSubtreeIfNeeded()
            let ended: NSTextField = try view("menu-name-" + scene.groupID, in: scene.root)
            let savedDrawing = try XCTUnwrap(ended.cell).drawingRect(forBounds: ended.bounds)
            let savedTitle = try XCTUnwrap(ended.cell).titleRect(forBounds: ended.bounds)
            XCTAssertEqual(ended.convert(ended.bounds, to: scene.root), originalFrame)
            XCTAssertEqual(savedDrawing, beforeDrawing)
            XCTAssertEqual(savedTitle, beforeTitle)
            XCTAssertEqual(savedDrawing.midY, ended.bounds.midY, accuracy: 1, label)
            XCTAssertEqual(savedTitle.midY, ended.bounds.midY, accuracy: 1, label)
        }
    }

    func testMenuColumnsShareTheSameTranslucentGradientAndRetainTheirBackdrop() throws {
        let scene = try makeScene()
        let first: ReferenceMaterialCard = try view("menu-primary-panel", in: scene.root)
        let second: ReferenceMaterialCard = try view("menu-secondary-panel", in: scene.root)
        let backdrop = MenuColumnColorTestBackdrop(frame: scene.menu.bounds)
        scene.menu.addSubview(backdrop, positioned: .below, relativeTo: nil)
        defer { backdrop.removeFromSuperview() }
        func bitmap(_ root: NSView) throws -> NSBitmapImageRep {
            func invalidate(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(invalidate) }
            invalidate(root); root.layoutSubtreeIfNeeded()
            let result = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: result)
            return result
        }
        func color(_ image: NSBitmapImageRep, in root: NSView, at point: NSPoint) throws -> NSColor {
            let x = min(image.pixelsWide - 1, max(0, Int((point.x - root.bounds.minX) / root.bounds.width * CGFloat(image.pixelsWide))))
            let y = min(image.pixelsHigh - 1, max(0, Int((point.y - root.bounds.minY) / root.bounds.height * CGFloat(image.pixelsHigh))))
            return try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        func difference(_ first: NSColor, _ second: NSColor) -> CGFloat {
            abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent)
                + abs(first.blueComponent - second.blueComponent)
        }
        let rawBackdrop = try bitmap(backdrop)
        let red = try color(rawBackdrop, in: backdrop, at: NSPoint(x: backdrop.bounds.width * 0.25, y: backdrop.bounds.midY))
        let blue = try color(rawBackdrop, in: backdrop, at: NSPoint(x: backdrop.bounds.width * 0.75, y: backdrop.bounds.midY))
        XCTAssertGreaterThan(abs(red.redComponent - blue.redComponent) + abs(red.blueComponent - blue.blueComponent), 1)
        for (theme, label) in [(WindowTheme.light, "light"), (.dark, "dark")] {
            scene.store.update { $0.windowTheme = theme }
            scene.root.layoutSubtreeIfNeeded()
            backdrop.splitColors = true
            let image = try bitmap(scene.menu)
            let leftPoint = first.convert(NSPoint(x: first.bounds.midX, y: first.bounds.midY), to: scene.menu)
            let rightPoint = second.convert(NSPoint(x: second.bounds.midX, y: second.bounds.midY), to: scene.menu)
            let left = try color(image, in: scene.menu, at: leftPoint)
            let right = try color(image, in: scene.menu, at: rightPoint)
            let retainedVariation = difference(left, right) / difference(red, blue)
            XCTAssertGreaterThan(retainedVariation, 0.7, label)
            XCTAssertLessThan(retainedVariation, 0.95, label)
            XCTAssertGreaterThan(difference(left, red), 0.03, label)
            XCTAssertGreaterThan(difference(right, blue), 0.03, label)
            XCTAssertFalse(first.isOpaque, "Rounded card corners must keep their existing opacity contract.")
            XCTAssertFalse(second.isOpaque)
            backdrop.splitColors = false
            let uniform = try bitmap(scene.menu)
            var gradients: [CGFloat] = []
            for fraction in [CGFloat(0.2), 0.8] {
                let leftPoint = first.convert(NSPoint(x: first.bounds.width * fraction, y: first.bounds.midY), to: scene.menu)
                let rightPoint = second.convert(NSPoint(x: second.bounds.width * fraction, y: second.bounds.midY), to: scene.menu)
                let left = try color(uniform, in: scene.menu, at: leftPoint)
                let right = try color(uniform, in: scene.menu, at: rightPoint)
                XCTAssertEqual(left.redComponent, right.redComponent, accuracy: 1.0 / 255, label)
                XCTAssertEqual(left.greenComponent, right.greenComponent, accuracy: 1.0 / 255, label)
                XCTAssertEqual(left.blueComponent, right.blueComponent, accuracy: 1.0 / 255, label)
                gradients.append(left.redComponent)
            }
            let gradient = abs(gradients[0] - gradients[1])
            XCTAssertGreaterThan(gradient, 0.02, label)
            XCTAssertLessThan(gradient, 0.12, label)
        }
    }
}

private final class MenuColumnColorTestBackdrop: NSView {
    var splitColors = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        if !splitColors {
            NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1).setFill()
            bounds.fill(); return
        }
        NSColor(srgbRed: 0.95, green: 0.05, blue: 0.05, alpha: 1).setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height).fill()
        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.95, alpha: 1).setFill()
        NSRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height).fill()
    }
}
