import XCTest
import AppKit
import CryptoKit
@testable import Crab

final class ToolMenuIconTests: XCTestCase {
    private let operations: [ToolAction] = [
        .fileInfo, .desktopLink, .airDrop, .copyName, .newFolderByName,
        .cut, .dissolveFolder, .copyPath, .makeWritable, .hide, .unhide,
        .showHidden, .hideHidden, .toggleExtension, .repairFilename,
        .paste, .trash, .deletePermanently, .wallpaper, .addCommon
    ]

    func testEveryToolAndApplicationFallbackHasValidMonochromeSymbolArtwork() throws {
        XCTAssertEqual(Set(operations), Set(ToolAction.allCases.filter { $0.category == "文件（夹）操作" }))
        for action in ToolAction.allCases {
            let image = try XCTUnwrap(ToolMenuIcon.image(for: action), action.rawValue)
            XCTAssertTrue(image.isValid, action.rawValue)
            XCTAssertTrue(image.isTemplate, action.rawValue)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertEqual(max(image.size.width, image.size.height), 18, accuracy: 0.001)
            XCTAssertEqual(image.accessibilityDescription, action.title)
        }
        for size in [CGFloat.zero, -.infinity, .infinity, .nan, 2049] {
            XCTAssertNil(ToolMenuIcon.image(for: .copyPath, size: size))
            XCTAssertNil(ToolMenuIcon.applicationFallback(size: size))
        }
    }

    func testRegularSymbolsAreCopiedAndSizedWithoutChangingTheirSharedSources() throws {
        let sources: [(ToolAction, NSImage)] = [
            (.fileInfo, try XCTUnwrap(NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil))),
            (.makeWritable, try XCTUnwrap(NSImage(systemSymbolName: "lock.open", accessibilityDescription: nil))),
            (.trash, try XCTUnwrap(NSImage(systemSymbolName: "trash", accessibilityDescription: nil))),
            (.airDrop, try XCTUnwrap(NSImage(systemSymbolName: "airdrop", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil))),
            (.png, try XCTUnwrap(NSImage(systemSymbolName: "photo", accessibilityDescription: nil))),
            (.zip, try XCTUnwrap(NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)))
        ]
        for (action, source) in sources {
            let originalSize = source.size, originalTemplate = source.isTemplate
            let small = try XCTUnwrap(ToolMenuIcon.image(for: action, size: 14))
            let large = try XCTUnwrap(ToolMenuIcon.image(for: action, size: 28))
            XCTAssertFalse(small === source)
            XCTAssertFalse(small === large)
            XCTAssertEqual(source.size, originalSize, "Do not resize AppKit's shared source for \(action).")
            XCTAssertEqual(source.isTemplate, originalTemplate)
            XCTAssertTrue(small.isTemplate)
            XCTAssertTrue(large.isTemplate)
            XCTAssertEqual(try pixels(small), try pixels(regularSymbol(source, size: 14)), action.rawValue)
            XCTAssertEqual(try pixels(large), try pixels(regularSymbol(source, size: 28)), action.rawValue)
            XCTAssertEqual(max(small.size.width, small.size.height), 14, accuracy: 0.001)
            XCTAssertEqual(max(large.size.width, large.size.height), 28, accuracy: 0.001)
        }
    }

    func testDifferentOperationsHaveDifferentVisibleArtworkInsteadOfOneCopyPlaceholder() throws {
        var hashes: [ToolAction: String] = [:]
        for action in operations {
            let image = try XCTUnwrap(ToolMenuIcon.image(for: action, size: 32))
            let menu = NSMenu()
            let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
            item.image = image; menu.addItem(item)
            FinderMenuPresentation.prepare(menu, appearance: try XCTUnwrap(NSAppearance(named: .darkAqua)))
            let output = try XCTUnwrap(item.image)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            output.draw(in: NSRect(x: (40 - output.size.width) / 2, y: (40 - output.size.height) / 2,
                                   width: output.size.width, height: output.size.height))
            context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
            let bytes = Data(bytes: try XCTUnwrap(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            hashes[action] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            XCTAssertTrue(bytes.contains { $0 != 0 }, "Artwork must actually render for \(action).")
        }
        XCTAssertGreaterThanOrEqual(Set(hashes.values).count, 18, "File operations must not share one placeholder.")
        let pairs: [(ToolAction, ToolAction)] = [(.cut, .paste), (.copyName, .copyPath), (.newFolderByName, .dissolveFolder),
                                                (.hide, .unhide), (.showHidden, .hideHidden), (.trash, .deletePermanently)]
        for (first, second) in pairs {
            XCTAssertNotEqual(hashes[first], hashes[second], "\(first) and \(second) need different semantic artwork.")
        }
    }

    func testToolSymbolsRemainMonochromeAndGainContrastInBothFinderAppearances() throws {
        for action in [ToolAction.fileInfo, .trash, .airDrop, .png, .icns, .macIconset, .iosIconset,
                       .zip, .sevenZip, .unzip, .terminal, .vscode] {
            let source = try XCTUnwrap(ToolMenuIcon.image(for: action, size: 32))
            XCTAssertTrue(source.isTemplate)
            var luminances: [CGFloat] = []
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let menu = NSMenu()
                let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                item.image = source; menu.addItem(item)
                FinderMenuPresentation.prepare(menu, appearance: try XCTUnwrap(NSAppearance(named: appearance)))
                let rendered = try XCTUnwrap(item.image)
                XCTAssertFalse(rendered.isTemplate)
                XCTAssertTrue(source.isTemplate, "Finder must not mutate the symbol shared with settings.")
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(rendered.tiffRepresentation)))
                var values: [CGFloat] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5 else { continue }
                        XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.02, action.rawValue)
                        XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.02, action.rawValue)
                        values.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
                    }
                }
                XCTAssertGreaterThan(values.count, 10, action.rawValue)
                luminances.append(values.reduce(0, +) / CGFloat(max(values.count, 1)))
            }
            XCTAssertLessThan(luminances[0], 0.25, action.rawValue)
            XCTAssertGreaterThan(luminances[1], 0.75, action.rawValue)
        }
    }

    func testNonTemplateApplicationArtworkRemainsUntouchedBesideToolSymbols() throws {
        let source = try XCTUnwrap(NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path).copy() as? NSImage)
        source.size = NSSize(width: 18, height: 18)
        XCTAssertFalse(source.isTemplate)
        let original = try pixels(source)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let menu = NSMenu()
            let application = NSMenuItem(title: "Actual application", action: nil, keyEquivalent: "")
            application.image = source; menu.addItem(application)
            let tool = NSMenuItem(title: "Tool", action: nil, keyEquivalent: "")
            tool.image = ToolMenuIcon.image(for: .fileInfo); menu.addItem(tool)
            FinderMenuPresentation.prepare(menu, appearance: try XCTUnwrap(NSAppearance(named: appearance)))
            XCTAssertTrue(application.image === source)
            XCTAssertFalse(source.isTemplate)
            XCTAssertEqual(source.size, NSSize(width: 18, height: 18))
            XCTAssertEqual(try pixels(source), original)
        }
    }

    func testCustomApplicationFallbackUsesTheSameSymbolFamilyAndIndependentCopies() throws {
        let first = try XCTUnwrap(ToolMenuIcon.applicationFallback(size: 14))
        let second = try XCTUnwrap(ToolMenuIcon.applicationFallback(size: 28))
        XCTAssertFalse(first === second)
        for image in [first, second] {
            XCTAssertTrue(image.isTemplate)
            XCTAssertTrue(image.isValid)
        }
        XCTAssertEqual(max(first.size.width, first.size.height), 14, accuracy: 0.001)
        XCTAssertEqual(max(second.size.width, second.size.height), 28, accuracy: 0.001)
        let source = try XCTUnwrap(NSImage(systemSymbolName: "app", accessibilityDescription: nil))
        XCTAssertEqual(try pixels(first), try pixels(regularSymbol(source, size: 14)))
        XCTAssertEqual(try pixels(second), try pixels(regularSymbol(source, size: 28)))
    }

    func testOnlyToolCategoryParentsUseTheSharedCategoryArtwork() throws {
        for (category, role) in [("文件（夹）操作", CategoryIcon.tools), ("图片转换", .images), ("进入 App", .applications), ("压缩与解压", .archives)] {
            let image = try XCTUnwrap(ToolMenuIcon.categoryImage(for: category, size: 22), category)
            XCTAssertTrue(image.isTemplate)
            XCTAssertTrue(image.isValid)
            let source = try XCTUnwrap(role.image(size: 22))
            XCTAssertEqual(try pixels(image), try pixels(source), category)
            XCTAssertEqual(max(image.size.width, image.size.height), 22, accuracy: 0.001)
            XCTAssertNil(ToolMenuIcon.categoryImage(for: category, size: 0))
        }
        for category in ["新建文件", "复制到", "移动到", "常用目录", "自定义图标", "unknown"] {
            XCTAssertNil(ToolMenuIcon.categoryImage(for: category), category)
        }
    }

    private func regularSymbol(_ source: NSImage, size: CGFloat) throws -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(.preferringMonochrome())
        let configured = try XCTUnwrap(source.withSymbolConfiguration(configuration))
        let image = try XCTUnwrap(configured.copy() as? NSImage)
        let scale = size / max(image.size.width, image.size.height)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.isTemplate = true
        return image
    }

    private func pixels(_ image: NSImage) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 40, height: 40))
        image.draw(in: NSRect(x: (40 - image.size.width) / 2, y: (40 - image.size.height) / 2,
                             width: image.size.width, height: image.size.height))
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: try XCTUnwrap(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}
