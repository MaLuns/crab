import AppKit
import XCTest
@testable import Crab

@MainActor
final class MenuNodeIconStyleTests: XCTestCase {
    private var directory: URL!
    private var originalLanguage = ""

    override func setUpWithError() throws {
        originalLanguage = AppLocalization.languageCode
        AppLocalization.languageCode = "zh-Hans"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-AppIcon-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        AppLocalization.languageCode = originalLanguage
        try? FileManager.default.removeItem(at: directory)
    }

    private func unavailableApplication() -> OperationRecord {
        OperationRecord(id: "builtin.app.vscode", parameters: .application(.init(catalogID: "vscode", path: directory.appendingPathComponent("Missing.app").path)))
    }

    private func applicationConfiguration(_ operation: OperationRecord) -> AppConfiguration {
        var configuration = AppConfiguration()
        configuration.operations = [operation]
        configuration.menu = [MenuNode(kind: .group, defaultNameKey: "由 APP 打开", iconID: "category.applications", children: [.reference(operation.id)])]
        configuration.languageCode = "zh-Hans"
        return configuration
    }

    func testAllExistingCategoryArtworkIsSelectableWithItsSemanticPaletteInBothAppearances() throws {
        let categoryIDs = CategoryIcon.allCases.map { "category." + $0.rawValue }
        XCTAssertEqual(Array(MenuNodeIcons.catalog.prefix(categoryIDs.count).map(\.id)), categoryIDs)
        XCTAssertEqual(Set(MenuNodeIcons.catalog.map(\.id)).count, MenuNodeIcons.catalog.count)
        let applicationAppearance = NSApp.appearance
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for category in CategoryIcon.allCases {
                for style in AppIconStyle.allCases {
                    var image: NSImage?
                    appearance.performAsCurrentDrawingAppearance {
                        image = MenuNodeIcons.catalogImage("category." + category.rawValue, style: style, size: 24)
                    }
                    let rendered = try XCTUnwrap(image)
                    XCTAssertEqual(rendered.isTemplate, style == .monochrome)
                    XCTAssertEqual(rendered.size, NSSize(width: 24, height: 24))
                    let expected = try XCTUnwrap(category.image(style: style, size: 24))
                    XCTAssertEqual(MenuIconPreview.pngData(from: rendered), MenuIconPreview.pngData(from: expected))
                }
            }
        }
        let general = try XCTUnwrap(MenuNodeIcons.catalogImage("category.general", style: .color))
        let tools = try XCTUnwrap(MenuNodeIcons.catalogImage("category.tools", style: .color))
        let generalPixels = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(MenuIconPreview.pngData(from: general))))
        let toolsPixels = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(MenuIconPreview.pngData(from: tools))))
        let generalTile = try XCTUnwrap(generalPixels.colorAt(x: 6, y: 32)?.usingColorSpace(.sRGB))
        let toolsTile = try XCTUnwrap(toolsPixels.colorAt(x: 6, y: 32)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(generalTile.alphaComponent, 0.9)
        XCTAssertGreaterThan(toolsTile.alphaComponent, 0.9)
        XCTAssertGreaterThan(abs(generalTile.redComponent - toolsTile.redComponent), 0.2)
        XCTAssertTrue(NSApp.appearance === applicationAppearance)
    }

    func testSameSelectedCatalogIDsFollowBothStylesInRootAndNestedMenus() throws {
        let operation = OperationRecord(id: "style-operation", parameters: .tool(.init(action: .copyPath)))
        var chosen = MenuNode.reference(operation.id); chosen.iconID = "category.tools"
        var hidden = MenuNode.reference(operation.id); hidden.iconID = MenuNodeIcons.hiddenID
        var native = MenuNode.reference(operation.id); native.iconID = "system.icon.folder"
        var legacy = MenuNode.reference(operation.id); legacy.iconID = "crab.star"
        var child = MenuNode.reference(operation.id); child.iconID = "category.common"
        let group = MenuNode(kind: .group, name: "Group", iconID: "category.newFile", children: [child])
        var configuration = AppConfiguration()
        configuration.operations = [operation]
        configuration.menu = [chosen, hidden, native, group, legacy]
        let savedNodes = configuration.menu
        let directory = FileManager.default.temporaryDirectory
        var nativeImages: [Data] = []
        var chosenImages: [Data] = []

        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            let menu = ContextMenuBuilder(configuration: configuration, handler: { _ in })
                .menu(selectedURLs: [directory.appendingPathComponent("sample.txt")], directory: directory)
            XCTAssertEqual(menu.items.count, 5)
            let chosenImage = try XCTUnwrap(menu.items[0].image)
            let groupImage = try XCTUnwrap(menu.items[3].image)
            let childImage = try XCTUnwrap(menu.items[3].submenu?.items.first?.image)
            for image in [chosenImage, groupImage, childImage, try XCTUnwrap(menu.items[4].image)] {
                XCTAssertEqual(image.isTemplate, style == .monochrome)
            }
            XCTAssertNil(menu.items[1].image)
            let nativeImage = try XCTUnwrap(menu.items[2].image)
            XCTAssertFalse(nativeImage.isTemplate)
            nativeImages.append(try XCTUnwrap(MenuIconPreview.pngData(from: nativeImage)))
            chosenImages.append(try XCTUnwrap(MenuIconPreview.pngData(from: chosenImage)))
            XCTAssertEqual(configuration.menu, savedNodes)
            XCTAssertEqual(configuration.operations, [operation])
            let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
            XCTAssertEqual(decoded.menu, savedNodes)
            XCTAssertEqual(decoded.iconStyle, style)
        }
        XCTAssertEqual(nativeImages[0], nativeImages[1])
        XCTAssertNotEqual(chosenImages[0], chosenImages[1])
    }

    func testDefaultUserArtworkKeepsItsColorsThroughBothStylesAndTransportPreviews() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<8 {
            for x in 0..<8 { bitmap.setColor(x < 4 ? .red : .green, atX: x, y: y) }
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let operation = OperationRecord(id: "transported-image", parameters: .image(.init(path: "/unused-test-preview.png")))
        let node = MenuNode.reference(operation.id)
        var configuration = AppConfiguration()
        configuration.operations = [operation]
        configuration.menu = [node]
        configuration.previews[operation.id] = OperationPreview(data: png)
        let original = configuration
        var renderedImages: [Data] = []

        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            let image = try XCTUnwrap(MenuNodeIcons.image(node: node, operation: operation,
                configuration: configuration, allowFileRead: false))
            XCTAssertFalse(image.isTemplate)
            renderedImages.append(try XCTUnwrap(MenuIconPreview.pngData(from: image)))
            XCTAssertEqual(configuration.menu, original.menu)
            XCTAssertEqual(configuration.operations, original.operations)
            XCTAssertEqual(configuration.previews, original.previews)
        }
        XCTAssertEqual(renderedImages[0], renderedImages[1])
    }

    func testUnavailableApplicationUsesSamePlaceholderLocallyAndAfterTransportWithoutBecomingExecutable() throws {
        let operation = unavailableApplication()
        let configuration = applicationConfiguration(operation)
        let prepared = ConfigurationStore.prepare(configuration)
        XCTAssertNil(OperationImages.source(operation), "Placeholder artwork must not become a native-logo preview.")
        XCTAssertNil(prepared.previews[operation.id]?.data)
        XCTAssertEqual(prepared.previews[operation.id]?.available, false)
        XCTAssertNotNil(prepared.previews[operation.id]?.reason)
        XCTAssertEqual(prepared.operations, configuration.operations)
        XCTAssertEqual(prepared.menu, configuration.menu)
        let transported = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(prepared))
        let context = OperationContext(urls: [], directory: directory)
        var colorAndMonochrome: [Data] = []
        for style in AppIconStyle.allCases {
            var styled = transported; styled.iconStyle = style
            let snapshot = styled
            let expected = try XCTUnwrap(ApplicationIcon.unavailableImage(style: style))
            for allowFileRead in [true, false] {
                let node = try XCTUnwrap(styled.menu.first?.children.first)
                let actual = try XCTUnwrap(MenuNodeIcons.image(node: node, operation: operation, configuration: styled, allowFileRead: allowFileRead))
                XCTAssertEqual(actual.isTemplate, style == .monochrome)
                XCTAssertEqual(actual.size, NSSize(width: 18, height: 18))
                XCTAssertEqual(MenuIconPreview.pngData(from: actual), MenuIconPreview.pngData(from: expected))
                XCTAssertFalse(OperationResolver.canExecute(operation, context: context, configuration: styled, allowFileRead: allowFileRead))
                XCTAssertTrue(MenuPlanner.items(configuration: styled, context: context, allowFileRead: allowFileRead).isEmpty)
            }
            XCTAssertTrue(ContextMenuBuilder(configuration: styled, handler: { _ in }).menu(selectedURLs: [], directory: directory).items.isEmpty)
            XCTAssertEqual(styled, snapshot)
            colorAndMonochrome.append(try XCTUnwrap(MenuIconPreview.pngData(from: expected)))
        }
        XCTAssertNotEqual(colorAndMonochrome[0], colorAndMonochrome[1])
        var asynchronous: AppConfiguration?
        ConfigurationStore.prepareAsync(configuration) { asynchronous = $0 }
        let deadline = Date().addingTimeInterval(3)
        while asynchronous == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(try XCTUnwrap(asynchronous).previews, prepared.previews)
    }

    func testUnavailablePlaceholderRequiresKnownUnavailableStatusWhenFileReadsAreDisabled() throws {
        let operation = unavailableApplication()
        var configuration = applicationConfiguration(operation)
        XCTAssertNil(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
        configuration.previews[operation.id] = OperationPreview(available: true)
        XCTAssertNil(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
        configuration.previews[operation.id] = OperationPreview(available: false, reason: "应用不可用")
        XCTAssertNotNil(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
    }

    func testApplicationNativeArtworkKeepsColorLocallyAndWhenUnavailableStatusIncludesALogo() throws {
        let app = directory.appendingPathComponent("Installed.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "dev.crab.icon-fixture", "CFBundleExecutable": "fixture"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/fixture")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let operation = OperationRecord(parameters: .application(.init(path: app.path)))
        var configuration = applicationConfiguration(operation)
        let native = try XCTUnwrap(OperationImages.source(operation))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<8 { for x in 0..<8 { bitmap.setColor(x < 4 ? .red : .green, atX: x, y: y) } }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let preview = try XCTUnwrap(NSImage(data: png))
        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            let local = try XCTUnwrap(OperationImages.image(operation, configuration: configuration, allowFileRead: true))
            XCTAssertFalse(local.isTemplate)
            XCTAssertEqual(MenuIconPreview.pngData(from: local), MenuIconPreview.pngData(from: native))
            for available in [true, false] {
                configuration.previews[operation.id] = OperationPreview(data: png, available: available)
                let transferred = try XCTUnwrap(OperationImages.image(operation, configuration: configuration, allowFileRead: false))
                XCTAssertFalse(transferred.isTemplate)
                XCTAssertEqual(MenuIconPreview.pngData(from: transferred), MenuIconPreview.pngData(from: preview))
            }
        }
    }

    func testUnavailableApplicationPlaceholderRespectsOperationAndMenuIconOverrides() throws {
        var operation = unavailableApplication()
        var configuration = ConfigurationStore.prepare(applicationConfiguration(operation))
        let inherited = MenuNode.reference(operation.id)
        var selected = inherited; selected.iconID = "category.common"
        var hidden = inherited; hidden.iconID = MenuNodeIcons.hiddenID
        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            for allowFileRead in [true, false] {
                operation.iconID = "category.tools"
                let operationImage = try XCTUnwrap(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: allowFileRead))
                XCTAssertEqual(MenuIconPreview.pngData(from: operationImage), MenuNodeIcons.catalogImage("category.tools", style: style).flatMap { MenuIconPreview.pngData(from: $0) })
                operation.iconID = MenuNodeIcons.hiddenID
                XCTAssertNil(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: allowFileRead))
                let selectedImage = try XCTUnwrap(MenuNodeIcons.image(node: selected, operation: operation, configuration: configuration, allowFileRead: allowFileRead))
                XCTAssertEqual(MenuIconPreview.pngData(from: selectedImage), MenuNodeIcons.catalogImage("category.common", style: style).flatMap { MenuIconPreview.pngData(from: $0) })
                operation.iconID = nil
                XCTAssertNil(MenuNodeIcons.image(node: hidden, operation: operation, configuration: configuration, allowFileRead: allowFileRead))
                XCTAssertNotNil(MenuNodeIcons.image(node: inherited, operation: operation, configuration: configuration, allowFileRead: allowFileRead))
            }
        }
    }

    func testOptionalUnavailableApplicationIconAndSettingsPreviews() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["CRAB_UNAVAILABLE_APP_PREVIEW_DIR"] ?? environment["TEST_RUNNER_CRAB_UNAVAILABLE_APP_PREVIEW_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let operation = unavailableApplication()
        for style in AppIconStyle.allCases {
            for size in [18, 32, 96] {
                let image = try XCTUnwrap(ApplicationIcon.unavailableImage(style: style, size: CGFloat(size)))
                XCTAssertEqual(image.size, NSSize(width: CGFloat(size), height: CGFloat(size)))
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size * 2, pixelsHigh: size * 2,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = image.size
                let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                image.draw(in: NSRect(origin: .zero, size: image.size))
                context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("placeholder-" + style.rawValue + "-" + String(size) + "pt@2x.png"))
            }
            let store = ConfigurationStore(directory: directory.appendingPathComponent(style.rawValue))
            var configuration = applicationConfiguration(operation); configuration.iconStyle = style; configuration.windowTheme = .light
            XCTAssertTrue(store.replace(configuration))
            let scene = SettingsWindowController(store: store)
            defer { scene.window?.close() }
            for page in [SettingsPage.library, .menu] {
                scene.selectPage(page.rawValue)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                let root = try XCTUnwrap(scene.window?.contentView)
                root.layoutSubtreeIfNeeded()
                func invalidate(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(invalidate) }
                invalidate(root)
                let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(style.rawValue + "-" + page.rawValue + ".png"))
            }
        }
    }
}
