import XCTest
import CoreFoundation
@testable import Crab

final class FilenameRepairTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CrabFilenameTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testUTF8AndGB18030CandidatesComeFromActualReversibleBytes() throws {
        let original = "中文报告.txt"
        let utf8Wrong = try XCTUnwrap(String(data: Data(original.utf8), encoding: .isoLatin1))
        XCTAssertTrue(FilenameRepair().candidates(for: utf8Wrong).contains(where: { $0.name == original }))
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let gbBytes = try XCTUnwrap(original.data(using: gb, allowLossyConversion: false))
        let gbWrong = try XCTUnwrap(String(data: gbBytes, encoding: .isoLatin1))
        XCTAssertTrue(FilenameRepair().candidates(for: gbWrong).contains(where: { $0.name == original }))
        let chineseWrong = try XCTUnwrap(String(data: Data("中文.txt".utf8), encoding: gb))
        XCTAssertTrue(FilenameRepair().candidates(for: chineseWrong).contains(where: { $0.name == "中文.txt" }))
        XCTAssertTrue(FilenameRepair().candidates(for: "plain-file.txt").isEmpty)
        XCTAssertTrue(FilenameRepair().candidates(for: "已丢失�.txt").isEmpty)
        let candidates = FilenameRepair().candidates(for: utf8Wrong)
        XCTAssertEqual(Set(candidates.map(\.name)).count, candidates.count)
        XCTAssertTrue(candidates.allSatisfy { $0.explanation.contains("可逆") })
    }

    func testPreviewCandidateCanBeAppliedWithoutChangingContents() throws {
        let original = "中文.txt", wrong = String(data: Data("中文.txt".utf8), encoding: .isoLatin1)!
        let input = try file(wrong, "contents")
        let candidate = try XCTUnwrap(FilenameRepair().candidates(for: wrong).first(where: { $0.name == original }))
        let output = try FilenameRepair().apply(mapping: [input: candidate.name])
        XCTAssertEqual(output, [root.appendingPathComponent(original)])
        XCTAssertEqual(try String(contentsOf: output[0]), "contents")
        XCTAssertFalse(FileManager.default.fileExists(atPath: input.path)); try assertNoStages()
    }

    func testBatchSwapPreservesBothFilesAndSupportsCaseOnlyRename() throws {
        let a = try file("a.txt", "A"), b = try file("b.txt", "B")
        _ = try FilenameRepair().apply(mapping: [a: "b.txt", b: "a.txt"])
        XCTAssertEqual(try String(contentsOf: a), "B"); XCTAssertEqual(try String(contentsOf: b), "A")
        let output = try FilenameRepair().apply(mapping: [a: "A.TXT"])
        XCTAssertEqual(try String(contentsOf: output[0]), "B")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains("A.TXT"))
        try assertNoStages()
    }

    func testConflictsUnsafeNamesMissingAndNestedSourcesLeaveFilesUntouched() throws {
        let a = try file("a", "A"), b = try file("b", "B"), existing = try file("existing", "E")
        XCTAssertThrowsError(try FilenameRepair().apply(mapping: [a: "new", b: existing.lastPathComponent]))
        XCTAssertThrowsError(try FilenameRepair().apply(mapping: [a: "same", b: "SAME"]))
        for name in ["", ".", "..", "../escape", "/absolute", "bad\\path", "bad:path", "bad\nname", String(repeating: "x", count: 256)] {
            XCTAssertThrowsError(try FilenameRepair().apply(mapping: [a: name]), name)
        }
        XCTAssertThrowsError(try FilenameRepair().apply(mapping: [a: "new", root.appendingPathComponent("missing"): "other"]))
        let directory = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let child = directory.appendingPathComponent("child"); try Data("child".utf8).write(to: child)
        XCTAssertThrowsError(try FilenameRepair().apply(mapping: [directory: "renamed", child: "new-child"]))
        XCTAssertEqual(try String(contentsOf: a), "A"); XCTAssertEqual(try String(contentsOf: b), "B")
        XCTAssertEqual(try String(contentsOf: existing), "E"); XCTAssertEqual(try String(contentsOf: child), "child")
        try assertNoStages()
    }

    func testFailureAfterPartialCommitRestoresEveryOriginalName() throws {
        let a = try file("a", "A"), b = try file("b", "B")
        var calls = 0
        let repair = FilenameRepair(move: { source, destination in
            calls += 1
            if calls == 4 { throw NSError(domain: "InjectedRenameFailure", code: 1) }
            try FilenameRepair.exclusiveMove(source, destination)
        })
        XCTAssertThrowsError(try repair.apply(mapping: [a: "alpha", b: "beta"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("已恢复原名"))
        }
        XCTAssertEqual(try String(contentsOf: a), "A"); XCTAssertEqual(try String(contentsOf: b), "B")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("alpha").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("beta").path))
        try assertNoStages()
    }

    func testRollbackConflictPreservesRecoveryFileAndExternalReplacement() throws {
        let a = try file("a", "A"), b = try file("b", "B")
        var calls = 0
        let repair = FilenameRepair(move: { source, destination in
            calls += 1
            if calls == 4 {
                try Data("external".utf8).write(to: a, options: .withoutOverwriting)
                throw NSError(domain: "InjectedRenameFailure", code: 2)
            }
            try FilenameRepair.exclusiveMove(source, destination)
        })
        XCTAssertThrowsError(try repair.apply(mapping: [a: "alpha", b: "beta"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("无法恢复"))
            XCTAssertTrue(error.localizedDescription.contains(".crab-rename-"))
        }
        XCTAssertEqual(try String(contentsOf: a), "external"); XCTAssertEqual(try String(contentsOf: b), "B")
        let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".crab-rename-") }
        XCTAssertEqual(stages.count, 1); XCTAssertEqual(try String(contentsOf: stages[0]), "A")
    }

    func testRenamingSymlinkDoesNotRenameOrModifyTarget() throws {
        let target = try file("target", "target bytes"), link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let output = try FilenameRepair().apply(mapping: [link: "renamed-link"])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: output[0].path), target.path)
        XCTAssertEqual(try String(contentsOf: target), "target bytes")
        try assertNoStages()
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(name); try Data(contents.utf8).write(to: url); return url
    }
    private func assertNoStages() throws {
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".crab-rename-") })
    }
}
