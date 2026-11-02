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
}
