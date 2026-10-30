import AppKit
import Darwin
import XCTest
@testable import Crab

@MainActor
final class ScriptLanguageIconTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-ScriptIcons-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func script(_ name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private func png(_ image: NSImage?, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        try XCTUnwrap(MenuIconPreview.pngData(from: XCTUnwrap(image, file: file, line: line)), file: file, line: line)
    }

    func testCommonSuffixesIdentifyAllTenLanguagesWithoutInstalledInterpreters() throws {
        let cases: [(ScriptLanguage, [String])] = [
            (.shell, ["sh", "bash", "zsh"]), (.python, ["py"]),
            (.javascript, ["js", "mjs", "cjs"]), (.typescript, ["ts", "tsx"]),
            (.ruby, ["rb"]), (.perl, ["pl"]), (.php, ["php"]),
            (.lua, ["lua"]), (.swift, ["swift"]), (.applescript, ["applescript"])
        ]
        XCTAssertEqual(Set(cases.map { $0.0 }), Set(ScriptLanguage.allCases))
        for (language, suffixes) in cases {
            XCTAssertFalse(language.title.isEmpty)
            for suffix in suffixes {
                let url = try script("sample." + suffix.uppercased(), contents: "sample body\n")
                XCTAssertEqual(ScriptLanguage.detect(at: url.path), language, suffix)
                XCTAssertEqual(ScriptLanguage.detect(path: url.path, header: Data("sample body\n".utf8)), language, suffix)
            }
        }
        let missingRuntime = directory.appendingPathComponent("missing-runtime/python3.12")
        let uninstalled = try script("uninstalled.data", contents: "#!" + missingRuntime.path + "\nprint('sample')\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingRuntime.path))
        XCTAssertEqual(ScriptLanguage.detect(at: uninstalled.path), .python)
    }

    func testShebangWinsOverSuffixAndRecognizesEnvVersionedRuntimesAndCRLFBinaryBodies() throws {
        let cases: [(String, ScriptLanguage)] = [
            ("#!/bin/zsh", .shell), ("#!/usr/bin/env python3.12 -u", .python),
            ("#!/usr/bin/env -S node --input-type=module", .javascript),
            ("#!/usr/bin/env -S ts-node --transpile-only", .typescript),
            ("#!/usr/local/bin/ruby3.2", .ruby), ("#!/usr/bin/env perl", .perl),
            ("#!/usr/local/bin/php8.3", .php), ("#!/usr/bin/env lua5.4", .lua),
            ("#!/usr/bin/swift", .swift), ("#!/usr/bin/osascript", .applescript)
        ]
        for (header, expected) in cases {
            var data = Data((header + "\r\n").utf8)
            data.append(contentsOf: [0xff, 0xfe, 0x00])
            XCTAssertEqual(ScriptLanguage.detect(path: "/unused/conflicting.py", header: data), expected, header)
        }
        let conflict = try script("conflict.py", contents: "#!/bin/sh -e -u\nexit 0\n")
        XCTAssertEqual(ScriptLanguage.detect(at: conflict.path), .shell)
    }

    func testUnknownInvalidAndOversizedShebangsUseDefaultInsteadOfSuffixGuessing() {
        let headers = [
            "#!\n", "#!relative-python\n", "#!/usr/bin/unknown-runtime\n",
            "#!/usr/bin/env -i python3\n", "#!/usr/bin/env PATH=/bin python3\n",
            "#!/usr/bin/env -S\n", "#!/usr/bin/env -S 'python3' -u\n",
            "#!/usr/bin/env -S ./python3 -u\n", "#!/usr/bin/env $RUNTIME\n",
            "#!/usr/bin/python3\0\n", "#!/usr/bin/" + String(repeating: "x", count: 4096) + "\n"
        ]
        for header in headers {
            XCTAssertNil(ScriptLanguage.detect(path: "/unused/looks-like-python.py", header: Data(header.utf8)), header.prefix(80).description)
        }
        XCTAssertNil(ScriptLanguage.detect(path: "/unused/no-suffix", header: Data("sample".utf8)))
        XCTAssertNil(ScriptLanguage.detect(path: "/unused/sample.unknown", header: Data()))
    }

    func testDetectionReadsOnlyRegularFilesAndDoesNotScanBodyForInterpreterNames() throws {
        XCTAssertNil(ScriptLanguage.detect(at: directory.path))
        XCTAssertNil(ScriptLanguage.detect(at: directory.appendingPathComponent("missing.py").path))
        let fifo = directory.appendingPathComponent("pipe.py")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(ScriptLanguage.detect(at: fifo.path), "Reject named pipes without waiting for a writer.")
        let body = try script("body-only.unknown", contents: "ordinary first line\n#!/usr/bin/python3\n")
        XCTAssertNil(ScriptLanguage.detect(at: body.path))
        let bounded = try script("bounded.py", contents: String(repeating: "x", count: 8192) + "\n")
        XCTAssertEqual(ScriptLanguage.detect(at: bounded.path), .python)
    }

    func testAutomaticDefaultsPreserveHiddenAndExplicitLibraryAndMenuIconChoices() throws {
        let url = try script("sample.py", contents: "print('sample')\n")
        var operation = OperationRecord(parameters: .script(url.path))
        var configuration = AppConfiguration(); configuration.operations = [operation]; configuration.menu = []
        for id in [nil, "category.scripts"] as [String?] {
            operation.iconID = id
            XCTAssertTrue(ScriptLanguageIcon.isAutomatic(operation))
            for style in AppIconStyle.allCases {
                configuration.iconStyle = style
                let expected = try png(ScriptLanguageIcon.image(language: .python, style: style))
                XCTAssertEqual(try png(OperationImages.image(operation, configuration: configuration)), expected)
                XCTAssertEqual(try png(OperationImages.image(operation, configuration: configuration, allowFileRead: false)),
                               try png(CategoryIcon.scripts.image(style: style)), "Missing preview metadata must not trigger a file read.")
            }
        }
        operation.iconID = "crab.star"
        XCTAssertFalse(ScriptLanguageIcon.isAutomatic(operation))
        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            XCTAssertEqual(try png(OperationImages.image(operation, configuration: configuration)),
                           try png(MenuNodeIcons.catalogImage("crab.star", style: style)))
        }
        operation.iconID = MenuNodeIcons.hiddenID
        XCTAssertFalse(ScriptLanguageIcon.isAutomatic(operation))
        XCTAssertNil(OperationImages.image(operation, configuration: configuration))
        operation.iconID = nil
        var explicit = MenuNode.reference(operation.id); explicit.iconID = "crab.heart"
        XCTAssertEqual(try png(MenuNodeIcons.image(node: explicit, operation: operation, configuration: configuration)),
                       try png(MenuNodeIcons.catalogImage("crab.heart", style: configuration.iconStyle)))
        explicit.iconID = MenuNodeIcons.hiddenID
        XCTAssertNil(MenuNodeIcons.image(node: explicit, operation: operation, configuration: configuration))
        XCTAssertFalse(ScriptLanguageIcon.isAutomatic(OperationRecord(parameters: .directory(directory.path))))
    }

    func testPreviewPreparationAgreesAcrossSyncAndAsyncAndNeverPersistsMetadataInMaster() throws {
        let python = try script("python.py", contents: "print('sample')\n")
        let shell = try script("shell.py", contents: "#!/bin/sh\nexit 0\n")
        let unknown = try script("unknown.data", contents: "unrecognized\n")
        var configuration = AppConfiguration()
        configuration.operations = [python, shell, unknown].map { .init(iconID: "category.scripts", parameters: .script($0.path)) }
        configuration.menu = configuration.operations.map { .reference($0.id) }
        let prepared = ConfigurationStore.prepare(configuration)
        let expected: [ScriptLanguage?] = [.python, .shell, nil]
        for (operation, language) in zip(configuration.operations, expected) {
            XCTAssertEqual(prepared.previews[operation.id]?.scriptLanguageID, language?.rawValue)
        }
        var asynchronous: AppConfiguration?
        ConfigurationStore.prepareAsync(configuration) { asynchronous = $0 }
        let deadline = Date().addingTimeInterval(5)
        while asynchronous == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(try XCTUnwrap(asynchronous).previews, prepared.previews)
        XCTAssertEqual(prepared.operations, configuration.operations)
        XCTAssertEqual(prepared.menu, configuration.menu)
        let storage = directory.appendingPathComponent("configuration", isDirectory: true)
        let store = ConfigurationStore(directory: storage)
        XCTAssertTrue(store.replace(prepared))
        let persisted = try Data(contentsOf: storage.appendingPathComponent("operations-v1.json"))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("scriptLanguageID"))
        XCTAssertTrue(ConfigurationStore(directory: storage).configuration.previews.isEmpty)
    }

    func testTransportedLanguageMetadataRendersAfterSourceRemovalInBothStylesAndInheritsInMenus() throws {
        let url = try script("transport.py", contents: "print('sample')\n")
        let operation = OperationRecord(iconID: "category.scripts", parameters: .script(url.path))
        let inherited = MenuNode.reference(operation.id)
        var explicit = MenuNode.reference(operation.id); explicit.iconID = "crab.star"
        var configuration = AppConfiguration(); configuration.operations = [operation]; configuration.menu = [inherited, explicit]
        let prepared = ConfigurationStore.prepare(configuration)
        var transported = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(prepared))
        XCTAssertEqual(transported.previews[operation.id]?.scriptLanguageID, ScriptLanguage.python.rawValue)
        try FileManager.default.removeItem(at: url)
        for style in AppIconStyle.allCases {
            transported.iconStyle = style
            let snapshot = transported
            let expected = try png(ScriptLanguageIcon.image(language: .python, style: style))
            let cached = try XCTUnwrap(OperationImages.image(operation, configuration: transported, allowFileRead: false))
            XCTAssertEqual(cached.isTemplate, style == .monochrome)
            XCTAssertEqual(try png(cached), expected)
            XCTAssertEqual(try png(MenuNodeIcons.image(node: inherited, operation: operation, configuration: transported, allowFileRead: false)), expected)
            XCTAssertEqual(try png(MenuNodeIcons.image(node: explicit, operation: operation, configuration: transported, allowFileRead: false)),
                           try png(MenuNodeIcons.catalogImage("crab.star", style: style)))
            XCTAssertEqual(transported, snapshot)
        }
    }

    func testBuiltInLanguageArtworkRendersBothStylesAndUnknownLanguageKeepsExistingDefault() throws {
        let unknown = try script("unknown.language", contents: "unrecognized script\n")
        let operation = OperationRecord(iconID: "category.scripts", parameters: .script(unknown.path))
        var configuration = AppConfiguration(); configuration.operations = [operation]; configuration.menu = []
        for style in AppIconStyle.allCases {
            configuration.iconStyle = style
            let fallback = try png(CategoryIcon.scripts.image(style: style))
            XCTAssertEqual(try png(ScriptLanguageIcon.image(language: nil, style: style)), fallback)
            XCTAssertEqual(try png(OperationImages.image(operation, configuration: configuration)), fallback)
            for language in ScriptLanguage.allCases {
                XCTAssertNotNil(CrabSymbol.image(named: language.symbol), language.rawValue)
                let image = try XCTUnwrap(ScriptLanguageIcon.image(language: language, style: style), language.rawValue)
                XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
                XCTAssertEqual(image.isTemplate, style == .monochrome, language.rawValue)
                XCTAssertFalse(try png(image).isEmpty)
            }
        }
        try writePreviewIfRequested()
    }

    private func writePreviewIfRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["CRAB_SCRIPT_ICON_PREVIEW_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let languages: [ScriptLanguage?] = [nil] + ScriptLanguage.allCases.map(Optional.some)
        let columnWidth = 90, rowHeight = 100
        let width = languages.count * columnWidth, height = rowHeight * 2
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        for (row, style) in [AppIconStyle.color, .monochrome].enumerated() {
            for (column, language) in languages.enumerated() {
                let x = CGFloat(column * columnWidth), y = CGFloat((1 - row) * rowHeight)
                let image = try XCTUnwrap(ScriptLanguageIcon.image(language: language, style: style, size: 42))
                image.draw(in: NSRect(x: x + 24, y: y + 35, width: 42, height: 42))
                let label = (language?.title ?? "Default") as NSString
                label.draw(in: NSRect(x: x + 3, y: y + 12, width: CGFloat(columnWidth - 6), height: 18),
                           withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
            }
        }
        context.flushGraphics()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("script-language-icons.png"))
    }
}
