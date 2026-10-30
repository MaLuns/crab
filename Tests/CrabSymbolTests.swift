import AppKit
import XCTest
@testable import Crab

@MainActor
final class CrabSymbolTests: XCTestCase {
    private func bitmap(_ image: NSImage, side: Int = 48) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(_ image: NSImage) throws -> [UInt8] {
        let pixels = try bitmap(image)
        return (0..<pixels.pixelsHigh).flatMap { y in
            (0..<pixels.pixelsWide).map { x in
                UInt8(((pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded())
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testOperationSymbolsResolve() throws {
        for name in OperationRegistry.shared.definitions.map(\.symbol) + SettingsPage.allCases.map { $0.categoryIcon.symbol } {
            XCTAssertNotNil(CrabSymbol.image(named: name), name)
        }
    }
    func testEverySymbolRetainsVectorArtworkVisibleStrokesAndTransparentMargins() throws {
        XCTAssertGreaterThanOrEqual(CrabSymbol.names.count, 125, "Keep the existing saved-name catalog available.")
        XCTAssertEqual(CrabSymbol.names.count, Set(CrabSymbol.names).count)
        for name in CrabSymbol.names {
            let image = try XCTUnwrap(CrabSymbol.image(named: name), name)
            XCTAssertTrue(image.isValid, name)
            XCTAssertTrue(image.isTemplate, name)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18), name)
            let vector = try XCTUnwrap(image.representations.compactMap { $0 as? NSPDFImageRep }.first, name)
            XCTAssertEqual(vector.pageCount, 1, name)
            XCTAssertEqual(vector.bounds.size, NSSize(width: 24, height: 24), name)
            let pixels = try bitmap(image)
            var ink = 0
            for y in 0..<48 {
                for x in 0..<48 {
                    let opacity = pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if opacity > 0.25 { ink += 1 }
                    if x == 0 || y == 0 || x == 47 || y == 47 {
                        XCTAssertLessThan(opacity, 0.01, "\(name) should keep a transparent outer margin.")
                    }
                }
            }
            XCTAssertGreaterThan(ink, 8, "\(name) must render visible artwork.")
            XCTAssertLessThan(ink, 48 * 48 * 2 / 3, "\(name) should retain an open outline.")
        }
    }

    func testUnknownNamesAndInvalidSizesDoNotProducePlaceholderArtwork() {
        for name in ["", "unknown-crab-symbol", "../mouse", "/tmp/mouse", "Mouse", "mouse.pdf"] {
            XCTAssertNil(CrabSymbol.image(named: name), name)
        }
        XCTAssertNil(CrabSymbol.image(forLegacySymbol: "an-old-custom-symbol"))
        for invalid in [CGFloat.zero, -1, .infinity, .nan, 2049] {
            XCTAssertNil(CrabSymbol.image(named: "mouse", size: invalid))
        }
    }

    func testImageCopiesKeepTheirOwnSizeTemplateStateAndDescription() throws {
        let small = try XCTUnwrap(CrabSymbol.image(named: "mouse", size: 16, template: true))
        let large = try XCTUnwrap(CrabSymbol.image(named: "tabler-mouse", size: 64, template: false))
        XCTAssertFalse(small === large)
        XCTAssertEqual(small.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(small.isTemplate)
        XCTAssertEqual(large.size, NSSize(width: 64, height: 64))
        XCTAssertFalse(large.isTemplate)
        small.size = NSSize(width: 5, height: 5)
        small.isTemplate = false
        small.accessibilityDescription = "Changed by one caller"
        let original = try XCTUnwrap(CrabSymbol.image(named: "mouse"))
        XCTAssertEqual(original.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(original.isTemplate)
        XCTAssertNotEqual(original.accessibilityDescription, small.accessibilityDescription)
    }

    func testAuxiliaryControlsAndRepairWindowReuseTheSharedGlyphs() throws {
        let buttonSymbols: [(NSButton, String)] = [
            (referenceButton("+", action: {}), "plus"),
            (referenceButton("-", action: {}), "minus"),
            (ClosureButton("Choose", symbol: "folder", action: {}), "folder"),
            (HoverHelpButton(title: "Help", message: "Explanation"), "help-circle")
        ]
        for (button, name) in buttonSymbols {
            XCTAssertEqual(try alpha(XCTUnwrap(button.image)), try alpha(XCTUnwrap(CrabSymbol.image(named: name))), name)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-SymbolControls-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(directory: directory)
        let scene = FilenameRepairWindowController(urls: [], store: store)
        defer { scene.window?.close() }
        let buttons = descendants(try XCTUnwrap(scene.window?.contentView)).compactMap { $0 as? NSButton }
        for (title, name) in [("确认改名…", "check"), ("在访达中显示", "folder")] {
            let button = try XCTUnwrap(buttons.first { $0.title == L(title) }, title)
            XCTAssertEqual(try alpha(XCTUnwrap(button.image)), try alpha(XCTUnwrap(CrabSymbol.image(named: name))), title)
        }
        XCTAssertFalse(try XCTUnwrap(scene.window).isVisible)
    }
}
