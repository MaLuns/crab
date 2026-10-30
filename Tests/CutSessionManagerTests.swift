import XCTest
import AppKit
import Darwin
@testable import Crab

final class CutSessionManagerTests: XCTestCase {
    private var root: URL!
    private var pasteboard: NSPasteboard!
    private var center: NotificationCenter!
    private var managers: [CutSessionManager] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CrabCutSession-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        pasteboard = NSPasteboard.withUniqueName()
        center = NotificationCenter()
    }
    override func tearDownWithError() throws {
        for manager in managers { try manager.shutdown() }
        managers = []
        pasteboard.releaseGlobally()
        try FileManager.default.removeItem(at: root)
    }

    func testCancelRestoresVisibleFilesAndPreservesOriginallyHiddenAndOtherFlags() throws {
        let visible = try file("visible.txt"), hidden = try file("hidden.txt")
        try setFlags(UInt32(UF_NODUMP), on: visible)
        try setFlags(UInt32(UF_HIDDEN), on: hidden)
        let manager = try makeManager()
        try manager.cut([visible, hidden], hideOriginals: true)
        XCTAssertTrue(try isHidden(visible)); XCTAssertTrue(try isHidden(hidden))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as! [String: Any]
        let originals = (json["records"] as! [[String: Any]]).compactMap { $0["originalHidden"] as? Bool }
        XCTAssertEqual(originals, [false, true])
        try manager.cancel()
        XCTAssertFalse(try isHidden(visible)); XCTAssertTrue(try isHidden(hidden))
        XCTAssertEqual(try flags(visible), UInt32(UF_NODUMP))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertFalse(try manager.prepareForPaste().move)
    }

    func testCutWithoutHideStillMovesAndDoesNotWriteRecoveryJournal() throws {
        let source = try file("plain.txt")
        let manager = try makeManager()
        try manager.cut([source], hideOriginals: false)
        XCTAssertFalse(try isHidden(source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        let plan = try manager.prepareForPaste()
        XCTAssertEqual(plan.urls, [source]); XCTAssertTrue(plan.move)
        try manager.completePaste(plan)
        XCTAssertTrue(pasteboard.types?.isEmpty ?? true)
    }

    func testNewCutAndCopyRestorePreviousSessionBeforeReplacingIt() throws {
        let first = try file("first.txt"), second = try file("second.txt")
        let manager = try makeManager()
        try manager.cut([first], hideOriginals: true)
        try manager.cut([second], hideOriginals: true)
        XCTAssertFalse(try isHidden(first)); XCTAssertTrue(try isHidden(second))
        try manager.prepareForCopy()
        pasteboard.clearContents(); XCTAssertTrue(pasteboard.setString("new copy", forType: .string))
        XCTAssertFalse(try isHidden(second))
        XCTAssertEqual(pasteboard.string(forType: .string), "new copy")
        XCTAssertFalse(try manager.prepareForPaste().move)
    }

    func testExternalClipboardReplacementRestoresAndKeepsNewClipboardContent() throws {
        let source = try file("cut.txt"), copied = try file("copied.txt")
        let manager = try makeManager()
        try manager.cut([source], hideOriginals: true)
        pasteboard.clearContents(); XCTAssertTrue(pasteboard.writeObjects([copied as NSURL]))
        let count = pasteboard.changeCount
        try manager.pollPasteboard()
        XCTAssertFalse(try isHidden(source))
        XCTAssertEqual(pasteboard.changeCount, count)
        let plan = try manager.prepareForPaste()
        XCTAssertFalse(plan.move); XCTAssertEqual(plan.urls, [copied])
    }

    func testAutomaticClipboardMonitoringRestoresAfterAnotherWriter() throws {
        let source = try file("automatic.txt")
        let manager = try makeManager(pollInterval: 0.01)
        try manager.cut([source], hideOriginals: true)
        pasteboard.clearContents(); XCTAssertTrue(pasteboard.setString("external", forType: .string))
        let count = pasteboard.changeCount
        let deadline = Date().addingTimeInterval(1)
        while try isHidden(source), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(try isHidden(source))
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string(forType: .string), "external")
        try manager.shutdown()
    }

    func testPasteRestoresBeforeMoveAndFailedTransferCanRetry() throws {
        let source = try file("move.txt")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let manager = try makeManager()
        try manager.cut([source], hideOriginals: true)
        let first = try manager.prepareForPaste()
        XCTAssertFalse(try isHidden(source))
        XCTAssertThrowsError(try FileOperations().transfer(urls: first.urls, to: root.appendingPathComponent("missing"), move: first.move))
        let retry = try manager.prepareForPaste()
        XCTAssertTrue(retry.move); XCTAssertEqual(retry.urls, [source])
        let result = try FileOperations().transfer(urls: retry.urls, to: destination, move: retry.move)
        XCTAssertFalse(try isHidden(try XCTUnwrap(result.first)))
        try manager.completePaste(retry)
        XCTAssertTrue(pasteboard.types?.isEmpty ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testOldAsyncPasteCompletionCannotClearOrRestoreNewCut() throws {
        let first = try file("first.txt"), second = try file("second.txt")
        let manager = try makeManager()
        try manager.cut([first], hideOriginals: true)
        let old = try manager.prepareForPaste()
        try manager.cut([second], hideOriginals: true)
        let count = pasteboard.changeCount
        try manager.completePaste(old)
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertTrue(try isHidden(second))
        let new = try manager.prepareForPaste()
        XCTAssertEqual(new.urls, [second]); XCTAssertTrue(new.move)
    }

    func testRecoveryConsumesDurableCrashJournalAndKeepsOriginallyHidden() throws {
        let visible = try file("visible.txt"), hidden = try file("hidden.txt")
        try setFlags(UInt32(UF_HIDDEN), on: hidden)
        let interrupted = try makeManager()
        try interrupted.cut([visible, hidden], hideOriginals: true)
        let recovered = try makeManager()
        XCTAssertFalse(try isHidden(visible)); XCTAssertTrue(try isHidden(hidden))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertFalse(try recovered.prepareForPaste().move)
        try interrupted.shutdown()
    }

    func testRecoveryFollowsOriginalIdentityAfterRenameAndNeverChangesReplacement() throws {
        let original = try file("original.txt")
        let manager = try makeManager()
        try manager.cut([original], hideOriginals: true)
        let renamed = root.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: original, to: renamed)
        let replacement = try file("original.txt")
        try setFlags(UInt32(UF_HIDDEN), on: replacement)
        try manager.cancel()
        XCTAssertFalse(try isHidden(renamed))
        XCTAssertTrue(try isHidden(replacement))
    }

    func testTerminationNotificationRestoresWithoutTouchingOtherNotificationCenters() throws {
        let source = try file("exit.txt")
        let manager = try makeManager()
        try manager.cut([source], hideOriginals: true)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertFalse(try isHidden(source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertThrowsError(try manager.cut([source], hideOriginals: true))
    }

    func testInvalidJournalAndJournalWriteFailureNeverHideFilesOrReplaceClipboard() throws {
        let source = try file("safe.txt")
        try Data("invalid journal".utf8).write(to: journal)
        XCTAssertThrowsError(try CutSessionManager(pasteboard: pasteboard, journalURL: journal, pollInterval: 0, notificationCenter: center))
        XCTAssertEqual(try String(contentsOf: journal), "invalid journal")
        try FileManager.default.removeItem(at: journal)
        let blocked = root.appendingPathComponent("blocked")
        let manager = try CutSessionManager(pasteboard: pasteboard, journalURL: blocked.appendingPathComponent("journal.json"), pollInterval: 0, notificationCenter: center)
        managers.append(manager)
        try Data().write(to: blocked)
        pasteboard.clearContents(); XCTAssertTrue(pasteboard.setString("keep", forType: .string))
        let count = pasteboard.changeCount
        XCTAssertThrowsError(try manager.cut([source], hideOriginals: true))
        XCTAssertFalse(try isHidden(source))
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
    }

    func testRestorationFailureRetainsJournalAndCanRetryWhenAccessReturns() throws {
        guard getuid() != 0 else { throw XCTSkip("权限错误测试需要普通用户运行。") }
        let folder = root.appendingPathComponent("restricted")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let source = folder.appendingPathComponent("file.txt")
        try Data("test".utf8).write(to: source)
        let manager = try makeManager()
        try manager.cut([source], hideOriginals: true)
        XCTAssertEqual(chmod(folder.path, 0), 0)
        defer { _ = chmod(folder.path, 0o700) }
        XCTAssertThrowsError(try manager.cancel())
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertEqual(chmod(folder.path, 0o700), 0)
        XCTAssertTrue(try isHidden(source))
        try manager.cancel()
        XCTAssertFalse(try isHidden(source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testFailedShutdownKeepsCutAndMonitoringAvailableUntilSuccessfulShutdown() throws {
        guard getuid() != 0 else { throw XCTSkip("权限错误测试需要普通用户运行。") }
        let folder = root.appendingPathComponent("restricted-shutdown")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let source = folder.appendingPathComponent("file.txt")
        try Data("test".utf8).write(to: source)
        let second = try file("second.txt")
        let manager = try makeManager(pollInterval: 0.01)
        try manager.cut([source], hideOriginals: true)
        XCTAssertEqual(chmod(folder.path, 0), 0)
        defer { _ = chmod(folder.path, 0o700) }
        XCTAssertThrowsError(try manager.shutdown())
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertEqual(chmod(folder.path, 0o700), 0)
        try manager.cut([second], hideOriginals: true)
        XCTAssertFalse(try isHidden(source)); XCTAssertTrue(try isHidden(second))
        pasteboard.clearContents(); XCTAssertTrue(pasteboard.setString("after cancelled exit", forType: .string))
        let deadline = Date().addingTimeInterval(1)
        while try isHidden(second), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(try isHidden(second))
        XCTAssertEqual(pasteboard.string(forType: .string), "after cancelled exit")
        try manager.cut([second], hideOriginals: true)
        try manager.shutdown()
        XCTAssertFalse(try isHidden(second))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertThrowsError(try manager.cut([second], hideOriginals: true))
    }

    private var journal: URL { root.appendingPathComponent("journal.json") }
    private func makeManager(pollInterval: TimeInterval = 0) throws -> CutSessionManager {
        let manager = try CutSessionManager(pasteboard: pasteboard, journalURL: journal, pollInterval: pollInterval, notificationCenter: center)
        managers.append(manager)
        return manager
    }
    private func file(_ name: String) throws -> URL {
        let result = root.appendingPathComponent(name)
        try Data("test".utf8).write(to: result)
        return result
    }
    private func flags(_ url: URL) throws -> UInt32 {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return value.st_flags
    }
    private func isHidden(_ url: URL) throws -> Bool { try flags(url) & UInt32(UF_HIDDEN) != 0 }
    private func setFlags(_ flags: UInt32, on url: URL) throws {
        guard chflags(url.path, flags) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
}
