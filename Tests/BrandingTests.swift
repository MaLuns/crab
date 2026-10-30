import XCTest
import AppKit
@testable import Crab

final class BrandingTests: XCTestCase {
    func testAllNineBundledLanguagesKeepTheCrabBrandInVisibleCopy() throws {
        let originalLanguage = AppLocalization.languageCode
        defer { AppLocalization.languageCode = originalLanguage }
        let languages = AppLocalization.supportedLanguages.filter { !$0.code.isEmpty }
        XCTAssertEqual(languages.count, 9)
        for language in languages {
            let table = try XCTUnwrap(AppLocalization.translations(for: language.code, in: Bundle.main), language.code)
            AppLocalization.languageCode = language.code
            for source in ["Crab", "关于Crab", "退出Crab", "Crab设置…"] {
                let translation = try XCTUnwrap(table[source], language.code + ": " + source)
                XCTAssertTrue(translation.contains("Crab"), language.code + ": " + source)
                XCTAssertEqual(L(source), translation, language.code + ": " + source)
            }
            XCTAssertEqual(L("Crab"), "Crab", language.code)
        }
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Crab")
    }

    func testActualBundledArtworkKeepsColorAlphaAndIndependentRequestedSizes() throws {
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "CrabIcon", withExtension: "png"))
        let original = try XCTUnwrap(NSImage(contentsOf: resource))
        let expected = try bitmap(original)
        let originalSize = original.size
        var previous: NSImage?
        for size: CGFloat in [18, 20, 70] {
            let image = try XCTUnwrap(CrabIcon.image(size: size))
            XCTAssertTrue(image.isValid)
            XCTAssertFalse(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: size, height: size))
            if let previous { XCTAssertFalse(image === previous) }
            previous = image
            let actual = try bitmap(image)
            var visible = 0, colored = 0
            for y in 0..<actual.pixelsHigh {
                for x in 0..<actual.pixelsWide {
                    let color = try XCTUnwrap(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let reference = try XCTUnwrap(expected.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    XCTAssertEqual(color.alphaComponent, reference.alphaComponent, accuracy: 1.0 / 255)
                    if color.alphaComponent > 0.1 {
                        visible += 1
                        if max(color.redComponent, color.greenComponent, color.blueComponent)
                            - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.1 { colored += 1 }
                        XCTAssertEqual(color.redComponent, reference.redComponent, accuracy: 1.0 / 255)
                        XCTAssertEqual(color.greenComponent, reference.greenComponent, accuracy: 1.0 / 255)
                        XCTAssertEqual(color.blueComponent, reference.blueComponent, accuracy: 1.0 / 255)
                    }
                }
            }
            XCTAssertGreaterThan(visible, 500, "The brand image must contain visible artwork.")
            XCTAssertGreaterThan(colored, 100, "Original artwork must retain color rather than become a monochrome template.")
        }
        XCTAssertEqual(original.size, originalSize)
        for size: CGFloat in [0, -1, .infinity, .nan] { XCTAssertNil(CrabIcon.image(size: size)) }
    }

    func testFinderExtensionLoadsItsOwnBundledArtworkWithoutTheAppResourcePath() throws {
        let extensionURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
            .appendingPathComponent("CrabFinder.appex", isDirectory: true)
        let bundle = try XCTUnwrap(Bundle(url: extensionURL))
        let resource = try XCTUnwrap(bundle.url(forResource: "CrabIcon", withExtension: "png"))
        let resourcePath = resource.resolvingSymlinksInPath().path
        let extensionPath = extensionURL.resolvingSymlinksInPath().path
        XCTAssertTrue(resourcePath.hasPrefix(extensionPath + "/"), "Resource: \(resourcePath); extension: \(extensionPath)")
        let image = try XCTUnwrap(CrabIcon.image(size: 20, in: bundle))
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 20, height: 20))
        let appData = try Data(contentsOf: try XCTUnwrap(Bundle.main.url(forResource: "CrabIcon", withExtension: "png")))
        XCTAssertEqual(try Data(contentsOf: resource), appData)
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let pixels = 64
        let result = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: result))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        graphics.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
                   operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return result
    }
}
