import XCTest
import AppKit
@testable import Crab

@MainActor
final class OperationLibraryTests: XCTestCase {
    private var directory: URL!
    private var language = ""
    override func setUpWithError() throws {
        language = AppLocalization.languageCode; AppLocalization.languageCode = "zh-Hans"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-Operations-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { AppLocalization.languageCode = language; try? FileManager.default.removeItem(at: directory) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func store() -> ConfigurationStore { ConfigurationStore(directory: directory.appendingPathComponent(UUID().uuidString)) }
    private func op(_ id: String = UUID().uuidString) -> OperationRecord { .init(id: id, parameters: .tool(.init(action: .copyPath))) }

    @discardableResult
    private func assertLibraryToolbar(in root: NSView, language: String) throws -> [NSControl] {
        let toolbar = try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == "library-toolbar" })
        var identifiers = ["library-search", "library-type", "library-status", "library-batch", "library-add"]
        if toolbar.subviews.contains(where: { $0.identifier?.rawValue == "library-batch-cancel" && !$0.isHidden }) {
            identifiers.append("library-batch-cancel")
        }
        let controls: [NSControl] = try identifiers.map { identifier in
            try XCTUnwrap(toolbar.subviews.first { $0.identifier?.rawValue == identifier } as? NSControl, language + ": " + identifier)
        }
        let rects = controls.map { $0.alignmentRect(forFrame: $0.frame) }
        for (index, rect) in rects.enumerated() {
            let message = language + ": " + identifiers[index]
            XCTAssertEqual(rect.midY, rects[index < 3 ? 0 : 3].midY, accuracy: 0.5, message)
            XCTAssertGreaterThanOrEqual(rect.minX, toolbar.bounds.minX - 0.5, message)
            XCTAssertGreaterThanOrEqual(rect.minY, toolbar.bounds.minY - 0.5, message)
            XCTAssertLessThanOrEqual(rect.maxX, toolbar.bounds.maxX + 0.5, message)
            XCTAssertLessThanOrEqual(rect.maxY, toolbar.bounds.maxY + 0.5, message)
            for other in rects.prefix(index) { XCTAssertFalse(rect.intersects(other), message + ": controls must not overlap") }
        }
        let search = try XCTUnwrap(controls[0] as? OperationLibrarySearchField)
        XCTAssertGreaterThanOrEqual(search.bounds.width, 120, language)
        XCTAssertLessThanOrEqual(search.bounds.width, 180, language)
        if abs(rects[3].midY - rects[0].midY) < 0.5 {
            XCTAssertGreaterThanOrEqual((rects.dropFirst(3).map(\.minX).min() ?? 0) - rects[2].maxX, 16, language)
        } else {
            XCTAssertGreaterThanOrEqual(rects[3].minY, rects.prefix(3).map(\.maxY).max() ?? 0, language)
        }
        XCTAssertEqual(rects.dropFirst(3).map(\.maxX).max() ?? 0, toolbar.bounds.maxX, accuracy: 0.5, language)
        XCTAssertFalse(search.drawsBackground)
        XCTAssertTrue(search.isBezeled)
        XCTAssertFalse(search.isOpaque)
        XCTAssertTrue(search.isEditable)
        XCTAssertTrue(search.isSelectable)
        let searchCell = try XCTUnwrap(search.cell as? NSSearchFieldCell)
        XCTAssertEqual(searchCell.searchTextRect(forBounds: search.bounds).midY, search.bounds.midY, accuracy: 0.5, language)
        for popup in controls.compactMap({ $0 as? NSPopUpButton }) {
            let title = try XCTUnwrap(popup.selectedItem?.title)
            let font = popup.font ?? .systemFont(ofSize: NSFont.smallSystemFontSize)
            let width = ceil((title as NSString).size(withAttributes: [.font: font]).width)
            let titleRect = try XCTUnwrap(popup.cell).titleRect(forBounds: popup.bounds)
            XCTAssertLessThanOrEqual(width, titleRect.width + 1, language + ": " + title)
        }
        return controls
    }
    func testFreshFormatIgnoresAndPreservesLegacyFileAndStartsWithDefaultMenu() throws {
        let legacy = directory.appendingPathComponent("configuration.json")
        let original = Data("{\"schemaVersion\":2,\"customScripts\":[{\"path\":\"/private/user-script.sh\"}]}".utf8)
        try original.write(to: legacy)
        let store = ConfigurationStore(directory: directory)
        XCTAssertFalse(store.configuration.operations.isEmpty)
        XCTAssertFalse(store.configuration.menu.isEmpty)
        let originalMenu = store.configuration.menu
        XCTAssertEqual(Set(store.configuration.operations.map(\.id)).count, store.configuration.operations.count)
        XCTAssertTrue(store.update { $0.operations.append(op("new")) })
        XCTAssertEqual(store.configuration.menu, originalMenu)
        XCTAssertEqual(ConfigurationStore(directory: directory).configuration.menu, originalMenu)
        XCTAssertEqual(store.configuration.referenceCount("new"), 0)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("operations-v1.json").path))
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfiguration.self, from: original))
    }

    func testDefaultMenuGroupsEveryBuiltInExactlyOnceWithExpectedCategories() throws {
        let configuration = AppConfiguration()
        let titles = ["新建文件", "文件（夹）操作", "由 APP 打开", "发送到…", "收藏目录", "自定义图标", "图片转换", "压缩与解压"]
        XCTAssertEqual(configuration.menu.compactMap(\.defaultNameKey), titles)
        XCTAssertEqual(configuration.menu.map(\.iconID), ["category.newFile", "category.tools", "category.applications", "category.send", "category.common", "category.customIcons", "category.images", "category.archives"])
        XCTAssertTrue(configuration.menu.allSatisfy { $0.kind == .group && $0.name == nil && $0.visible && $0.operationID == nil })
        let references = configuration.menu.flatMap(\.children)
        XCTAssertTrue(references.allSatisfy { $0.kind == .operation && $0.children.isEmpty && $0.visible && $0.name == nil })
        XCTAssertEqual(references.count, configuration.operations.count)
        XCTAssertEqual(Set(references.compactMap(\.operationID)), Set(configuration.operations.map(\.id)))
        XCTAssertTrue(configuration.operations.allSatisfy { configuration.referenceCount($0.id) == 1 })
        func ids(_ title: String) -> [String] { configuration.menu.first { $0.defaultNameKey == title }?.children.compactMap(\.operationID) ?? [] }
        XCTAssertEqual(ids("新建文件"), FileTemplate.defaults.map { "builtin.template." + $0.id })
        XCTAssertEqual(ids("由 APP 打开"), ApplicationCatalog.all.map { "builtin.app." + $0.id })
        XCTAssertEqual(ids("发送到…"), ["builtin.tool.desktopLink", "builtin.tool.airDrop", "builtin.transfer.copy", "builtin.transfer.move"])
        XCTAssertEqual(ids("收藏目录"), ["builtin.tool.add-common"])
        XCTAssertEqual(ids("自定义图标"), SystemIconDefaults.catalog.map(\.id) + ["builtin.image.remove"])
        XCTAssertEqual(ids("图片转换"), ["webp", "heic", "jpeg", "png", "icns", "macIconset", "iosIconset", "tiff"].map { "builtin.tool." + $0 })
        XCTAssertEqual(ids("压缩与解压"), ["builtin.tool.sevenZip", "builtin.tool.zip", "builtin.tool.unzip"])
        for action in [ToolAction.copyPath, .fileInfo, .cut, .paste, .dissolveFolder, .trash] {
            XCTAssertTrue(ids("文件（夹）操作").contains("builtin.tool." + action.rawValue))
        }
        try configuration.validate()
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration)), configuration)
    }

    func testDefaultGroupTitlesFollowLanguageUntilRenamedAndPlannerUsesSameTitles() throws {
        var configuration = AppConfiguration()
        configuration.previews = Dictionary(uniqueKeysWithValues: configuration.operations.map { ($0.id, OperationPreview()) })
        let context = OperationContext(urls: [directory.appendingPathComponent("image.png")], directory: directory)
        for code in ["zh-Hans", "en", "ja"] {
            AppLocalization.languageCode = code
            for node in configuration.menu { XCTAssertEqual(node.displayName(), L(try XCTUnwrap(node.defaultNameKey))) }
            let planned = MenuPlanner.items(configuration: configuration, context: context, allowFileRead: false)
            XCTAssertEqual(planned.map(\.title), configuration.menu.map { $0.displayName() })
        }
        AppLocalization.languageCode = "en"
        XCTAssertEqual(configuration.menu[0].displayName(), "New File")
        configuration.menu[0].name = "新建文件"
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(decoded.menu[0].displayName(), "新建文件", "A user name remains literal even when it matches a translation key.")
        XCTAssertEqual(MenuPlanner.items(configuration: decoded, context: context, allowFileRead: false).first?.title, "新建文件")
        let oldGroup = Data(#"{"id":"old-group","kind":"group","name":"Original group","visible":true,"children":[]}"#.utf8)
        let oldNode = try JSONDecoder().decode(MenuNode.self, from: oldGroup)
        XCTAssertNil(oldNode.defaultNameKey)
        XCTAssertEqual(oldNode.displayName(), "Original group")
    }

    func testSavedEmptyAndCustomizedMenusAreNeverReplacedByDefaults() throws {
        let store = ConfigurationStore(directory: directory)
        XCTAssertTrue(store.update { $0.menu = [] })
        let empty = ConfigurationStore(directory: directory)
        XCTAssertTrue(empty.configuration.menu.isEmpty)
        XCTAssertTrue(empty.update { $0.operations.append(op("custom")) })
        XCTAssertTrue(ConfigurationStore(directory: directory).configuration.menu.isEmpty)
        var reference = MenuNode.reference("custom"); reference.name = "My action"; reference.visible = false
        let customMenu = [MenuNode(kind: .group, name: "My menu", iconID: "crab.heart", children: [reference])]
        XCTAssertTrue(empty.update { $0.menu = customMenu })
        let reloaded = ConfigurationStore(directory: directory)
        XCTAssertEqual(reloaded.configuration.menu, customMenu)
        XCTAssertTrue(reloaded.update { $0.operations.append(op("another")) })
        XCTAssertEqual(ConfigurationStore(directory: directory).configuration.menu, customMenu)
    }

    func testDefaultMenuUsesOnlyExistingBuiltInsAndKeepsLibraryParameters() throws {
        let original = try XCTUnwrap(OperationRegistry.defaults().first { $0.id == "builtin.tool.copyPath" })
        var existing = original; existing.name = "My built-in name"; existing.enabled = false
        let custom = original.duplicated()
        var configuration = AppConfiguration(); configuration.operations = [existing, custom]
        configuration.menu = DefaultMenuLayout.nodes(for: configuration.operations)
        XCTAssertEqual(configuration.menu.flatMap(\.children).compactMap(\.operationID), [existing.id])
        XCTAssertEqual(configuration.operations, [existing, custom])
        XCTAssertEqual(configuration.referenceCount(custom.id), 0)
        try configuration.validate()
    }

    func testResetWholeMenuUsesCurrentLibraryAndPreservesOperationsPreferencesAndPreviews() throws {
        var configuration = AppConfiguration()
        var retained = try XCTUnwrap(configuration.operations.first { $0.id == "builtin.template.txt" })
        retained.name = "My template"; retained.enabled = false
        let custom = op("custom-library-operation")
        configuration.operations = [retained, custom]
        configuration.menu = [.init(kind: .group, name: "Custom arrangement", children: [.reference(custom.id)])]
        configuration.languageCode = "ja"; configuration.windowTheme = .dark
        configuration.previews[retained.id] = OperationPreview(available: false, reason: "Test status")
        var expected = configuration
        expected.menu = DefaultMenuLayout.nodes(for: configuration.operations)
        XCTAssertTrue(configuration.resetMenu())
        XCTAssertEqual(configuration, expected)
        XCTAssertEqual(configuration.menu.flatMap(\.children).compactMap(\.operationID), [retained.id])
        try configuration.validate()
    }

    func testResetRenamedDefaultGroupPreservesOtherNodesAndAvoidsMovedReferenceIDConflicts() throws {
        var configuration = AppConfiguration()
        let defaultGroup = try XCTUnwrap(configuration.menu.first)
        let moved = try XCTUnwrap(defaultGroup.children.first)
        let destination = MenuNode(kind: .group, name: "Destination", children: [moved])
        configuration.menu[0].children.removeFirst()
        configuration.menu[0].name = "Renamed templates"
        configuration.menu[0].iconID = "crab.heart"
        configuration.menu[0].visible = false
        configuration.menu[0].children = [.reference("missing-reference")]
        configuration.menu.append(destination)
        let original = configuration
        XCTAssertTrue(configuration.resetMenu(groupID: defaultGroup.id))
        let restored = try XCTUnwrap(configuration.menuNode(defaultGroup.id))
        XCTAssertEqual(restored.children.compactMap(\.operationID), defaultGroup.children.compactMap(\.operationID))
        let restoredMoved = try XCTUnwrap(restored.children.first { $0.operationID == moved.operationID })
        XCTAssertNotEqual(restoredMoved.id, moved.id)
        XCTAssertEqual(configuration.menuNode(destination.id), destination)
        var expectedGroup = original.menu[0]; expectedGroup.children = restored.children
        XCTAssertEqual(restored, expectedGroup)
        XCTAssertEqual(Array(configuration.menu.dropFirst()), Array(original.menu.dropFirst()))
        XCTAssertEqual(configuration.operations, original.operations)
        XCTAssertEqual(configuration.general, original.general)
        let allIDs = configuration.menu.flatMap { [$0.id] + $0.children.map(\.id) }
        XCTAssertEqual(Set(allIDs).count, allIDs.count)
        try configuration.validate()
    }

    func testResetCustomGroupsAndInvalidTargetsDoNotChangeConfiguration() throws {
        var configuration = AppConfiguration()
        let custom = MenuNode(kind: .group, name: "新建文件", visible: false, iconID: "crab.star", children: [.reference("custom-action")])
        configuration.menu.append(custom)
        let original = configuration
        XCTAssertFalse(configuration.resetMenu(groupID: custom.id))
        XCTAssertEqual(configuration, original, "A custom group whose name matches a default group must remain unchanged.")
        XCTAssertFalse(configuration.resetMenu(groupID: "removed-group"))
        XCTAssertEqual(configuration, original)
        let root = MenuNode.reference("root-operation")
        configuration.menu.append(root)
        let withRoot = configuration
        XCTAssertFalse(configuration.resetMenu(groupID: root.id))
        XCTAssertEqual(configuration, withRoot)
    }

    func testMenuToolbarIconsFollowSelectionAndResetAnEmptyMenuWithoutASheet() throws {
        let location = directory.appendingPathComponent("default-menu-ui")
        let store = ConfigurationStore(directory: location)
        XCTAssertTrue(store.update { $0.languageCode = "zh-Hans"; $0.windowTheme = .light })
        let scene = SettingsWindowController(store: store)
        defer { scene.window?.close() }
        scene.selectPage(SettingsPage.menu.rawValue)
        let root = try XCTUnwrap(scene.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(descendants(root).compactMap { $0 as? MenuEditorView }.first)
        let tables = descendants(editor).compactMap { $0 as? NSTableView }
        let primary = try XCTUnwrap(tables.first { $0.identifier?.rawValue == "menu-primary" })
        let secondary = try XCTUnwrap(tables.first { $0.identifier?.rawValue == "menu-secondary" })
        func button(_ identifier: String) throws -> NSButton {
            try XCTUnwrap(descendants(editor).first { $0.identifier?.rawValue == identifier } as? NSButton)
        }
        let primaryIDs = ["menu-new-group", "menu-primary-add", "menu-primary-remove", "menu-primary-reset"]
        let secondaryIDs = ["menu-secondary-add", "menu-secondary-remove", "menu-secondary-reset"]
        for identifiers in [primaryIDs, secondaryIDs] {
            let buttons = try identifiers.map(button)
            for (index, control) in buttons.enumerated() {
                XCTAssertNotNil(control.image, identifiers[index])
                XCTAssertEqual(control.imagePosition, .imageOnly, identifiers[index])
                XCTAssertTrue(control.title.isEmpty, identifiers[index])
                XCTAssertFalse((control.toolTip ?? "").isEmpty, identifiers[index])
                XCTAssertFalse((control.accessibilityLabel() ?? "").isEmpty, identifiers[index])
                if index > 0 { XCTAssertGreaterThanOrEqual(control.frame.minX, buttons[index - 1].frame.maxX) }
            }
        }
        let reset = try button("menu-primary-reset")
        XCTAssertNil(descendants(editor).first { $0.identifier?.rawValue == "menu-use-defaults" })
        XCTAssertEqual(primary.numberOfRows, 8)
        XCTAssertEqual(primary.selectedRow, 0)
        XCTAssertEqual(secondary.numberOfRows, FileTemplate.defaults.count)
        XCTAssertTrue(reset.isEnabled); XCTAssertFalse(reset.isHidden)
        XCTAssertTrue(try button("menu-primary-remove").isEnabled)
        XCTAssertTrue(try button("menu-secondary-add").isEnabled)
        XCTAssertTrue(try button("menu-secondary-reset").isEnabled)
        XCTAssertFalse(try button("menu-secondary-remove").isEnabled)
        secondary.selectRowIndexes([0], byExtendingSelection: false)
        XCTAssertTrue(try button("menu-secondary-remove").isEnabled)
        primary.deselectAll(nil)
        XCTAssertFalse(try button("menu-primary-remove").isEnabled)
        for identifier in secondaryIDs { XCTAssertFalse(try button(identifier).isEnabled) }
        XCTAssertTrue(reset.isEnabled)
        primary.selectRowIndexes([0], byExtendingSelection: false)

        let environment = ProcessInfo.processInfo.environment
        if let path = environment["CRAB_MENU_TOOLBAR_PREVIEW_DIR"] ?? environment["TEST_RUNNER_CRAB_MENU_TOOLBAR_PREVIEW_DIR"] {
            let output = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (theme, name) in [(WindowTheme.light, "light"), (.dark, "dark")] {
                XCTAssertTrue(store.update { $0.windowTheme = theme })
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                root.layoutSubtreeIfNeeded()
                func invalidate(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(invalidate) }
                invalidate(root)
                let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("menu-toolbar-" + name + ".png"))
            }
        }

        let retained = try XCTUnwrap(store.configuration.operations.first { $0.id == "builtin.template.txt" })
        let custom = op("custom")
        XCTAssertTrue(store.update { $0.menu = []; $0.operations = [retained, custom] })
        editor.reload()
        XCTAssertFalse(reset.isHidden)
        XCTAssertTrue(reset.isEnabled)
        XCTAssertEqual(primary.numberOfRows, 0)
        XCTAssertEqual(secondary.numberOfRows, 0)
        reset.performClick(nil)
        XCTAssertNil(scene.window?.attachedSheet)
        XCTAssertEqual(primary.numberOfRows, 8)
        XCTAssertEqual(secondary.numberOfRows, 1)
        XCTAssertFalse(reset.isHidden)
        XCTAssertEqual(store.configuration.operations, [retained, custom])
        XCTAssertEqual(store.configuration.menu.flatMap(\.children).compactMap(\.operationID), [retained.id])
        XCTAssertEqual(ConfigurationStore(directory: location).configuration, store.configuration)
        XCTAssertTrue(store.update { $0.menu = [.reference(custom.id)] })
        editor.reload(); primary.selectRowIndexes([0], byExtendingSelection: false)
        XCTAssertTrue(try button("menu-primary-remove").isEnabled)
        for identifier in secondaryIDs { XCTAssertFalse(try button(identifier).isEnabled) }
        let customGroup = MenuNode(kind: .group, name: "新建文件", children: [.reference(custom.id)])
        XCTAssertTrue(store.update { $0.menu = [customGroup] })
        editor.reload(); primary.selectRowIndexes([0], byExtendingSelection: false)
        XCTAssertTrue(try button("menu-secondary-add").isEnabled)
        XCTAssertFalse(try button("menu-secondary-reset").isEnabled)
        let beforeCustomReset = store.configuration
        let disabledReset = try button("menu-secondary-reset")
        _ = disabledReset.target?.perform(try XCTUnwrap(disabledReset.action), with: disabledReset)
        XCTAssertNil(scene.window?.attachedSheet)
        XCTAssertEqual(store.configuration, beforeCustomReset)
    }
    func testUnknownTypeRoundTripsAndDoesNotDiscardOtherOperations() throws {
        var config = AppConfiguration(); config.operations = [op("known"), .init(id: "future", parameters: .unknown("future.type", .object(["list": .array([.number(2), .bool(true), .null]), "name": .string("客户")])))]
        config.menu = [.reference("future"), .reference("known")]
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        let result = MenuPlanner.items(configuration: decoded, context: .init(urls: [directory.appendingPathComponent("a.txt")], directory: directory))
        XCTAssertEqual(result.map { $0.operation?.id }, ["known"])
    }
    func testUnknownFutureToolPayloadIsPreservedAndUnavailable() throws {
        let data = Data(#"{"type":"tool","value":{"action":"future.action","newOption":true}}"#.utf8)
        let parameters = try JSONDecoder().decode(OperationParameters.self, from: data)
        let op = OperationRecord(parameters: parameters)
        XCTAssertNotNil(OperationResolver.reason(op, configuration: AppConfiguration()))
        let first = try JSONSerialization.jsonObject(with: data) as! NSDictionary
        let second = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as! NSDictionary
        XCTAssertEqual(first, second)
    }
    func testAtomicValidationRejectsThirdLevelDuplicatesAndPreservesSavedState() throws {
        let store = store(); XCTAssertTrue(store.replace(AppConfiguration()))
        let previous = store.configuration
        XCTAssertFalse(store.update { $0.menu = [.init(kind: .group, children: [.init(kind: .group)])] })
        XCTAssertEqual(store.configuration, previous)
        XCTAssertEqual(ConfigurationStore(directory: directory.appendingPathComponent("unused")).configuration.menu, AppConfiguration().menu)
        XCTAssertFalse(store.update { $0.operations += [$0.operations[0]] })
        XCTAssertEqual(store.configuration, previous)
        XCTAssertNotNil(store.lastError)
    }
    func testUnreadableNewFormatIsNotOverwrittenByEditing() throws {
        let file = directory.appendingPathComponent("operations-v1.json")
        let bytes = Data("{broken".utf8); try bytes.write(to: file)
        let store = ConfigurationStore(directory: directory)
        XCTAssertTrue(store.configuration.menu.isEmpty)
        XCTAssertNotNil(store.lastError); XCTAssertFalse(store.update { $0.menu = [] })
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testMenuReferencesNamesCopiesAndDeletionHaveSeparateIdentity() throws {
        let original = op("original"); var copy = original.duplicated(); copy.name = "Copy"
        XCTAssertNotEqual(copy.id, original.id)
        copy.parameters = .tool(.init(action: .copyName))
        XCTAssertEqual(original.parameters, .tool(.init(action: .copyPath)))
        var config = AppConfiguration(); config.operations = [original, copy]
        let group = MenuNode(kind: .group, name: "组", children: [.reference(original.id), .reference(original.id)])
        config.menu = [.reference(original.id), group]
        XCTAssertEqual(config.referenceCount(original.id), 3)
        config.removeMenuNode(group.id)
        XCTAssertEqual(config.operations, [original, copy]); XCTAssertEqual(config.referenceCount(original.id), 1)
        config.menu += [group]; config.removeOperations([original.id])
        XCTAssertEqual(config.operations, [copy]); XCTAssertEqual(config.referenceCount(original.id), 0)
        XCTAssertEqual(config.menu.count, 1)
    }
    func testDragAcrossGroupsAndRootKeepsOrderAndRejectsGroupNesting() throws {
        var config = AppConfiguration(); let a = MenuNode.reference("a"), b = MenuNode.reference("b")
        let g1 = MenuNode(kind: .group, children: [a]), g2 = MenuNode(kind: .group, children: [b])
        config.menu = [g1, g2]
        XCTAssertTrue(config.moveMenuNode(a.id, into: g2.id, at: 1))
        XCTAssertTrue(config.menu[0].children.isEmpty)
        XCTAssertEqual(config.menu[1].children.map(\.operationID), ["b", "a"])
        XCTAssertFalse(config.moveMenuNode(g1.id, into: g2.id, at: 0))
        XCTAssertTrue(config.moveMenuNode(a.id, into: nil, at: 0))
        XCTAssertEqual(config.menu.first?.id, a.id)
        XCTAssertTrue(config.moveMenuNode(a.id, into: nil, at: 3))
        XCTAssertEqual(config.menu.last?.id, a.id)
        try config.validate()
    }
    func testPlannerFiltersContextVisibilityDisabledAndUnavailableAndRetainsEditorStructure() throws {
        var config = AppConfiguration(); let a = op("a")
        let image = OperationRecord(id: "convert", parameters: .tool(.init(action: .png)))
        let missing = OperationRecord(id: "missing", parameters: .directory("/does-not-exist-crab-test"))
        var hidden = MenuNode.reference(a.id); hidden.visible = false
        config.operations = [a, image, missing]
        config.menu = [hidden, .init(kind: .group, name: "图像", children: [.reference(image.id)]), .reference(a.id), .reference(missing.id)]
        let original = config.menu
        XCTAssertTrue(MenuPlanner.items(configuration: config, context: .init(urls: [], directory: directory)).isEmpty)
        let result = MenuPlanner.items(configuration: config, context: .init(urls: [directory.appendingPathComponent("file.txt")], directory: directory))
        XCTAssertEqual(result.map { $0.operation?.id }, [a.id]); XCTAssertEqual(config.menu, original)
        config.operations[0].enabled = false
        XCTAssertTrue(MenuPlanner.items(configuration: config, context: .init(urls: [directory.appendingPathComponent("file.txt")], directory: directory)).isEmpty)
    }
    func testTransportPreviewsAreKeyedByInstanceAndNeverPersistedInMaster() throws {
        let store = store()
        XCTAssertTrue(store.update { $0.operations = [op("one"), op("two")] })
        let prepared = ConfigurationStore.prepare(store.configuration)
        XCTAssertEqual(Set(prepared.previews.keys), ["one", "two"])
        XCTAssertTrue(prepared.previews.values.allSatisfy { $0.data != nil && $0.available })
        XCTAssertTrue(store.replace(prepared))
        let file = directory.appendingPathComponent("dummy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let encoded = try JSONEncoder().encode(store.configuration)
        XCTAssertFalse(encoded.isEmpty)
        let local = ConfigurationStore(directory: directory.appendingPathComponent("cache"))
        XCTAssertTrue(local.replace(prepared))
        XCTAssertTrue(ConfigurationStore(directory: directory.appendingPathComponent("cache")).configuration.previews.isEmpty)
        var ext = prepared; ext.menu = [.reference("one")]
        XCTAssertEqual(MenuPlanner.items(configuration: ext, context: .init(urls: [directory.appendingPathComponent("file")], directory: directory), allowFileRead: false).count, 1)
    }
    func testStaleMenuRequestResolvesLatestParametersAndRejectsDeletedOrDisabledOperation() throws {
        let first = directory.appendingPathComponent("one.sh"), second = directory.appendingPathComponent("two.sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: first); try Data("#!/bin/sh\nexit 0\n".utf8).write(to: second)
        let store = store(); var calls: [String] = []
        store.update { $0.operations = [.init(id: "script", parameters: .script(first.path))] }
        let router = ActionRouter(store: store, launchScript: { script, _, _, _ in DispatchQueue.main.async { calls.append(script.path) } })
        let request = ActionRequest(operationID: "script", paths: [], targetDirectory: directory.path)
        let decoded = try ActionRequest.decode(request.encodedURL())
        store.update { $0.operations[0].parameters = .script(second.path) }
        router.execute(decoded)
        let deadline = Date().addingTimeInterval(2)
        while calls.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(calls, [second.path])
        store.update { $0.operations[0].enabled = false }; router.execute(decoded)
        store.update { $0.removeOperations(["script"]) }; router.execute(decoded)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05)); XCTAssertEqual(calls.count, 1)
    }
    func testEditorCancelAndFailedSaveDoNotWriteAndValidSaveLeavesMenuEmpty() throws {
        let store = store(); store.update { $0.menu = [] }; let original = store.configuration
        let path = directory.appendingPathComponent("script.sh"); try Data("#!/bin/sh\n".utf8).write(to: path)
        let record = OperationRecord(name: "script", parameters: .script(path.path))
        let canceled = OperationEditor(operation: record, existing: false, store: store); canceled.close()
        XCTAssertEqual(store.configuration, original)
        let invalid = OperationEditor(operation: .init(parameters: .directory("/missing-crab")), existing: false, store: store)
        XCTAssertFalse(invalid.save()); invalid.close(); XCTAssertEqual(store.configuration, original)
        let valid = OperationEditor(operation: record, existing: false, store: store)
        XCTAssertTrue(valid.save()); XCTAssertTrue(store.configuration.menu.isEmpty)
        XCTAssertTrue(store.configuration.operations.contains { $0.id == record.id })
        XCTAssertEqual(try String(contentsOf: path), "#!/bin/sh\n")
    }
    func testThreePagesUseCompactCardsAndTwoMenuListsAcrossLanguagesAndStyles() throws {
        for code in AppLocalization.supportedLanguages.map(\.code) {
            for style in AppIconStyle.allCases {
                let store = store(); store.update { $0.languageCode = code; $0.iconStyle = style }
                let scene = SettingsWindowController(store: store)
                defer { scene.window?.close() }
                for page in SettingsPage.allCases {
                    scene.selectPage(page.rawValue)
                    let root = try XCTUnwrap(scene.window?.contentView); root.layoutSubtreeIfNeeded()
                    let views = descendants(root)
                    for navigation in views.compactMap({ $0 as? NSButton }).filter({ $0.accessibilityIdentifier().hasPrefix("nav-") }) {
                        for label in descendants(navigation).compactMap({ $0 as? NSTextField }) {
                            let width = (label.stringValue as NSString).size(withAttributes: [.font: label.font!]).width
                            XCTAssertLessThanOrEqual(width, label.bounds.width + 1, code + ": " + label.stringValue)
                        }
                    }
                    if page == .library {
                        XCTAssertEqual(views.compactMap { $0 as? NSCollectionView }.count, 1)
                        XCTAssertTrue(views.compactMap { $0 as? NSTableView }.isEmpty)
                        let before = store.configuration
                        let controls = try assertLibraryToolbar(in: root, language: code)
                        let frames = controls.map(\.frame)
                        let normalBatch = try XCTUnwrap(controls[3] as? NSButton)
                        XCTAssertFalse(normalBatch is OperationAddButton)
                        XCTAssertNil(normalBatch.menu)
                        XCTAssertEqual(normalBatch.title, L("批量删除"), code)
                        normalBatch.performClick(nil)
                        root.layoutSubtreeIfNeeded()
                        let selectingControls = try assertLibraryToolbar(in: root, language: code)
                        let batch = try XCTUnwrap(selectingControls[3] as? NSButton)
                        XCTAssertNil(batch.menu)
                        XCTAssertEqual(batch.title, L("删除"), code)
                        XCTAssertFalse(batch.isEnabled, code)
                        let cancel = try XCTUnwrap(selectingControls.first { $0.identifier?.rawValue == "library-batch-cancel" } as? NSButton)
                        XCTAssertNil(cancel.menu)
                        cancel.performClick(nil)
                        XCTAssertEqual(try assertLibraryToolbar(in: root, language: code).map(\.frame), frames, code)
                        XCTAssertEqual(store.configuration, before, code)
                    }
                    if page == .menu {
                        XCTAssertTrue(views.compactMap { $0 as? NSOutlineView }.isEmpty)
                        XCTAssertEqual(views.compactMap { $0 as? NSTableView }.count, 2)
                    }
                    XCTAssertFalse(try XCTUnwrap(scene.window).isVisible)
                }
            }
        }
    }
    func testLibraryBatchDeleteButtonRestoresToolbarAndDoesNotWriteWhileSelecting() throws {
        for theme in [WindowTheme.light, .dark] {
            let storeDirectory = directory.appendingPathComponent("batch-toolbar-" + theme.rawValue)
            let store = ConfigurationStore(directory: storeDirectory)
            let builtIn = try XCTUnwrap(OperationRegistry.defaults().first)
            var custom = op("custom"), other = op("other")
            custom.name = "复制项目路径"; other.name = "复制工作目录路径"
            XCTAssertTrue(store.update { $0.languageCode = "zh-Hans"; $0.windowTheme = theme; $0.operations = [builtIn, custom, other]; $0.menu = [] })
            let file = storeDirectory.appendingPathComponent("operations-v1.json")
            let saved = try Data(contentsOf: file), configuration = store.configuration
            let modification = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
            let scene = SettingsWindowController(store: store)
            defer { scene.window?.close() }
            let root = try XCTUnwrap(scene.window?.contentView)
            root.layoutSubtreeIfNeeded()
            let frames = try assertLibraryToolbar(in: root, language: "zh-Hans").map(\.frame)
            func button(_ identifier: String) throws -> NSButton {
                try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == identifier } as? NSButton)
            }
            func card(_ index: Int) throws -> NSCollectionViewItem {
                let collection = try XCTUnwrap(descendants(root).compactMap { $0 as? NSCollectionView }.first)
                return scene.collectionView(collection, itemForRepresentedObjectAt: IndexPath(item: index, section: 0))
            }
            func capture(_ state: String) throws {
                let environment = ProcessInfo.processInfo.environment
                guard let path = environment["CRAB_BATCH_DELETE_PREVIEW_DIR"] ?? environment["TEST_RUNNER_CRAB_BATCH_DELETE_PREVIEW_DIR"] else { return }
                let output = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                root.layoutSubtreeIfNeeded()
                func invalidate(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(invalidate) }
                invalidate(root)
                let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("batch-delete-" + state + "-" + theme.rawValue + ".png"))
            }
            XCTAssertFalse(try button("library-batch") is OperationAddButton)
            XCTAssertNil(try button("library-batch").menu)
            XCTAssertEqual(try button("library-batch").title, L("批量删除"))
            XCTAssertTrue(try button("library-batch").isEnabled)
            XCTAssertFalse(descendants(root).contains { $0.identifier?.rawValue == "library-batch-cancel" && !$0.isHidden })
            XCTAssertTrue(try button("library-add") is OperationAddButton)
            XCTAssertNotNil(try button("library-add").menu)
            try capture("normal")
            try button("library-batch").performClick(nil)
            XCTAssertEqual(try button("library-batch").title, L("删除"))
            XCTAssertNil(try button("library-batch").menu)
            XCTAssertFalse(try button("library-batch").isEnabled)
            XCTAssertNil(try button("library-batch-cancel").menu)
            try assertLibraryToolbar(in: root, language: "zh-Hans")
            let builtInCard = try card(0)
            XCTAssertTrue(descendants(builtInCard.view).compactMap { $0 as? ClosureCheck }.isEmpty)
            try XCTUnwrap(builtInCard.view.subviews.compactMap { $0 as? NSButton }.first).performClick(nil)
            XCTAssertFalse(try button("library-batch").isEnabled)
            let customCard = try card(1)
            try XCTUnwrap(descendants(customCard.view).compactMap { $0 as? ClosureCheck }.first).performClick(nil)
            XCTAssertTrue(try button("library-batch").isEnabled)
            try capture("selecting")
            try button("library-batch-cancel").performClick(nil)
            XCTAssertEqual(try button("library-batch").title, L("批量删除"))
            XCTAssertEqual(try assertLibraryToolbar(in: root, language: "zh-Hans").map(\.frame), frames)
            try button("library-batch").performClick(nil)
            XCTAssertFalse(try button("library-batch").isEnabled, "Leaving batch mode must clear the selection.")
            let reentered = try card(1)
            XCTAssertEqual(try XCTUnwrap(descendants(reentered.view).compactMap { $0 as? ClosureCheck }.first).state, .off)
            try button("library-batch-cancel").performClick(nil)
            XCTAssertEqual(try assertLibraryToolbar(in: root, language: "zh-Hans").map(\.frame), frames)
            XCTAssertEqual(store.configuration, configuration)
            XCTAssertEqual(try Data(contentsOf: file), saved)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date, modification)
            XCTAssertFalse(try XCTUnwrap(scene.window).isVisible)
        }
    }
    func testLibraryBatchCardsOnlyAllowSelectingCustomOperations() throws {
        let builtIn = try XCTUnwrap(OperationRegistry.defaults().first)
        let custom = op("batch-custom")
        for operation in [builtIn, custom] {
            let card = OperationCardItem(); _ = card.view
            var selections: [Bool] = []
            card.configure(operation, snapshot: nil, references: 0, selecting: true, selected: false,
                           edit: {}, toggle: { selections.append($0) }, action: { _ in })
            let checks = descendants(card.view).compactMap { $0 as? ClosureCheck }
            XCTAssertEqual(checks.count, operation.isBuiltIn ? 0 : 1)
            let body = try XCTUnwrap(card.view.subviews.compactMap { $0 as? NSButton }.first)
            for clicks in [1, 2] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                    context: nil, eventNumber: clicks, clickCount: clicks, pressure: 1))
                body.mouseDown(with: event)
            }
            XCTAssertEqual(selections, operation.isBuiltIn ? [] : [true, true])
            if let check = checks.first {
                check.performClick(nil)
                XCTAssertEqual(selections, [true, true, true])
            }
            let expectedCommands = operation.isBuiltIn ? ["加入菜单…"] : ["编辑", "复制", "加入菜单…", "删除"]
            XCTAssertEqual(card.view.menu?.items.map(\.title), expectedCommands.map(L))
        }
    }
    func testEveryTypeCanSaveThroughItsEditorWithoutAddingMenuReferences() throws {
        let root = directory!
        let file = root.appendingPathComponent("template.txt"); try Data("sample".utf8).write(to: file)
        let script = root.appendingPathComponent("sample.sh"); try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        let image = root.appendingPathComponent("image.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:])).write(to: image)
        let app = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "dev.crab.fixture", "CFBundleExecutable": "fixture"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/fixture"); try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let parameters: [OperationParameters] = [
            .tool(.init(action: .copyPath)), .template(.init(template: .init(name: "Template", suffix: "txt", importedPath: file.path))),
            .transfer(.init(move: true, target: root.path)), .directory(root.path), .application(.init(path: app.path)),
            .image(.init(path: image.path)), .script(script.path)
        ]
        let store = store(); store.update { $0.operations = []; $0.menu = [] }
        for parameter in parameters {
            let draft = try XCTUnwrap(OperationUIRegistry.shared.adapter(parameter.kind)).makeDraft()
            let defaultIcon = try XCTUnwrap(draft.iconID, parameter.kind)
            XCTAssertTrue(MenuNodeIcons.catalog.contains { $0.id == defaultIcon }, parameter.kind)
            let operation = OperationRecord(name: parameter.kind, parameters: parameter)
            let editor = OperationEditor(operation: operation, existing: false, store: store)
            XCTAssertEqual(editor.draft.iconID, defaultIcon, parameter.kind)
            XCTAssertTrue(editor.save(), parameter.kind)
            XCTAssertEqual(store.configuration.operations.first { $0.id == operation.id }?.iconID, defaultIcon, parameter.kind)
        }
        XCTAssertEqual(store.configuration.operations.count, 7); XCTAssertTrue(store.configuration.menu.isEmpty)
        XCTAssertEqual(try String(contentsOf: file), "sample")
        XCTAssertEqual(try Data(contentsOf: image).count > 0, true)
        let imports = self.store(); imports.update { $0.operations = []; $0.menu = [] }
        let scene = SettingsWindowController(store: imports)
        defer { scene.window?.close() }
        let sources: [String: URL] = ["template": file, "transfer": root, "directory": root, "application": app, "image": image, "script": script]
        var picked: [String] = []
        scene.operationFilePicker = { kind in picked.append(kind); return sources[kind].map { [$0] } ?? [] }
        let add = try XCTUnwrap(descendants(scene.window!.contentView!).compactMap { $0 as? OperationAddButton }.first { $0.identifier?.rawValue == "library-add" })
        XCTAssertEqual(add.menu?.items.map(\.title), ["文件模板", "传送目录", "快捷目录", "应用入口", "自定义图标", "自定义脚本"])
        for index in OperationFileImport.kinds.indices {
            let item = try XCTUnwrap(add.menu?.item(at: index))
            _ = item.target?.perform(try XCTUnwrap(item.action), with: item)
        }
        let deadline = Date().addingTimeInterval(3)
        while imports.configuration.operations.count < 6 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(picked, OperationFileImport.kinds)
        XCTAssertEqual(Set(imports.configuration.operations.map { $0.parameters.kind }), Set(OperationFileImport.kinds))
        for operation in imports.configuration.operations {
            let draft = try XCTUnwrap(OperationUIRegistry.shared.adapter(operation.parameters.kind)).makeDraft()
            XCTAssertEqual(operation.iconID, draft.iconID, operation.parameters.kind)
        }
        XCTAssertTrue(imports.configuration.menu.isEmpty)
        let snapshot = imports.configuration
        scene.operationFilePicker = { _ in [] }; scene.addOperation(kind: "script")
        XCTAssertEqual(imports.configuration, snapshot)
    }
    func testRegisteredTypeUsesPlannerAndExecutorWithoutTypeBranches() throws {
        let kind = "test.extension"
        OperationRegistry.shared.register(.init(kind: kind, title: "Test", category: .tools, symbol: "tools", defaultName: { _ in "Test" }, validation: { _ in nil }, supports: { _, _ in true }))
        let op = OperationRecord(id: "extension", parameters: .unknown(kind, .object(["value": .string("opaque")])) )
        let store = store(); store.update { $0.operations = [op]; $0.menu = [.reference(op.id)] }
        let planned = MenuPlanner.items(configuration: store.configuration, context: .init(urls: [], directory: directory))
        XCTAssertEqual(planned.first?.operation, op)
        let router = ActionRouter(store: store); var received: OperationRecord?
        router.registerExecutor(kind: kind) { value, _ in received = value }
        router.execute(.init(operationID: op.id, paths: [], targetDirectory: directory.path))
        XCTAssertEqual(received, op)
    }
    func testActualMenuSelectorDispatchesLatestScriptAndKeepsOriginalPermissions() throws {
        let output = directory.appendingPathComponent("result.txt"), script = directory.appendingPathComponent("run.sh")
        try Data("#!/bin/sh\nprintf old > \"$CRAB_DIRECTORY/result.txt\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: script.path)
        let store = store(); store.update { $0.operations = [.init(id: "run", parameters: .script(script.path))]; $0.menu = [.reference("run")] }
        let router = ActionRouter(store: store)
        let menu = ContextMenuBuilder(configuration: store.configuration, handler: router.execute).menu(selectedURLs: [], directory: directory)
        let item = try XCTUnwrap(menu.items.first)
        try Data("#!/bin/sh\nprintf '%s' \"$CRAB_SELECTED_COUNT\" > \"$CRAB_DIRECTORY/result.txt\"\n".utf8).write(to: script)
        _ = item.target?.perform(try XCTUnwrap(item.action), with: item)
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: output.path) && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(try String(contentsOf: output), "0")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testLargeLibraryOnlyInstantiatesVisibleCardItems() throws {
        let store = store(); store.update { config in config.operations = (0..<1000).map { self.op("item-" + String($0)) } }
        let scene = SettingsWindowController(store: store); defer { scene.window?.close() }
        let root = try XCTUnwrap(scene.window?.contentView); root.layoutSubtreeIfNeeded()
        let collection = try XCTUnwrap(descendants(root).compactMap { $0 as? NSCollectionView }.first)
        collection.layoutSubtreeIfNeeded()
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1000)
        XCTAssertLessThan(collection.visibleItems().count, 20)
        XCTAssertFalse(scene.window!.isVisible)
    }
    func testImageIOThumbnailPreservesColorAspectAndBounds() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 512, height: 256, bitsPerComponent: 8, bytesPerRow: 2048, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
        let path = directory.appendingPathComponent("large.png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:])).write(to: path)
        XCTAssertEqual(MenuIconPreview.dimensions(at: path.path), CGSize(width: 512, height: 256))
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(MenuIconPreview.thumbnail(at: path.path))))
        XCTAssertEqual(pixels.pixelsWide, 64); XCTAssertEqual(pixels.pixelsHigh, 32)
        XCTAssertGreaterThan(try XCTUnwrap(pixels.colorAt(x: 32, y: 16)).redComponent, 0.9)
    }
    func testBuiltInCardsOpenDetailsWithoutDestructiveControlsAndCannotSaveOrDelete() throws {
        let store = store(), builtIn = try XCTUnwrap(OperationRegistry.defaults().first)
        let custom = op("custom"); store.update { $0.operations = [builtIn, custom]; $0.menu = [.reference(builtIn.id), .reference(custom.id)] }
        let card = OperationCardItem(); _ = card.view
        var edits = 0
        card.configure(builtIn, snapshot: .init(summary: "Summary", reason: nil, image: nil), references: 1, selecting: false, selected: false, edit: { edits += 1 }, toggle: { _ in }, action: { _ in })
        let views = descendants(card.view)
        XCTAssertEqual(card.view.bounds.height, 56)
        XCTAssertTrue(views.compactMap { $0 as? NSPopUpButton }.isEmpty)
        XCTAssertTrue(views.compactMap { $0 as? ClosureCheck }.isEmpty)
        XCTAssertEqual(card.view.menu?.items.map(\.title), [L("加入菜单…")])
        views.compactMap { $0 as? NSButton }.first?.performClick(nil); XCTAssertEqual(edits, 1)
        let editor = OperationEditor(operation: builtIn, existing: true, store: store)
        XCTAssertTrue(editor.isReadOnly)
        editor.updateDraft { $0.name = "Changed" }
        XCTAssertEqual(editor.draft, builtIn)
        XCTAssertFalse(editor.setIcon("crab.star"))
        XCTAssertFalse(editor.save()); editor.close()
        XCTAssertEqual(store.configuration.operations.first, builtIn)
        store.update { $0.removeOperations([builtIn.id, custom.id]) }
        XCTAssertEqual(store.configuration.operations, [builtIn]); XCTAssertEqual(store.configuration.referenceCount(builtIn.id), 1)
        card.configure(custom, snapshot: nil, references: 0, selecting: false, selected: false, edit: {}, toggle: { _ in }, action: { _ in })
        XCTAssertEqual(card.view.menu?.items.map(\.title), ["编辑", "复制", "加入菜单…", "删除"].map(L))
    }

    func testLibraryAndPickerCardsIdentifyBuiltInAndCustomOperations() throws {
        let builtIn = try XCTUnwrap(OperationRegistry.defaults().first), custom = op("custom-origin")
        for code in AppLocalization.supportedLanguages.map(\.code) {
            AppLocalization.languageCode = code
            for operation in [builtIn, custom] {
                let expected = L(operation.isBuiltIn ? "内置" : "自定义")
                let card = OperationCardItem(); _ = card.view
                card.configure(operation, snapshot: nil, references: 0, selecting: false, selected: false,
                               edit: {}, toggle: { _ in }, action: { _ in })
                var badge = try XCTUnwrap(descendants(card.view).first { $0.identifier?.rawValue == "operation-origin" })
                let label = try XCTUnwrap(descendants(badge).compactMap { $0 as? NSTextField }.first { $0.stringValue == expected })
                XCTAssertLessThanOrEqual(try XCTUnwrap(label.cell).cellSize.width, label.bounds.width, code)
                let name = try XCTUnwrap(descendants(card.view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "operation-name" })
                XCTAssertFalse(name.convert(name.bounds, to: card.view).intersects(badge.convert(badge.bounds, to: card.view)))
                var selections = 0
                card.configurePicker(operation, snapshot: nil, selected: false, toggle: { selections += 1 })
                badge = try XCTUnwrap(descendants(card.view).first { $0.identifier?.rawValue == "operation-origin" })
                XCTAssertTrue(descendants(badge).compactMap { $0 as? NSTextField }.contains { $0.stringValue == expected })
                let toggle = try XCTUnwrap(descendants(card.view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "operation-picker-toggle-" + operation.id })
                toggle.performClick(nil)
                XCTAssertEqual(selections, 1)
                XCTAssertNil(card.view.menu)
            }
        }
    }

    func testBuiltInDetailsExposeSelectableValuesAndRejectEveryMutationEntryPoint() throws {
        let store = store()
        let defaults = OperationRegistry.defaults()
        var kinds = Set<String>()
        let representatives = defaults.filter { kinds.insert($0.parameters.kind).inserted }
        XCTAssertTrue(store.update { $0.operations = representatives })
        let snapshot = store.configuration
        for operation in representatives {
            let editor = OperationEditor(operation: operation, existing: true, store: store)
            defer { editor.close() }
            XCTAssertTrue(editor.isReadOnly, operation.parameters.kind)
            XCTAssertEqual(editor.window?.title, L("查看操作"))
            let root = try XCTUnwrap(editor.window?.contentView)
            let views = descendants(root)
            XCTAssertFalse(views.contains { $0.identifier?.rawValue == "operation-save" })
            XCTAssertTrue(views.compactMap { $0 as? NSPopUpButton }.isEmpty, operation.parameters.kind)
            XCTAssertTrue(views.compactMap { $0 as? ClosureCheck }.isEmpty, operation.parameters.kind)
            XCTAssertFalse(views.compactMap { $0 as? NSButton }.contains { $0.title == L("取消") })
            let close = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-close" } as? NSButton)
            XCTAssertTrue(close.isEnabled)
            let values = views.compactMap { $0 as? NSTextField }.filter { ($0.delegate as? OperationEditor) === editor }
            XCTAssertFalse(values.isEmpty)
            for field in values {
                XCTAssertFalse(field.isEditable, operation.parameters.kind)
                XCTAssertTrue(field.isSelectable, operation.parameters.kind)
            }
            for button in views.compactMap({ $0 as? NSButton }).filter({ $0 !== close }) {
                XCTAssertFalse(button.isEnabled, operation.parameters.kind)
            }
            let name = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-name" } as? NSTextField)
            XCTAssertEqual(name.stringValue, operation.displayName)
            name.stringValue = "Uncommitted UI value"
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: name))
            editor.updateDraft { $0.name = "Mutated"; $0.iconID = "crab.star"; $0.enabled = false }
            XCTAssertEqual(editor.draft, operation, operation.parameters.kind)
            XCTAssertFalse(editor.setIcon("crab.star"))
            XCTAssertFalse(editor.save())
            XCTAssertEqual(store.configuration, snapshot)
        }
    }

    func testBuiltInDesktopDetailsUseCompactStaticRowsWithoutAutomaticallySelectingName() throws {
        let operation = try XCTUnwrap(OperationRegistry.defaults().first { $0.id == "system.icon.desktop" })
        for code in AppLocalization.supportedLanguages.map(\.code) where !code.isEmpty {
            AppLocalization.languageCode = code
            for theme in [WindowTheme.light, .dark] {
                let store = store()
                XCTAssertTrue(store.update { $0.languageCode = code; $0.windowTheme = theme })
                let original = store.configuration
                let owner = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 680, height: 460),
                                     styleMask: [.titled, .closable], backing: .buffered, defer: false)
                owner.isReleasedWhenClosed = false; owner.animationBehavior = .none
                owner.makeKeyAndOrderFront(nil)
                let detail = OperationEditor(operation: operation, existing: true, store: store)
                let window = try XCTUnwrap(detail.window); window.animationBehavior = .none
                defer { detail.close(); owner.close() }
                detail.present(asSheetFor: owner)
                let root = try XCTUnwrap(window.contentView)
                root.layoutSubtreeIfNeeded()
                let views = descendants(root)
                let name = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-name" } as? NSTextField)
                let value = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-detail-value-图标来源" } as? NSTextField)
                let icon = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-icon" } as? NSImageView)
                let origin = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-origin" })
                XCTAssertTrue(window.initialFirstResponder === root, code)
                XCTAssertTrue(window.firstResponder === root, code)
                XCTAssertNil(name.currentEditor(), code)
                XCTAssertEqual(name.stringValue, L("桌面"), code)
                XCTAssertEqual(value.stringValue, L("桌面"), code)
                XCTAssertEqual(value.accessibilityLabel(), L("图标来源"), code)
                XCTAssertEqual(value.toolTip, L("桌面"), code)
                XCTAssertTrue(value.isSelectable); XCTAssertFalse(value.isEditable)
                XCTAssertNotNil(icon.image)
                XCTAssertEqual(root.bounds.width, 460, accuracy: 0.5)
                XCTAssertLessThan(root.bounds.height, 210, code)
                XCTAssertGreaterThan(try XCTUnwrap(name.font).pointSize, try XCTUnwrap(value.font).pointSize)
                XCTAssertFalse(name.convert(name.bounds, to: root).intersects(origin.convert(origin.bounds, to: root)), code)
                XCTAssertTrue(views.compactMap { $0 as? NSPopUpButton }.isEmpty, code)
                XCTAssertEqual(views.compactMap { $0 as? NSButton }.map { $0.identifier?.rawValue }, ["operation-close"], code)

                let environment = ProcessInfo.processInfo.environment
                if code == "zh-Hans", let path = environment["CRAB_OPERATION_EDITOR_PREVIEW_DIR"] ?? environment["TEST_RUNNER_CRAB_OPERATION_EDITOR_PREVIEW_DIR"] {
                    let destination = URL(fileURLWithPath: path, isDirectory: true)
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    func invalidate(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(invalidate) }
                    invalidate(root)
                    let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                    root.cacheDisplay(in: root.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: destination.appendingPathComponent("builtin-desktop-" + theme.rawValue + ".png"))
                }

                name.selectText(nil)
                let textEditor = try XCTUnwrap(name.currentEditor() as? NSTextView)
                XCTAssertTrue(window.firstResponder === textEditor, code)
                XCTAssertGreaterThan(textEditor.selectedRange().length, 0, code)
                XCTAssertTrue(window.makeFirstResponder(root))
                XCTAssertNil(name.currentEditor())
                detail.close()
                let deadline = Date().addingTimeInterval(2)
                while owner.attachedSheet != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
                XCTAssertNil(owner.attachedSheet)
                detail.present(asSheetFor: owner)
                XCTAssertTrue(window.firstResponder === root, code)
                XCTAssertNil(name.currentEditor(), code)
                XCTAssertEqual(detail.draft, operation)
                XCTAssertEqual(store.configuration, original)
            }
        }
    }
    func testDirectFileImportCommitsWholeSelectionAndRollsBackFailedImports() throws {
        let store = store(); store.update { $0.operations = []; $0.menu = [] }
        let one = directory.appendingPathComponent("one.txt"), two = directory.appendingPathComponent("two.md")
        try Data("one".utf8).write(to: one); try Data("two".utf8).write(to: two)
        let prepared = try OperationFileImport.prepare(kind: "template", urls: [one, two], store: store)
        XCTAssertTrue(store.configuration.operations.isEmpty)
        try prepared.commit(to: store)
        XCTAssertEqual(store.configuration.operations.map(\.name), ["one", "two"])
        XCTAssertTrue(store.configuration.menu.isEmpty)
        for record in store.configuration.operations {
            guard case .template(let p) = record.parameters else { return XCTFail() }
            XCTAssertTrue(try XCTUnwrap(p.template.importedPath).hasPrefix(store.assetsDirectory.path))
        }
        let assets = try FileManager.default.contentsOfDirectory(atPath: store.assetsDirectory.path)
        XCTAssertThrowsError(try OperationFileImport.prepare(kind: "template", urls: [one, directory.appendingPathComponent("missing")], store: store))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: store.assetsDirectory.path)), Set(assets))
        XCTAssertEqual(store.configuration.operations.count, 2)
        let scripts = try OperationFileImport.prepare(kind: "script", urls: [one, two], store: store)
        try scripts.commit(to: store)
        XCTAssertEqual(Array(store.configuration.operations.suffix(2)).map(\.parameters), [.script(one.path), .script(two.path)])
        let dirs = try OperationFileImport.prepare(kind: "directory", urls: [directory], store: store)
        try dirs.commit(to: store)
        let transfers = try OperationFileImport.prepare(kind: "transfer", urls: [directory], store: store)
        try transfers.commit(to: store)
        XCTAssertEqual(store.configuration.operations.last?.parameters, .transfer(.init(target: directory.path)))
        XCTAssertEqual(try String(contentsOf: one), "one"); XCTAssertEqual(try String(contentsOf: two), "two")
        XCTAssertTrue(store.configuration.menu.isEmpty)
    }
    func testTwoMenuListsFollowSelectionAndRenameReferencesWithoutChangingOperation() throws {
        let store = store(), operation = op("source")
        let root = MenuNode.reference(operation.id), child = MenuNode.reference(operation.id)
        let group = MenuNode(kind: .group, name: "Group", children: [child])
        store.update { $0.operations = [operation]; $0.menu = [root, group] }
        let editor = MenuEditorView(store: store)
        let tables = descendants(editor).compactMap { $0 as? NSTableView }
        let left = try XCTUnwrap(tables.first { $0.identifier?.rawValue == "menu-primary" })
        let right = try XCTUnwrap(tables.first { $0.identifier?.rawValue == "menu-secondary" })
        XCTAssertEqual(left.numberOfRows, 2); XCTAssertEqual(right.numberOfRows, 0)
        left.selectRowIndexes([1], byExtendingSelection: false)
        XCTAssertEqual(right.numberOfRows, 1)
        right.selectRowIndexes([0], byExtendingSelection: false)
        _ = right.target?.perform(try XCTUnwrap(right.doubleAction), with: right)
        let cell = try XCTUnwrap(right.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let field = try XCTUnwrap(cell.textField); XCTAssertTrue(field.isEditable)
        field.stringValue = "Cancelled"
        XCTAssertTrue(editor.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertNil(store.configuration.menuNode(child.id)?.name)
        _ = right.target?.perform(try XCTUnwrap(right.doubleAction), with: right)
        let edited = try XCTUnwrap((right.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField)
        edited.stringValue = "Inline label"
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: edited))
        XCTAssertEqual(store.configuration.menuNode(child.id)?.name, "Inline label")
        XCTAssertTrue(editor.renameNode(child.id, name: "Child label"))
        XCTAssertEqual(store.configuration.menuNode(child.id)?.name, "Child label")
        XCTAssertEqual(store.configuration.menuNode(root.id)?.name, nil)
        XCTAssertEqual(store.configuration.operations, [operation])
        left.selectRowIndexes([0], byExtendingSelection: false); XCTAssertEqual(right.numberOfRows, 0)
        let rootDrag = MenuDragFixture(source: left, writer: try XCTUnwrap(editor.tableView(left, pasteboardWriterForRow: 0)))
        let foreign = MenuDragFixture(source: NSTableView(), writer: try XCTUnwrap(editor.tableView(left, pasteboardWriterForRow: 0)))
        XCTAssertEqual(editor.tableView(left, validateDrop: foreign, proposedRow: 1, proposedDropOperation: .on), [])
        XCTAssertFalse(editor.tableView(left, acceptDrop: foreign, row: 1, dropOperation: .on))
        XCTAssertEqual(editor.tableView(left, validateDrop: rootDrag, proposedRow: 1, proposedDropOperation: .on), .move)
        XCTAssertTrue(editor.tableView(left, acceptDrop: rootDrag, row: 1, dropOperation: .on))
        XCTAssertEqual(left.numberOfRows, 1); XCTAssertEqual(right.numberOfRows, 2)
        XCTAssertEqual(store.configuration.menu[0].children.map(\.id), [child.id, root.id])
        let reorderDrag = MenuDragFixture(source: right, writer: try XCTUnwrap(editor.tableView(right, pasteboardWriterForRow: 1)))
        XCTAssertEqual(editor.tableView(right, validateDrop: reorderDrag, proposedRow: 0, proposedDropOperation: .above), .move)
        XCTAssertTrue(editor.tableView(right, acceptDrop: reorderDrag, row: 0, dropOperation: .above))
        XCTAssertEqual(store.configuration.menu[0].children.map(\.id), [root.id, child.id])
        let groupDrag = MenuDragFixture(source: left, writer: try XCTUnwrap(editor.tableView(left, pasteboardWriterForRow: 0)))
        XCTAssertEqual(editor.tableView(right, validateDrop: groupDrag, proposedRow: 0, proposedDropOperation: .above), [])
        XCTAssertFalse(editor.moveNode(group.id, into: group.id, at: 0))
        let childDrag = MenuDragFixture(source: right, writer: try XCTUnwrap(editor.tableView(right, pasteboardWriterForRow: 1)))
        XCTAssertEqual(editor.tableView(left, validateDrop: childDrag, proposedRow: 0, proposedDropOperation: .above), .move)
        XCTAssertTrue(editor.tableView(left, acceptDrop: childDrag, row: 0, dropOperation: .above))
        XCTAssertEqual(store.configuration.menu.map(\.id), [child.id, group.id])
        XCTAssertEqual(store.configuration.menuNode(child.id)?.name, "Child label")
        try store.configuration.validate()
    }

    func testPerReferenceAndGroupIconChoicesRoundTripAndBuildSharedMenus() throws {
        let store = store(), operation = op("icon-source")
        let first = MenuNode.reference(operation.id), second = MenuNode.reference(operation.id)
        let child = MenuNode.reference(operation.id)
        let group = MenuNode(kind: .group, name: "Custom group", children: [child])
        store.update { $0.operations = [operation]; $0.menu = [first, second, group]; $0.iconStyle = .monochrome }
        let editor = MenuEditorView(store: store)
        XCTAssertTrue(editor.setIcon("crab.star", for: first.id))
        XCTAssertTrue(editor.setIcon(MenuNodeIcons.hiddenID, for: second.id))
        XCTAssertTrue(editor.setIcon("system.icon.folder", for: group.id))
        XCTAssertTrue(editor.setIcon("crab.heart", for: child.id))
        XCTAssertFalse(editor.setIcon("unregistered", for: first.id))
        XCTAssertEqual(store.configuration.operations, [operation])
        XCTAssertEqual(store.configuration.menuNode(first.id)?.iconID, "crab.star")
        XCTAssertEqual(store.configuration.menuNode(second.id)?.iconID, MenuNodeIcons.hiddenID)
        let config = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(store.configuration))
        XCTAssertEqual(config, store.configuration)
        let menu = ContextMenuBuilder(configuration: config, handler: { _ in }).menu(selectedURLs: [directory.appendingPathComponent("file.txt")], directory: directory)
        XCTAssertTrue(try XCTUnwrap(menu.items[0].image).isTemplate)
        XCTAssertNil(menu.items[1].image)
        XCTAssertFalse(try XCTUnwrap(menu.items[2].image).isTemplate)
        XCTAssertTrue(try XCTUnwrap(menu.items[2].submenu?.items[0].image).isTemplate)
        for item in [menu.items[0], menu.items[1], try XCTUnwrap(menu.items[2].submenu?.items[0])] {
            XCTAssertEqual((item.representedObject as? ActionRequest)?.operationID, operation.id)
        }
        XCTAssertTrue(editor.setIcon(nil, for: first.id)); XCTAssertNil(store.configuration.menuNode(first.id)?.iconID)
        let scene = SettingsWindowController(store: store); defer { scene.window?.close() }
        scene.selectPage(SettingsPage.general.rawValue)
        XCTAssertFalse(descendants(scene.window!.contentView!).contains { $0.identifier?.rawValue == "general-heading-icons" })
        let general = try XCTUnwrap((JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])?["general"] as? [String: Any])
        XCTAssertNil(general["menuIconVisibility"]); XCTAssertNil(general["showMenuIcons"])
    }
    func testBuiltInMenuIconCatalogRendersBothStylesWithoutFileAssets() throws {
        XCTAssertEqual(Set(MenuNodeIcons.catalog.map(\.id)).count, MenuNodeIcons.catalog.count)
        for style in AppIconStyle.allCases {
            for entry in MenuNodeIcons.catalog {
                let image = try XCTUnwrap(MenuNodeIcons.catalogImage(entry.id, style: style), entry.id)
                XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
                XCTAssertNotNil(MenuIconPreview.pngData(from: image))
                if entry.id.hasPrefix("system.") { XCTAssertFalse(image.isTemplate) }
                else { XCTAssertEqual(image.isTemplate, style == .monochrome) }
            }
        }
        XCTAssertNil(MenuNodeIcons.catalogImage("arbitrary-path", style: .color))
    }

    func testOperationIconIsOptionalInExistingConfigurationAndPreservedByCopies() throws {
        let original = OperationRecord(id: "legacy-directory", name: "Directory", parameters: .directory(directory.path))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "iconID")
        let decoded = try JSONDecoder().decode(OperationRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.iconID)
        XCTAssertNotNil(OperationImages.source(decoded))

        var custom = decoded; custom.iconID = "crab.star"
        let copy = custom.duplicated()
        XCTAssertNotEqual(copy.id, custom.id)
        XCTAssertEqual(copy.iconID, custom.iconID)
        XCTAssertEqual(try JSONDecoder().decode(OperationRecord.self, from: JSONEncoder().encode(copy)), copy)
    }

    func testOperationIconEditingCommitsOnlyOnSaveAndKeepsMenuIconOverrides() throws {
        let configurationDirectory = directory.appendingPathComponent("icon-editor")
        let store = ConfigurationStore(directory: configurationDirectory)
        var operation = OperationRecord(name: "Directory", parameters: .directory(directory.path))
        operation.iconID = "category.common"
        var explicit = MenuNode.reference(operation.id); explicit.iconID = "crab.heart"
        var hidden = MenuNode.reference(operation.id); hidden.iconID = MenuNodeIcons.hiddenID
        let inherited = MenuNode.reference(operation.id)
        XCTAssertTrue(store.update { $0.operations = [operation]; $0.menu = [inherited, explicit, hidden] })
        let original = store.configuration
        let file = configurationDirectory.appendingPathComponent("operations-v1.json")
        let savedBytes = try Data(contentsOf: file)

        let cancelled = OperationEditor(operation: operation, existing: true, store: store)
        XCTAssertTrue(cancelled.setIcon("crab.star"))
        XCTAssertEqual(cancelled.draft.iconID, "crab.star")
        XCTAssertFalse(cancelled.setIcon("unknown-icon"))
        XCTAssertEqual(cancelled.draft.iconID, "crab.star")
        cancelled.close()
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(try Data(contentsOf: file), savedBytes)

        let editor = OperationEditor(operation: operation, existing: true, store: store)
        XCTAssertFalse(editor.setIcon(nil))
        XCTAssertEqual(editor.draft.iconID, "category.common")
        XCTAssertTrue(editor.setIcon(MenuNodeIcons.hiddenID))
        XCTAssertNil(OperationImages.image(editor.draft, configuration: store.configuration))
        XCTAssertTrue(editor.setIcon("crab.star"))
        XCTAssertTrue(editor.save())
        let reloaded = ConfigurationStore(directory: configurationDirectory).configuration
        XCTAssertEqual(reloaded.operations.first?.iconID, "crab.star")
        XCTAssertEqual(reloaded.operations.first?.parameters, operation.parameters)
        XCTAssertEqual(reloaded.menu, original.menu)
        XCTAssertEqual(reloaded.referenceCount(operation.id), 3)
    }

    func testLibraryIconEditingPermissionsKeepApplicationAndImageArtworkFixed() throws {
        let store = store()
        let parameters: [OperationParameters] = [
            .tool(.init(action: .copyPath)),
            .template(.init(template: .init(name: "Template", suffix: "txt"))),
            .transfer(.init(target: directory.path)), .directory(directory.path),
            .application(.init(path: directory.appendingPathComponent("Missing.app").path)),
            .image(.init(remove: true)), .script(directory.appendingPathComponent("sample.sh").path)
        ]
        for parameter in parameters {
            let operation = OperationRecord(iconID: "crab.heart", parameters: parameter)
            let editor = OperationEditor(operation: operation, existing: true, store: store)
            let canEdit = !["application", "image"].contains(parameter.kind)
            XCTAssertFalse(editor.isReadOnly, parameter.kind)
            XCTAssertEqual(editor.canEditIcon, canEdit, parameter.kind)
            let root = try XCTUnwrap(editor.window?.contentView)
            let icon = try XCTUnwrap(descendants(root).first { $0.identifier?.rawValue == "operation-icon" })
            XCTAssertEqual(icon is NSButton, canEdit, parameter.kind)
            XCTAssertEqual(icon is NSImageView, !canEdit, parameter.kind)
            XCTAssertFalse(editor.setIcon(nil), parameter.kind)
            XCTAssertEqual(editor.draft, operation, parameter.kind)
            XCTAssertEqual(editor.setIcon("crab.star"), canEdit, parameter.kind)
            XCTAssertEqual(editor.setIcon(MenuNodeIcons.hiddenID), canEdit, parameter.kind)
            if canEdit {
                XCTAssertEqual(editor.draft.iconID, MenuNodeIcons.hiddenID, parameter.kind)
                XCTAssertFalse(editor.setIcon(nil), parameter.kind)
                XCTAssertEqual(editor.draft.iconID, MenuNodeIcons.hiddenID, parameter.kind)
            } else {
                XCTAssertEqual(editor.draft, operation, parameter.kind)
            }
            editor.close()
        }
    }

    func testIconPickerOnlyOffersDefaultForMenuChoices() throws {
        for allowsDefault in [false, true] {
            var selections: [String?] = []
            let picker = CatalogIconPicker.make(title: "选择图标", selectedID: "crab.star", style: .color,
                                                allowsDefault: allowsDefault) { selections.append($0) }
            let root = try XCTUnwrap(picker.contentViewController?.view)
            let buttons = descendants(root).compactMap { $0 as? NSButton }
            let defaults = buttons.first { $0.identifier?.rawValue == "catalog-icon-default" }
            XCTAssertEqual(defaults != nil, allowsDefault)
            XCTAssertEqual(buttons.contains { $0.title == L("使用默认图标") }, allowsDefault)
            if allowsDefault {
                try XCTUnwrap(defaults).performClick(nil)
                XCTAssertEqual(selections.count, 1)
                XCTAssertNil(selections[0])
            }
            try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "catalog-icon-hidden" }).performClick(nil)
            XCTAssertEqual(selections.last ?? nil, MenuNodeIcons.hiddenID)
            picker.close()
        }
    }

    func testMenuIconsRejectImageChangesButAllowApplicationChanges() throws {
        let image = OperationRecord(iconID: "category.customIcons", parameters: .image(.init(remove: true)))
        let builtInImage = try XCTUnwrap(OperationRegistry.defaults().first { $0.parameters.kind == "image" })
        let application = OperationRecord(parameters: .application(.init(path: directory.appendingPathComponent("Missing.app").path)))
        let rootImage = MenuNode.reference(image.id), nestedImage = MenuNode.reference(builtInImage.id)
        let app = MenuNode.reference(application.id)
        let group = MenuNode(kind: .group, name: "Icons", children: [nestedImage])
        let store = store()
        XCTAssertTrue(store.update { $0.operations = [image, builtInImage, application]; $0.menu = [rootImage, group, app] })
        let original = store.configuration
        let editor = MenuEditorView(store: store)
        let choices: [String?] = [nil, MenuNodeIcons.hiddenID, "crab.star"]
        for node in [rootImage, nestedImage] {
            for iconID in choices {
                XCTAssertFalse(editor.setIcon(iconID, for: node.id))
                XCTAssertEqual(store.configuration, original)
            }
        }
        let primary = try XCTUnwrap(descendants(editor).first { $0.identifier?.rawValue == "menu-primary" } as? NSTableView)
        let imageCell = try XCTUnwrap(editor.tableView(primary, viewFor: primary.tableColumns.first, row: 0))
        let imageButton = try XCTUnwrap(descendants(imageCell).first { $0.identifier?.rawValue == "menu-icon-" + rootImage.id } as? NSButton)
        XCTAssertNotEqual(imageButton.toolTip, L("双击更换图标"))
        primary.selectRowIndexes([1], byExtendingSelection: false)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        imageButton.mouseDown(with: event)
        XCTAssertEqual(primary.selectedRow, 0)
        XCTAssertTrue(editor.setIcon("crab.star", for: app.id))
        XCTAssertEqual(store.configuration.menuNode(app.id)?.iconID, "crab.star")
        XCTAssertTrue(editor.setIcon(nil, for: app.id))
        XCTAssertNil(store.configuration.menuNode(app.id)?.iconID)
        XCTAssertEqual(store.configuration.operations, original.operations)
        XCTAssertEqual(store.configuration.menuNode(rootImage.id), rootImage)
        XCTAssertEqual(store.configuration.menuNode(group.id), group)
    }

    func testResetMenuIconInheritsLibraryArtworkIncludingScriptsAndApplicationPreviews() throws {
        let records: [OperationRecord] = [
            .init(iconID: "crab.star", parameters: .directory(directory.path)),
            .init(iconID: "crab.heart", parameters: .script(directory.appendingPathComponent("sample.sh").path)),
            .init(parameters: .application(.init(path: directory.appendingPathComponent("Missing.app").path))),
            .init(iconID: MenuNodeIcons.hiddenID, parameters: .script(directory.appendingPathComponent("hidden.sh").path))
        ]
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<8 { for x in 0..<8 { bitmap.setColor(x < 4 ? .red : .green, atX: x, y: y) } }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let store = store()
        let nodes = records.map { operation -> MenuNode in
            var node = MenuNode.reference(operation.id); node.iconID = "category.tools"; return node
        }
        var otherReference = MenuNode.reference(records[1].id); otherReference.iconID = "crab.terminal"
        let group = MenuNode(kind: .group, name: "References", children: nodes)
        XCTAssertTrue(store.update { $0.operations = records; $0.menu = [otherReference, group] })
        let editor = MenuEditorView(store: store)
        for node in nodes {
            XCTAssertTrue(editor.setIcon(nil, for: node.id))
            XCTAssertNil(store.configuration.menuNode(node.id)?.iconID)
        }
        XCTAssertEqual(store.configuration.operations, records)
        XCTAssertEqual(store.configuration.menuNode(otherReference.id), otherReference)
        for style in AppIconStyle.allCases {
            var configuration = store.configuration; configuration.iconStyle = style
            configuration.previews = [records[2].id: OperationPreview(data: png)]
            let transported = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
            for (operation, originalNode) in zip(records, nodes) {
                let node = try XCTUnwrap(transported.menuNode(originalNode.id))
                let actual = MenuNodeIcons.image(node: node, operation: operation, configuration: transported, allowFileRead: false)
                let expected = OperationImages.image(operation, configuration: transported, allowFileRead: false)
                if operation.iconID == MenuNodeIcons.hiddenID { XCTAssertNil(actual) }
                else {
                    let actual = try XCTUnwrap(actual, operation.parameters.kind)
                    let expected = try XCTUnwrap(expected, operation.parameters.kind)
                    XCTAssertEqual(MenuIconPreview.pngData(from: actual), MenuIconPreview.pngData(from: expected), operation.parameters.kind)
                    XCTAssertEqual(actual.isTemplate, expected.isTemplate, operation.parameters.kind)
                    if operation.parameters.kind == "application" { XCTAssertFalse(actual.isTemplate) }
                }
            }
        }
    }

    func testOperationIconsRenderInFinderWithoutFileReadsAndRespectReferenceChoices() throws {
        var operation = OperationRecord(parameters: .directory("/missing-crab-icon-test"))
        var configuration = AppConfiguration(); configuration.operations = [operation]; configuration.previews = [:]
        let inherited = MenuNode.reference(operation.id)
        var explicit = inherited; explicit.iconID = "crab.heart"
        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            for iconID in ["category.newFile", "crab.star", "system.icon.folder"] {
                operation.iconID = iconID
                let image = try XCTUnwrap(OperationImages.image(operation, configuration: configuration, allowFileRead: false), iconID)
                XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
                XCTAssertEqual(image.isTemplate, style == .monochrome && !iconID.hasPrefix("system."), iconID)
                XCTAssertNotNil(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: false))
            }
            operation.iconID = MenuNodeIcons.hiddenID
            XCTAssertNil(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
            XCTAssertNil(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: false))
            XCTAssertNotNil(MenuNodeIcons.image(node: explicit, operation: operation, configuration: configuration, allowFileRead: false))
            operation.parameters = .script("/missing-crab-script.sh"); operation.iconID = "category.scripts"
            XCTAssertNotNil(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
            XCTAssertNotNil(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: false))
            XCTAssertNotNil(MenuNodeIcons.image(node: explicit, operation: operation, configuration: configuration, allowFileRead: false))
            operation.parameters = .directory("/missing-crab-icon-test")
        }
    }

    func testOperationEditorFitsContentAndPlacesFilePickerBesidePath() throws {
        let templatePath = directory.appendingPathComponent("project.code-workspace").path
        let parameters: [OperationParameters] = [
            .directory(directory.path),
            .template(.init(template: .init(name: "Project", suffix: "code-workspace", importedPath: templatePath)))
        ]
        for code in AppLocalization.supportedLanguages.map(\.code) {
            AppLocalization.languageCode = code
            let store = store(); store.update { $0.languageCode = code }
            var heights: [CGFloat] = []
            for parameter in parameters {
                let editor = OperationEditor(operation: .init(name: "Project", parameters: parameter), existing: false, store: store)
                defer { editor.close() }
                let root = try XCTUnwrap(editor.window?.contentView); root.layoutSubtreeIfNeeded()
                XCTAssertLessThan(root.bounds.width, 580, code)
                XCTAssertLessThan(root.bounds.height, 560, code)
                heights.append(root.bounds.height)
                let views = descendants(root)
                let name = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-name" } as? NSTextField)
                XCTAssertTrue(name.isEditable, code)
                XCTAssertEqual(name.accessibilityLabel(), L("名称"), code)
                XCTAssertFalse(views.compactMap { $0 as? NSTextField }.contains { !$0.isEditable && [L("名称"), L("图标")].contains($0.stringValue) }, code)
                let origin = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-origin" })
                XCTAssertTrue(descendants(origin).compactMap { $0 as? NSTextField }.contains { $0.stringValue == L("自定义") }, code)
                let icon = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-icon" } as? NSButton)
                XCTAssertNotNil(icon.image, code)
                let save = try XCTUnwrap(views.first { $0.identifier?.rawValue == "operation-save" } as? NSButton)
                let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
                XCTAssertLessThanOrEqual(scroll.frame.maxY, save.frame.minY, code)
                XCTAssertTrue(root.bounds.contains(save.frame), code)
                let document = try XCTUnwrap(scroll.documentView)
                for control in document.subviews.compactMap({ $0 as? NSControl }) {
                    XCTAssertGreaterThanOrEqual(control.frame.minX, 0, code)
                    XCTAssertLessThanOrEqual(control.frame.maxX, document.bounds.maxX + 0.5, code)
                    XCTAssertLessThanOrEqual(control.frame.maxY, document.bounds.maxY + 0.5, code)
                }
                let path = parameter.kind == "directory" ? directory.path : templatePath
                let pathField = try XCTUnwrap(document.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.stringValue == path })
                let choose = try XCTUnwrap(document.subviews.compactMap { $0 as? NSButton }.first { $0.title == L("选择…") })
                XCTAssertEqual(pathField.frame.midY, choose.frame.midY, accuracy: 3, code)
                XCTAssertLessThanOrEqual(pathField.frame.maxX, choose.frame.minX, code)
                if parameter.kind == "template" {
                    XCTAssertTrue(document.subviews.compactMap { $0 as? NSTextField }.contains { $0.isEditable && $0.stringValue == "code-workspace" }, code)
                    XCTAssertTrue(document.subviews.compactMap { $0 as? NSButton }.contains { $0.title == L("新建文件后自动打开") }, code)
                    XCTAssertFalse(document.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == L("内置内容") || $0.accessibilityLabel() == L("内置内容") }, code)
                }
            }
            XCTAssertLessThan(heights[0], heights[1], code)
        }
    }

    func testTemplateEditorOnlyShowsInlineContentsWithoutAFileSource() throws {
        let store = store()
        let sources: [FileTemplate] = [
            .init(name: "Inline", suffix: "txt", contents: "Initial text"),
            .init(name: "Imported", suffix: "txt", importedPath: directory.appendingPathComponent("source.txt").path),
            .init(name: "Bundled", suffix: "docx", resourceName: "source.docx")
        ]
        for template in sources {
            let editor = OperationEditor(operation: .init(parameters: .template(.init(template: template))), existing: false, store: store)
            defer { editor.close() }
            let fields = descendants(try XCTUnwrap(editor.window?.contentView)).compactMap { $0 as? NSTextField }
            let contents = fields.first { $0.accessibilityLabel() == L("内置内容") }
            if template.importedPath == nil && template.resourceName == nil {
                let editable = try XCTUnwrap(contents)
                XCTAssertTrue(editable.isEditable)
                XCTAssertEqual(editable.stringValue, "Initial text")
                editable.stringValue = "Edited text"
                editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editable))
                guard case .template(let updated) = editor.draft.parameters else { return XCTFail() }
                XCTAssertEqual(updated.template.contents, "Edited text")
            } else {
                XCTAssertNil(contents)
            }
        }
    }
}

private final class MenuDragFixture: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingSource: Any?
    let draggingDestinationWindow: NSWindow? = nil
    let draggingSourceOperationMask: NSDragOperation = .move
    let draggingLocation = NSPoint.zero
    let draggedImageLocation = NSPoint.zero
    let draggedImage: NSImage? = nil
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    init(source: NSTableView, writer: NSPasteboardWriting) {
        draggingSource = source; super.init(); draggingPasteboard.writeObjects([writer])
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
