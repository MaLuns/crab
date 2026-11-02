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
    private func store() -> ConfigurationStore { ConfigurationStore(directory: directory.appendingPathComponent(UUID().uuidString)) }
    private func op(_ id: String = UUID().uuidString) -> OperationRecord { .init(id: id, parameters: .tool(.init(action: .copyPath))) }

    func testScriptCommandSplitsUnquotedSpacesAndRequiresDoubleQuotedPathsWithSpaces() throws {
        let plain = try ScriptParameters(commandLine: "/tmp/run.sh --mode fast")
        XCTAssertEqual(plain, .init(path: "/tmp/run.sh", arguments: ["--mode", "fast"]))
        let quoted = try ScriptParameters(commandLine: #"  "/tmp/My Scripts/run.sh" --mode fast  "#)
        XCTAssertEqual(quoted, .init(path: "/tmp/My Scripts/run.sh", arguments: ["--mode", "fast"]))
        let unquoted = try ScriptParameters(commandLine: "/tmp/My Scripts/run.sh --mode fast")
        XCTAssertEqual(unquoted, .init(path: "/tmp/My", arguments: ["Scripts/run.sh", "--mode", "fast"]))
        for command in [#"'/tmp/My Scripts/run.sh' --mode fast"#, #"/tmp/My\ Scripts/run.sh --mode fast"#] {
            XCTAssertThrowsError(try ScriptParameters(commandLine: command), command)
        }
    }

    func testScriptCommandPreservesEmptyArgumentsQuotesEscapesAndLiteralShellText() throws {
        let p = try ScriptParameters(commandLine: #"/tmp/run.sh --name "hello world" "" 'single quoted' escaped\ value --flag="x y" "C:\tools\file" "say \"hi\"" "$HOME" "$(touch marker)""#)
        XCTAssertEqual(p.arguments, ["--name", "hello world", "", "single quoted", "escaped value", "--flag=x y", "C:\\tools\\file", "say \"hi\"", "$HOME", "$(touch marker)"])
        for path in ["/tmp/run.sh", "/tmp/中文 路径/script.sh", "/tmp/a\"b'c\\d\nscript.sh"] {
            let original = ScriptParameters(path: path, arguments: p.arguments + ["\t", "\n", "\\", "\"", "`touch marker`", ";", "|", "*", "~"])
            XCTAssertEqual(try ScriptParameters(commandLine: original.commandLine), original)
            XCTAssertEqual(try JSONDecoder().decode(ScriptParameters.self, from: JSONEncoder().encode(original)), original)
        }
        for invalid in ["", "   ", "\"\" --mode fast", "/tmp/run.sh \"unfinished", "/tmp/run.sh 'unfinished", "/tmp/run.sh trailing\\", "/tmp/run.sh bad\0value"] {
            XCTAssertThrowsError(try ScriptParameters(commandLine: invalid), invalid)
        }
    }

    func testScriptParametersRequirePathAndArgumentsObjectAndPersistSeparately() throws {
        let path = directory.appendingPathComponent("original \"quoted\" --mode fast.sh")
        try Data("#!/bin/sh\n".utf8).write(to: path)
        for unsupported in [JSONValue.string(path.path), .object(["path": .string(path.path)])] {
            let data = try JSONEncoder().encode(unsupported)
            XCTAssertThrowsError(try JSONDecoder().decode(ScriptParameters.self, from: data))
            let operation = JSONValue.object(["type": .string("script"), "value": unsupported])
            let decoded = try JSONDecoder().decode(OperationParameters.self, from: JSONEncoder().encode(operation))
            XCTAssertEqual(decoded, .unknown("script", unsupported))
            let record = OperationRecord(parameters: decoded)
            XCTAssertFalse(OperationResolver.canExecute(record, context: .init(urls: [], directory: directory), configuration: AppConfiguration(), allowFileRead: true))
        }
        let noArguments = ScriptParameters(path: path.path)
        XCTAssertEqual(try JSONDecoder().decode(ScriptParameters.self, from: JSONEncoder().encode(noArguments)), noArguments)
        let parameters = ScriptParameters(path: path.path, arguments: ["--mode", "fast", "", "hello world"])
        let storeDirectory = directory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(directory: storeDirectory)
        XCTAssertTrue(store.update { $0.operations = [.init(id: "script", parameters: .script(parameters))]; $0.menu = [.reference("script")] })
        let reloaded = ConfigurationStore(directory: storeDirectory)
        XCTAssertEqual(reloaded.configuration.operations.first?.parameters, .script(parameters))
        XCTAssertEqual(reloaded.configuration.menu, store.configuration.menu)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(OperationParameters.script(parameters))) as? [String: Any]
        let value = try XCTUnwrap(encoded?["value"] as? [String: Any])
        XCTAssertEqual(value["path"] as? String, path.path)
        XCTAssertEqual(value["arguments"] as? [String], parameters.arguments)
        let preview = ConfigurationStore.prepare(reloaded.configuration).previews["script"]
        XCTAssertEqual(preview?.available, true)
        XCTAssertEqual(preview?.scriptLanguageID, ScriptLanguage.shell.rawValue)
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
    func testPlannerFiltersInvalidReferencesWithoutChangingSavedMenu() throws {
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
        let store = store(); var calls: [CustomScript] = []
        store.update { $0.operations = [.init(id: "script", parameters: .script(.init(path: first.path)))] }
        let router = ActionRouter(store: store, launchScript: { script, _, _, _ in DispatchQueue.main.async { calls.append(script) } })
        let request = ActionRequest(operationID: "script", paths: [], targetDirectory: directory.path)
        let decoded = try ActionRequest.decode(request.encodedURL())
        store.update { $0.operations[0].parameters = .script(.init(path: second.path, arguments: ["--mode", "fast", "hello world"])) }
        router.execute(decoded)
        let deadline = Date().addingTimeInterval(2)
        while calls.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(calls.map(\.path), [second.path])
        XCTAssertEqual(calls.first?.arguments, ["--mode", "fast", "hello world"])
        store.update { $0.operations[0].enabled = false }; router.execute(decoded)
        store.update { $0.removeOperations(["script"]) }; router.execute(decoded)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05)); XCTAssertEqual(calls.count, 1)
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
        XCTAssertEqual(Array(store.configuration.operations.suffix(2)).map(\.parameters), [.script(.init(path: one.path)), .script(.init(path: two.path))])
        let dirs = try OperationFileImport.prepare(kind: "directory", urls: [directory], store: store)
        try dirs.commit(to: store)
        let transfers = try OperationFileImport.prepare(kind: "transfer", urls: [directory], store: store)
        try transfers.commit(to: store)
        XCTAssertEqual(store.configuration.operations.last?.parameters, .transfer(.init(target: directory.path)))
        XCTAssertEqual(try String(contentsOf: one), "one"); XCTAssertEqual(try String(contentsOf: two), "two")
        XCTAssertTrue(store.configuration.menu.isEmpty)
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

    func testResetMenuIconInheritsLibraryArtworkIncludingScriptsAndApplicationPreviews() throws {
        let records: [OperationRecord] = [
            .init(iconID: "crab.star", parameters: .directory(directory.path)),
            .init(iconID: "crab.heart", parameters: .script(.init(path: directory.appendingPathComponent("sample.sh").path))),
            .init(parameters: .application(.init(path: directory.appendingPathComponent("Missing.app").path))),
            .init(iconID: MenuNodeIcons.hiddenID, parameters: .script(.init(path: directory.appendingPathComponent("hidden.sh").path)))
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
        for node in nodes {
            XCTAssertTrue(store.update { $0.updateMenuNode(node.id) { $0.iconID = nil } })
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
            operation.parameters = .script(.init(path: "/missing-crab-script.sh")); operation.iconID = "category.scripts"
            XCTAssertNotNil(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
            XCTAssertNotNil(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: false))
            XCTAssertNotNil(MenuNodeIcons.image(node: explicit, operation: operation, configuration: configuration, allowFileRead: false))
            operation.parameters = .directory("/missing-crab-icon-test")
        }
    }
}
