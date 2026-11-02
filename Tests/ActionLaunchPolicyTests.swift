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
        for arguments in [["Crab", "--settings"], ["Crab", "--page", "操作库"]] {
            XCTAssertTrue(ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: arguments,
                hasLaunched: true, isDefaultLaunch: false, hasPendingActionURLs: true, event: try actionEvent()))
        }
        XCTAssertEqual(ActionLaunchPolicy.settingsPageArgument(in: ["Crab", "--page", "菜单编排"]), "菜单编排")
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
