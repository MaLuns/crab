import XCTest
import AppKit
import Carbon
@testable import Crab

final class ActionLaunchPolicyTests: XCTestCase {
    func testFinderDeliveryUsesBackgroundConfigurationWithoutHidingExistingWindows() throws {
        let configuration = ActionLaunchPolicy.backgroundOpenConfiguration()
        XCTAssertFalse(configuration.activates)
        XCTAssertFalse(configuration.promptsUserIfNeeded)
        XCTAssertFalse(configuration.addsToRecentItems)
        XCTAssertFalse(configuration.hides)
        XCTAssertFalse(configuration.hidesOthers)
        XCTAssertFalse(configuration.createsNewApplicationInstance)
        XCTAssertTrue(configuration.arguments.isEmpty, "Sandboxed Finder extensions cannot rely on custom launch arguments.")
        let request = ActionRequest(operationID: "builtin.template.json", paths: [], targetDirectory: "/tmp/中文目录")
        let url = try request.encodedURL()
        XCTAssertTrue(ActionLaunchPolicy.isActionURL(url))
        let decoded = try ActionRequest.decode(url)
        XCTAssertEqual(decoded.operationID, request.operationID)
        XCTAssertEqual(decoded.targetDirectory, request.targetDirectory)
        XCTAssertEqual(decoded.paths, request.paths)
        XCTAssertFalse(ActionLaunchPolicy.isActionURL(try XCTUnwrap(URL(string: "https://example.invalid/execute"))))
        XCTAssertFalse(ActionLaunchPolicy.isActionURL(try XCTUnwrap(URL(string: "crab-native://settings"))))
    }

    func testFirstActionLaunchDoesNotOpenSettingsRegardlessOfURLDeliveryOrder() throws {
        let event = try actionEvent()
        for hasLaunched in [false, true] {
            for isDefaultLaunch in [false, true] {
                XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: ["Crab"],
                    hasLaunched: hasLaunched, isDefaultLaunch: isDefaultLaunch, hasPendingActionURLs: true, event: nil))
                XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: ["Crab"],
                    hasLaunched: hasLaunched, isDefaultLaunch: isDefaultLaunch, hasPendingActionURLs: false, event: event))
            }
        }
        XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: ["Crab"],
            hasLaunched: false, isDefaultLaunch: false, hasPendingActionURLs: false, event: nil))
    }

    func testOrdinaryFirstLaunchAndExplicitSettingsRequestsStillOpenSettings() throws {
        XCTAssertTrue(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: ["Crab"],
            hasLaunched: false, isDefaultLaunch: true, hasPendingActionURLs: false, event: nil))
        XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: ["Crab"],
            hasLaunched: true, isDefaultLaunch: true, hasPendingActionURLs: false, event: nil))
        for arguments in [["Crab", "--settings"], ["Crab", "--page", "新建文件"]] {
            XCTAssertTrue(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: arguments,
                hasLaunched: true, isDefaultLaunch: false, hasPendingActionURLs: true, event: try actionEvent()))
        }
        XCTAssertEqual(ActionLaunchPolicy.settingsPageArgument(in: ["Crab", "--page", "工具箱"]), "工具箱")
        XCTAssertNil(ActionLaunchPolicy.settingsPageArgument(in: ["Crab", "--page"]))
    }

    func testBackgroundReopenAndURLDeliveryDoNotShowSettingsButExplicitReopenDoes() throws {
        XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: try actionEvent(), applicationIsActive: true))
        let background = event(eventClass: AEEventClass(kCoreEventClass), id: AEEventID(kAEReopenApplication))
        background.setParam(NSAppleEventDescriptor(boolean: false), forKeyword: AEKeyword(kAEApplicationActivationExpected))
        XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: background, applicationIsActive: true))
        let foreground = event(eventClass: AEEventClass(kCoreEventClass), id: AEEventID(kAEReopenApplication))
        foreground.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: AEKeyword(kAEApplicationActivationExpected))
        XCTAssertTrue(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: foreground, applicationIsActive: false))
        let normalReopen = event(eventClass: AEEventClass(kCoreEventClass), id: AEEventID(kAEReopenApplication))
        XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: normalReopen, applicationIsActive: false))
        XCTAssertTrue(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: normalReopen, applicationIsActive: true))
        XCTAssertFalse(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: nil, applicationIsActive: false))
        XCTAssertTrue(ActionLaunchPolicy.shouldShowSettingsOnReopen(event: nil, applicationIsActive: true))
    }

    @MainActor
    func testAddingACommonDirectoryPersistsWithoutCreatingAWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-SilentCommon-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(directory: directory.appendingPathComponent("configuration"))
        store.update { $0.operations = [.init(id: "common", parameters: .tool(.init(action: .addCommon)))] }
        let router = ActionRouter(store: store)
        let windows = NSApp.windows.map(\.windowNumber)
        let keyWindow = NSApp.keyWindow

        router.execute(.init(operationID: "common", paths: [directory.path], targetDirectory: directory.path))

        XCTAssertEqual(store.configuration.operations.compactMap { if case .directory(let p) = $0.parameters { return p }; return nil }, [directory.path])
        XCTAssertEqual(ConfigurationStore(directory: directory.appendingPathComponent("configuration")).configuration.operations.compactMap { if case .directory(let p) = $0.parameters { return p }; return nil }, [directory.path])
        XCTAssertEqual(NSApp.windows.map(\.windowNumber), windows)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
    }

    @MainActor
    func testFileAttributeChangesAndDeletionCompleteWithoutProgressOrSuccessWindows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-SilentFiles-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.txt")
        try Data("test".utf8).write(to: file)
        let store = ConfigurationStore(directory: directory.appendingPathComponent("configuration"))
        store.update { config in
            config.operations = [.hide, .unhide, .toggleExtension, .makeWritable, .deletePermanently].map { (action: ToolAction) in
                var p = ToolParameters(action: action); p.confirmDeletion = false
                return OperationRecord(id: action.rawValue, parameters: .tool(p))
            }
        }
        let router = ActionRouter(store: store)
        let windows = NSApp.windows.map(\.windowNumber)
        let keyWindow = NSApp.keyWindow

        func run(_ action: ToolAction, until completed: () throws -> Bool) throws {
            router.execute(.init(operationID: action.rawValue, paths: [file.path], targetDirectory: directory.path))
            XCTAssertEqual(NSApp.windows.map(\.windowNumber), windows, action.rawValue)
            let deadline = Date().addingTimeInterval(3)
            while try !completed(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                XCTAssertEqual(NSApp.windows.map(\.windowNumber), windows, action.rawValue)
            }
            XCTAssertTrue(try completed(), action.rawValue)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(NSApp.windows.map(\.windowNumber), windows, action.rawValue)
            XCTAssertTrue(NSApp.keyWindow === keyWindow, action.rawValue)
        }

        try run(.hide) { try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.isHiddenKey]).isHidden == true }
        try run(.unhide) { try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.isHiddenKey]).isHidden == false }
        let extensionWasHidden = try file.resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension ?? false
        try run(.toggleExtension) { try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension == !extensionWasHidden }
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
        try run(.makeWritable) { ((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o200 != 0 }
        try run(.deletePermanently) { !FileManager.default.fileExists(atPath: file.path) }
    }

    private func actionEvent() throws -> NSAppleEventDescriptor {
        let url = try ActionRequest(operationID: "builtin.template.txt", paths: [], targetDirectory: "/tmp/test").encodedURL()
        let result = event(eventClass: AEEventClass(kInternetEventClass), id: AEEventID(kAEGetURL))
        result.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: AEKeyword(keyDirectObject))
        return result
    }

    private func event(eventClass: AEEventClass, id: AEEventID) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: eventClass, eventID: id, targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }
}
