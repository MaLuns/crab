import AppKit
import XCTest
@testable import Crab

@MainActor
final class StatusBarPresentationTests: XCTestCase {
    private final class SettingsTarget: NSObject {
        var openCount = 0
        var quitCount = 0
        @objc func openSettings() { openCount += 1 }
        @objc func quit() { quitCount += 1 }
    }

    func testEveryLanguageOffersOnlyWorkingSettingsAndQuitCommands() {
        let originalLanguage = AppLocalization.languageCode
        defer { AppLocalization.languageCode = originalLanguage }
        let target = SettingsTarget()
        let action = #selector(SettingsTarget.openSettings)
        let quitAction = #selector(SettingsTarget.quit)
        for language in AppLocalization.supportedLanguages where !language.code.isEmpty {
            AppLocalization.languageCode = language.code
            let menu = StatusBarPresentation.menu(target: target, settingsAction: action, quitAction: quitAction)
            menu.update()
            XCTAssertEqual(menu.items.map(\.title), [L("通用设置"), L("退出")], language.code)
            XCTAssertEqual(menu.items.count, 2)
            XCTAssertFalse(menu.items.contains { $0.isSeparatorItem || $0.submenu != nil })
            guard menu.items.count == 2 else { continue }
            XCTAssertTrue(menu.items[0].target === target)
            XCTAssertEqual(menu.items[0].action, action)
            XCTAssertEqual(menu.items[0].keyEquivalent, ",")
            XCTAssertTrue(menu.items[1].target === target)
            XCTAssertEqual(menu.items[1].action, quitAction)
            XCTAssertNotEqual(menu.items[1].action, #selector(NSApplication.terminate(_:)))
            XCTAssertNil(menu.items[1].image)
            XCTAssertEqual(menu.items[1].keyEquivalent, "q")
            menu.performActionForItem(at: 0)
            menu.performActionForItem(at: 1)
        }
        XCTAssertEqual(target.openCount, 9)
        XCTAssertEqual(target.quitCount, 9)
    }

    func testTrayTileHasATransparentCrabCutoutAtBothDisplayScales() throws {
        let image = StatusBarPresentation.icon()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        for scale in [1, 2] {
            let bitmap = try render(image, scale: scale)
            var visible = 0, transparent = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if color.alphaComponent > 0.1 {
                        visible += 1
                        XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 1.0 / 255)
                        XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 1.0 / 255)
                    } else { transparent += 1 }
                }
            }
            XCTAssertGreaterThan(visible, 30 * scale * scale)
            XCTAssertGreaterThan(transparent, 30 * scale * scale)
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 9 * scale, y: 9 * scale)).alphaComponent, 0,
                           "The crab body must be a transparent hole rather than a painted symbol.")
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: scale, y: 9 * scale)).alphaComponent, 0.95,
                                 "The rounded tile must remain opaque beside the cutout.")
            for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0),
                           (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0, accuracy: 1.0 / 255)
            }
            for background in [NSColor(deviceRed: 0.2, green: 0.6, blue: 0.35, alpha: 1),
                               NSColor(deviceWhite: 0.85, alpha: 1)] {
                let composite = try render(image, scale: scale, background: background)
                let center = try XCTUnwrap(composite.colorAt(x: 9 * scale, y: 9 * scale)?.usingColorSpace(.deviceRGB))
                let expected = try XCTUnwrap(background.usingColorSpace(.deviceRGB))
                XCTAssertEqual(center.alphaComponent, 1, "Drawing the cutout must not erase the host background.")
                XCTAssertEqual(center.redComponent, expected.redComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(center.greenComponent, expected.greenComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(center.blueComponent, expected.blueComponent, accuracy: 1.0 / 255)
            }
        }
    }

    private func render(_ image: NSImage, scale: Int, background: NSColor? = nil) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 18 * scale, pixelsHigh: 18 * scale, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let bounds = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        graphics.cgContext.clear(bounds)
        if let background { background.setFill(); bounds.fill() }
        graphics.cgContext.saveGState()
        graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        image.draw(in: NSRect(origin: .zero, size: image.size))
        graphics.cgContext.restoreGState()
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
