import XCTest
import PDFKit
import ImageIO
@testable import Crab

final class DocumentTemplateTests: XCTestCase {
    private func resource(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: nil), "Missing bundled template: " + name)
    }

    func testIndependentIllustratorTemplateIsOneBlankPDFCompatiblePage() throws {
        let document = try XCTUnwrap(PDFDocument(url: resource("Blank.ai")))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 595.276, accuracy: 0.01)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 841.89, accuracy: 0.01)
        XCTAssertTrue((page.string ?? "").isEmpty)
    }

    func testIndependentPSDActuallyDecodesToWhiteRGBImage() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(resource("Blank.psd") as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1890)
        XCTAssertEqual(image.height, 1417)
        let pixel = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { pixel.deallocate() }
        let context = try XCTUnwrap(CGContext(data: pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: pixel, count: 4)), [255, 255, 255, 255])
    }

    func testPackagedTemplatesAreRealArchivesAndWPSAreRealCompoundDocuments() throws {
        for name in ["Blank.pptx", "Blank.pages", "Blank.numbers", "Blank.key"] {
            let data = try Data(contentsOf: resource(name))
            XCTAssertTrue(data.starts(with: [0x50, 0x4b, 0x03, 0x04]), name)
            XCTAssertGreaterThan(data.count, 1000, name)
        }
        for name in ["Blank.wps", "Blank.et", "Blank.dps"] {
            let data = try Data(contentsOf: resource(name))
            XCTAssertEqual(Array(data.prefix(8)), [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1], name)
            XCTAssertGreaterThan(data.count, 4096, name)
        }
    }
}
