import XCTest
import AppKit
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
            XCTAssertEqual(max(small.size.width, small.size.height), 14, accuracy: 0.001)
            XCTAssertEqual(max(large.size.width, large.size.height), 28, accuracy: 0.001)
        }
    }

    func testApplicationFallbackReturnsIndependentTemplateImagesAtRequestedSizes() throws {
        let first = try XCTUnwrap(ToolMenuIcon.applicationFallback(size: 14))
        let second = try XCTUnwrap(ToolMenuIcon.applicationFallback(size: 28))
        XCTAssertFalse(first === second)
        for image in [first, second] {
            XCTAssertTrue(image.isTemplate)
            XCTAssertTrue(image.isValid)
        }
        XCTAssertEqual(max(first.size.width, first.size.height), 14, accuracy: 0.001)
        XCTAssertEqual(max(second.size.width, second.size.height), 28, accuracy: 0.001)
    }
}
