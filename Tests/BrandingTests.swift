import XCTest
import AppKit
@testable import Crab

@MainActor
final class BrandingTests: XCTestCase {
    private func bitmap(_ image: NSImage?) throws -> NSBitmapImageRep {
        let image = try XCTUnwrap(image)
        return NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }

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

    func testBundledArtworkLoadsIndependentImagesAtRequestedSizes() throws {
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "CrabIcon", withExtension: "png"))
        let original = try XCTUnwrap(NSImage(contentsOf: resource))
        let originalSize = original.size
        var previous: NSImage?
        for size: CGFloat in [18, 20, 70] {
            let image = try XCTUnwrap(CrabIcon.image(size: size))
            XCTAssertTrue(image.isValid)
            XCTAssertFalse(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: size, height: size))
            if let previous { XCTAssertFalse(image === previous) }
            previous = image
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

    func testLightAndDarkArtworkSwapForegroundAndBackgroundWithoutChangingAlpha() throws {
        let light = try bitmap(CrabIcon.image(size: 128, appearance: NSAppearance(named: .aqua)!))
        let dark = try bitmap(CrabIcon.image(size: 128, appearance: NSAppearance(named: .darkAqua)!))
        XCTAssertEqual(light.pixelsWide, dark.pixelsWide)
        XCTAssertEqual(light.pixelsHigh, dark.pixelsHigh)
        var foreground = 0, background = 0
        for y in stride(from: 0, to: light.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: light.pixelsWide, by: 16) {
                let a = try XCTUnwrap(light.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(dark.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(a.alphaComponent, b.alphaComponent, accuracy: 1.0 / 255)
                guard a.alphaComponent > 0.95 else { continue }
                // AppKit color management changes intermediate gray values;
                // verify the visible foreground/background roles instead.
                if a.redComponent < 0.15 {
                    foreground += 1
                    for channel in [b.redComponent, b.greenComponent, b.blueComponent] {
                        XCTAssertGreaterThan(channel, 0.8)
                    }
                }
                if a.redComponent > 0.85 {
                    background += 1
                    for channel in [b.redComponent, b.greenComponent, b.blueComponent] {
                        XCTAssertLessThan(channel, 0.2)
                    }
                }
            }
        }
        XCTAssertGreaterThan(foreground, 0)
        XCTAssertGreaterThan(background, foreground)
    }

    func testFinderArtworkResolvesEachAppearanceBeforeCrossProcessEncoding() throws {
        let extensionURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
            .appendingPathComponent("CrabFinder.appex", isDirectory: true)
        let bundle = try XCTUnwrap(Bundle(url: extensionURL))
        for name: NSAppearance.Name in [.aqua, .darkAqua, .accessibilityHighContrastDarkAqua, .aqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let image = try XCTUnwrap(CrabIcon.image(size: 20, in: bundle, appearance: appearance))
            let encoded = try NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: true)
            let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: encoded))
            let actual = try bitmap(decoded)
            let expected = try bitmap(CrabIcon.image(size: 20, appearance: appearance))
            XCTAssertEqual(actual.pixelsWide, expected.pixelsWide)
            XCTAssertEqual(actual.pixelsHigh, expected.pixelsHigh)
            let a = try XCTUnwrap(actual.colorAt(x: actual.pixelsWide / 2, y: actual.pixelsHigh / 5)?.usingColorSpace(.sRGB))
            let b = try XCTUnwrap(expected.colorAt(x: expected.pixelsWide / 2, y: expected.pixelsHigh / 5)?.usingColorSpace(.sRGB))
            XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 1.0 / 255)
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            XCTAssertEqual(a.redComponent, dark ? 0 : 1, accuracy: 0.03)
        }
    }
}
