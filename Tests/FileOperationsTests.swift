import XCTest
@testable import Crab

final class FileOperationsTests: XCTestCase {
    private var root: URL!
    private let manager = FileManager.default
    private var operations: FileOperations!

    override func setUpWithError() throws {
        root = manager.temporaryDirectory.appendingPathComponent("CrabTests-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        operations = FileOperations()
    }
    override func tearDownWithError() throws { try manager.removeItem(at: root) }

    @discardableResult
    private func file(_ name: String, in directory: URL? = nil, contents: String = "original") throws -> URL {
        let url = (directory ?? root!).appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
    private func directory(_ name: String, in parent: URL? = nil) throws -> URL {
        let url = (parent ?? root!).appendingPathComponent(name, isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testCreateTextAndNumberWithoutOverwrite() throws {
        let template = FileTemplate(name: "文本", suffix: "txt", contents: "new")
        let existing = try file("报告.txt")
        let created = try operations.createFile(template: template, in: root, name: "报告")
        XCTAssertEqual(created.lastPathComponent, "报告 2.txt")
        XCTAssertEqual(try contents(existing), "original")
        XCTAssertEqual(try contents(created), "new")
        let third = try operations.createFile(template: template, in: root, name: "报告.txt")
        XCTAssertEqual(third.lastPathComponent, "报告 3.txt")
    }

    func testUnnamedFilesUseTheirSuffixAndKeepExistingFiles() throws {
        let existing = try file("未命名.txt", contents: "keep existing")
        let template = FileTemplate(name: "Renamed menu item", suffix: "txt", contents: "new document")
        let second = try operations.createFile(template: template, in: root)
        let third = try operations.createFile(template: template, in: root)
        XCTAssertEqual(second.lastPathComponent, "未命名 2.txt")
        XCTAssertEqual(third.lastPathComponent, "未命名 3.txt")
        XCTAssertEqual(try contents(existing), "keep existing")
        XCTAssertEqual(try contents(second), "new document")
        XCTAssertEqual(try contents(third), "new document")
        let noSuffix = FileTemplate(name: "自定义创建新文件", suffix: "")
        XCTAssertEqual(try operations.createFile(template: noSuffix, in: root).lastPathComponent, "未命名")
        XCTAssertEqual(try operations.createFile(template: noSuffix, in: root).lastPathComponent, "未命名 2")
    }

    func testDefaultNamesPreserveAllBuiltInTemplateContents() throws {
        for template in FileTemplate.defaults {
            let destination = try directory(template.id)
            let created = try operations.createFile(template: template, in: destination)
            XCTAssertEqual(created.lastPathComponent, "未命名" + (template.suffix.isEmpty ? "" : "." + template.suffix), template.id)
            if let resourceName = template.resourceName {
                let original = try XCTUnwrap(Bundle.main.url(forResource: resourceName, withExtension: nil))
                XCTAssertEqual(try Data(contentsOf: created), try Data(contentsOf: original), template.id)
            } else {
                XCTAssertEqual(try contents(created), template.contents, template.id)
            }
        }
    }

    func testImportedFileAndPackageTemplates() throws {
        let source = try file("template.docx", contents: "custom bytes")
        let destination = try directory("destination")
        let created = try operations.createFile(template: .init(name: "自定义", suffix: "docx", importedPath: source.path), in: destination, name: "合同")
        XCTAssertEqual(try contents(created), "custom bytes")
        let package = try directory("template.pages")
        try file("inside", in: package)
        let createdPackage = try operations.createFile(template: .init(name: "Pages", suffix: "pages", importedPath: package.path), in: destination, name: "文稿")
        XCTAssertEqual(try contents(createdPackage.appendingPathComponent("inside")), "original")
    }

    func testUnsafeNamesAreRejected() throws {
        for name in ["", " ", ".", "..", "../escape", "a/b", "a\\b", "a:b", "a\0b", "a\nb", String(repeating: "x", count: 256)] {
            XCTAssertThrowsError(try operations.uniqueURL(in: root, preferredName: name), name)
        }
        XCTAssertThrowsError(try operations.createFile(template: .init(name: "恶意", suffix: "../txt"), in: root, name: "safe"))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: root.path), [])
    }

    func testCopyAndMoveNeverOverwriteAndSameDirectoryMoveIsNoop() throws {
        let source = try file("a.txt")
        let destination = try directory("destination")
        let existing = try file("a.txt", in: destination, contents: "keep")
        let copied = try operations.transfer(urls: [source], to: destination, move: false)
        XCTAssertEqual(copied.first?.lastPathComponent, "a 2.txt")
        XCTAssertEqual(try contents(existing), "keep")
        XCTAssertTrue(manager.fileExists(atPath: source.path))
        let same = try operations.transfer(urls: [source], to: root, move: true)
        XCTAssertEqual(same, [source])
        let moved = try operations.transfer(urls: [source], to: destination, move: true)
        XCTAssertEqual(moved.first?.lastPathComponent, "a 3.txt")
        XCTAssertEqual(try contents(XCTUnwrap(moved.first)), "original")
        XCTAssertFalse(manager.fileExists(atPath: source.path))
    }

    func testRejectsDirectoryIntoItselfOrDescendantIncludingDestinationAlias() throws {
        let folder = try directory("folder")
        let child = try directory("child", in: folder)
        let alias = root.appendingPathComponent("alias")
        try manager.createSymbolicLink(at: alias, withDestinationURL: child)
        for destination in [folder, child, alias] {
            XCTAssertThrowsError(try operations.transfer(urls: [folder], to: destination, move: false))
        }
        XCTAssertThrowsError(try operations.transfer(urls: [folder, child], to: root, move: true))
        XCTAssertTrue(manager.fileExists(atPath: child.path))
    }

    func testSourcePreflightPreventsPartialCopy() throws {
        let source = try file("valid")
        let destination = try directory("destination")
        XCTAssertThrowsError(try operations.transfer(urls: [source, root.appendingPathComponent("missing")], to: destination, move: true))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: destination.path), [])
        XCTAssertEqual(try contents(source), "original")
    }

    func testFailedCopyKeepsAllSourcesAndCleansStaging() throws {
        let first = try file("first")
        let second = try file("second")
        let destination = try directory("destination")
        let failing = ControlledFileManager()
        failing.failCopyName = "second"
        XCTAssertThrowsError(try FileOperations(fileManager: failing).transfer(urls: [first, second], to: destination, move: true))
        XCTAssertEqual(try contents(first), "original")
        XCTAssertEqual(try contents(second), "original")
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: destination.path), [])
    }

    func testFailedMoveCleanupLeavesCompleteDestination() throws {
        let source = try file("keep")
        let destination = try directory("destination")
        let failing = ControlledFileManager()
        failing.failRemovePath = source.path
        XCTAssertThrowsError(try FileOperations(fileManager: failing).transfer(urls: [source], to: destination, move: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("完整保存"))
        }
        XCTAssertEqual(try contents(source), "original")
        XCTAssertEqual(try contents(destination.appendingPathComponent("keep")), "original")
    }

    func testDissolvePreservesCollisionAndDoesNotFollowChildLinks() throws {
        let outside = try directory("outside")
        let outsideFile = try file("protected", in: outside, contents: "protected")
        let folder = try directory("folder")
        try file("same.txt", in: folder, contents: "inner")
        let existing = try file("same.txt", contents: "outer")
        let link = folder.appendingPathComponent("external-link")
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        let result = try operations.dissolveFolders(urls: [folder])
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(manager.fileExists(atPath: folder.path))
        XCTAssertEqual(try contents(existing), "outer")
        XCTAssertEqual(try contents(root.appendingPathComponent("same 2.txt")), "inner")
        XCTAssertEqual(try contents(outsideFile), "protected")
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: root.appendingPathComponent("external-link").path), outside.path)
    }

    func testDissolveRejectsTopLevelLinkAndPreflightsEveryFolder() throws {
        let folder = try directory("folder")
        let child = try file("child", in: folder)
        let link = root.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertThrowsError(try operations.dissolveFolders(urls: [folder, link]))
        XCTAssertEqual(try contents(child), "original")
        XCTAssertTrue(manager.fileExists(atPath: link.path))
    }

    func testDissolveFailureNeverDeletesSourceFolderOrUncopiedChildren() throws {
        let folder = try directory("folder")
        let a = try file("a", in: folder)
        let b = try file("b", in: folder)
        let failing = ControlledFileManager()
        failing.failCopyName = "b"
        XCTAssertThrowsError(try FileOperations(fileManager: failing).dissolveFolders(urls: [folder]))
        XCTAssertEqual(try contents(a), "original")
        XCTAssertEqual(try contents(b), "original")
        XCTAssertTrue(manager.fileExists(atPath: folder.path))
    }

    func testDissolveLeavesUnexpectedNewChild() throws {
        let folder = try directory("folder")
        try file("a", in: folder)
        let injecting = ControlledFileManager()
        injecting.afterRemove = { url in
            if url.lastPathComponent == "a", url.deletingLastPathComponent() == folder {
                try Data("new data".utf8).write(to: folder.appendingPathComponent("arrived"))
            }
        }
        XCTAssertThrowsError(try FileOperations(fileManager: injecting).dissolveFolders(urls: [folder]))
        XCTAssertEqual(try contents(folder.appendingPathComponent("arrived")), "new data")
        XCTAssertEqual(try contents(root.appendingPathComponent("a")), "original")
    }

    func testMakeWritableOnlyAddsOwnerWriteAndRejectsSymlinks() throws {
        let source = try file("permissions")
        try manager.setAttributes([.posixPermissions: 0o451], ofItemAtPath: source.path)
        try operations.makeWritable(urls: [source])
        let mode = try XCTUnwrap(manager.attributesOfItem(atPath: source.path)[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(mode & 0o777, 0o651)
        let link = root.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try operations.makeWritable(urls: [link]))
    }

    func testHiddenAndExtensionAttributesDoNotChangeContentsOrPermissions() throws {
        let source = try file("attributes.txt")
        try manager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        try operations.setHidden(urls: [source], hidden: true)
        XCTAssertEqual(try URL(fileURLWithPath: source.path).resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
        try operations.setHidden(urls: [source], hidden: false)
        XCTAssertEqual(try URL(fileURLWithPath: source.path).resourceValues(forKeys: [.isHiddenKey]).isHidden, false)
        let original = try URL(fileURLWithPath: source.path).resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension ?? false
        try operations.toggleExtensions(urls: [source])
        XCTAssertEqual(try URL(fileURLWithPath: source.path).resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension, !original)
        try operations.toggleExtensions(urls: [source])
        XCTAssertEqual(try URL(fileURLWithPath: source.path).resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension, original)
        XCTAssertEqual(try contents(source), "original")
        let mode = try XCTUnwrap(manager.attributesOfItem(atPath: source.path)[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(mode & 0o777, 0o640)
    }

    func testCreatesFoldersAndDesktopLinksWithUniqueNames() throws {
        let source = try file("report.txt")
        let folders = try operations.createFoldersByFilename(urls: [source])
        XCTAssertEqual(folders.first?.lastPathComponent, "report")
        let desktop = try directory("desktop")
        try file("report.txt", in: desktop)
        let links = try operations.desktopLinks(urls: [source], desktop: desktop)
        XCTAssertEqual(links.first?.lastPathComponent, "report 2.txt")
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: XCTUnwrap(links.first).path), source.path)
    }

    func testDanglingLinkCountsAsExistingNameAndTransfersAsLink() throws {
        let dangling = root.appendingPathComponent("dangling")
        try manager.createSymbolicLink(atPath: dangling.path, withDestinationPath: "/does-not-exist-crab-test")
        XCTAssertEqual(try operations.uniqueURL(in: root, preferredName: "dangling").lastPathComponent, "dangling 2")
        let destination = try directory("destination")
        let result = try operations.transfer(urls: [dangling], to: destination, move: true)
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: XCTUnwrap(result.first).path), "/does-not-exist-crab-test")
    }
}

private final class ControlledFileManager: FileManager, @unchecked Sendable {
    var failCopyName: String?
    var failRemovePath: String?
    var afterRemove: ((URL) throws -> Void)?
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent == failCopyName { throw CocoaError(.fileWriteUnknown) }
        try super.copyItem(at: srcURL, to: dstURL)
    }
    override func removeItem(at URL: URL) throws {
        if URL.path == failRemovePath { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: URL)
        try afterRemove?(URL)
    }
}
