import AppKit
import XCTest
@testable import Crab

@MainActor
final class CrabSymbolTests: XCTestCase {
    func testOperationSymbolsResolve() throws {
        for name in OperationRegistry.shared.definitions.map(\.symbol) + SettingsPage.allCases.map { $0.categoryIcon.symbol } {
            XCTAssertNotNil(CrabSymbol.image(named: name), name)
        }
    }
    func testCatalogProducesUniqueValidVectorImages() throws {
        XCTAssertFalse(CrabSymbol.names.isEmpty)
        XCTAssertEqual(CrabSymbol.names.count, Set(CrabSymbol.names).count)
        for name in CrabSymbol.names {
            let image = try XCTUnwrap(CrabSymbol.image(named: name), name)
            XCTAssertTrue(image.isValid, name)
            XCTAssertTrue(image.isTemplate, name)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18), name)
            let vector = try XCTUnwrap(image.representations.compactMap { $0 as? NSPDFImageRep }.first, name)
            XCTAssertEqual(vector.pageCount, 1, name)
            XCTAssertEqual(vector.bounds.size, NSSize(width: 24, height: 24), name)
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
}
