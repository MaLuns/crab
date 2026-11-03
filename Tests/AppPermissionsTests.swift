import ApplicationServices
import CoreServices
import XCTest
@testable import Crab

final class AppPermissionsTests: XCTestCase {
    private func environment(accessibility: Bool = false, inputMonitoring: Bool = false,
                             extensionEnabled: Bool = false, iTermInstalled: Bool = false,
                             running: Set<String> = [],
                             automationPermission: @escaping (String, AEEventClass, AEEventID) -> OSStatus = { _, _, _ in
                                 XCTFail("A target that is not running must never be queried.")
                                 return OSStatus(paramErr)
                             }) -> AppPermissions.Environment {
        .init(hasAccessibilityPermission: { accessibility },
              hasInputMonitoringPermission: { inputMonitoring },
              isFinderExtensionEnabled: { extensionEnabled },
              isApplicationInstalled: { $0 == "com.googlecode.iterm2" && iTermInstalled },
              isApplicationRunning: { running.contains($0) },
              automationPermission: automationPermission)
    }

    func testAutomationResultsPreserveConsentAndRunningDistinctions() {
        XCTAssertEqual(AppPermissions.automationState(for: noErr), .authorized)
        XCTAssertEqual(AppPermissions.automationState(for: OSStatus(errAEEventNotPermitted)), .notAuthorized)
        XCTAssertEqual(AppPermissions.automationState(for: OSStatus(errAEEventWouldRequireUserConsent)), .notDetermined)
        XCTAssertEqual(AppPermissions.automationState(for: OSStatus(procNotFound)), .notRunning)
        XCTAssertEqual(AppPermissions.automationState(for: OSStatus(paramErr)), .unavailable)
    }

    func testSnapshotKeepsFilePermissionsUnconfirmedAndOmitsUninstalledITerm() {
        let statuses = AppPermissions.currentStatuses(environment: environment())
        XCTAssertEqual(statuses, [
            .init(permission: .accessibility, state: .notAuthorized),
            .init(permission: .inputMonitoring, state: .notAuthorized),
            .init(permission: .finderAutomation, state: .notRunning),
            .init(permission: .filesAndFolders, state: .requiresSystemSettings),
            .init(permission: .fullDiskAccess, state: .requiresSystemSettings),
            .init(permission: .finderExtension, state: .disabled)
        ])
    }

    func testInstalledStoppedITermIsShownWithoutQueryingOrLaunchingIt() {
        let statuses = AppPermissions.currentStatuses(environment: environment(iTermInstalled: true))
        XCTAssertEqual(statuses.first { $0.permission == .iTermAutomation }?.state, .notRunning)
    }

    func testSnapshotQueriesOnlyRunningTargetsForTheEventsUsedByEachFeature() {
        var queriedTargets: [String] = []
        let dependencies = environment(accessibility: true, inputMonitoring: true, extensionEnabled: true,
                                       iTermInstalled: true, running: ["com.apple.finder", "com.googlecode.iterm2"]) { identifier, eventClass, eventID in
            queriedTargets.append(identifier)
            if identifier == "com.apple.finder" {
                XCTAssertEqual(eventClass, AEEventClass(kAECoreSuite))
                XCTAssertEqual(eventID, AEEventID(kAEGetData))
                return noErr
            }
            XCTAssertEqual(identifier, "com.googlecode.iterm2")
            XCTAssertEqual(eventClass, AEEventClass(typeWildCard))
            XCTAssertEqual(eventID, AEEventID(typeWildCard))
            return OSStatus(errAEEventWouldRequireUserConsent)
        }
        let statuses = AppPermissions.currentStatuses(environment: dependencies)
        XCTAssertEqual(queriedTargets, ["com.apple.finder", "com.googlecode.iterm2"])
        XCTAssertEqual(statuses.first { $0.permission == .accessibility }?.state, .authorized)
        XCTAssertEqual(statuses.first { $0.permission == .inputMonitoring }?.state, .authorized)
        XCTAssertEqual(statuses.first { $0.permission == .finderAutomation }?.state, .authorized)
        XCTAssertEqual(statuses.first { $0.permission == .iTermAutomation }?.state, .notDetermined)
        XCTAssertEqual(statuses.first { $0.permission == .finderExtension }?.state, .enabled)
    }

    func testFailedAutomationCheckDoesNotChangeOtherIndependentPermissions() {
        let dependencies = environment(accessibility: true, running: ["com.apple.finder"]) { _, _, _ in OSStatus(errAEEventNotPermitted) }
        let statuses = AppPermissions.currentStatuses(environment: dependencies)
        XCTAssertEqual(statuses.first { $0.permission == .finderAutomation }?.state, .notAuthorized)
        XCTAssertEqual(statuses.first { $0.permission == .accessibility }?.state, .authorized)
        XCTAssertEqual(statuses.first { $0.permission == .inputMonitoring }?.state, .notAuthorized)
        XCTAssertEqual(statuses.first { $0.permission == .filesAndFolders }?.state, .requiresSystemSettings)
        XCTAssertEqual(statuses.first { $0.permission == .fullDiskAccess }?.state, .requiresSystemSettings)
    }

    func testRegistryUsesOnlyTheCurrentExtensionPathAndPreservesUnknownElections() throws {
        let current = try XCTUnwrap(Bundle.main.builtInPlugInsURL).appendingPathComponent("CrabFinder.appex")
        let identifier = try XCTUnwrap(Bundle(url: current)?.bundleIdentifier)
        let other = "/Fixture/Other/Crab.app/Contents/PlugIns/CrabFinder.appex"
        func record(_ marker: String, _ path: String) -> String {
            marker + "    " + identifier + "(1.0.0)\tUUID\t2026-10-29 00:00:00 +0000\t" + path
        }
        func state(_ output: String?, nativeEnabled: Bool = false) -> AppPermissionState {
            AppPermissions.finderExtensionState(nativeEnabled: nativeEnabled, extensionURL: current) { queriedID in
                XCTAssertEqual(queriedID, identifier)
                return output
            }
        }
        let currentDisabled = record("+", other) + "\n" + record("-", current.path) + "\n (2 plug-ins)"
        XCTAssertEqual(state(currentDisabled, nativeEnabled: true), .disabled)
        let currentEnabled = record("-", other) + "\n" + record("+", current.path)
        XCTAssertEqual(state(currentEnabled), .enabled)
        XCTAssertEqual(state(record("+", other)), .unavailable)
        XCTAssertEqual(state(record("+", current.path).replacingOccurrences(of: identifier, with: "other.extension")), .unavailable)
        for marker in ["?", "=", "!"] {
            XCTAssertEqual(state(record(marker, current.path)), .unavailable)
        }
        let conflicting = record("+", current.path) + "\n" + record("-", current.path)
        XCTAssertEqual(state(conflicting), .unavailable)
        XCTAssertEqual(state(nil), .unavailable)
        XCTAssertEqual(state(nil, nativeEnabled: true), .enabled)
        XCTAssertEqual(AppPermissions.finderExtensionState(nativeEnabled: true, extensionURL: nil) { _ in
            XCTFail("Missing bundle metadata must skip the registry query")
            return nil
        }, .enabled)
    }

    func testRegistryFailureDoesNotMisreportTheExtensionAsDisabled() {
        var dependencies = environment()
        dependencies.finderExtensionState = { .unavailable }
        let statuses = AppPermissions.currentStatuses(environment: dependencies)
        XCTAssertEqual(statuses.first { $0.permission == .finderExtension }?.state, .unavailable)
    }

    func testStalledAutomationIsBoundedAndDoesNotHideOtherPermissionResults() {
        let blocked = DispatchSemaphore(value: 0)
        defer { blocked.signal() }
        let loaded = expectation(description: "Bounded permission snapshot")
        let dependencies = environment(accessibility: true, inputMonitoring: true, extensionEnabled: true,
                                       iTermInstalled: true, running: ["com.apple.finder", "com.googlecode.iterm2"]) { identifier, _, _ in
            if identifier == "com.apple.finder" { blocked.wait() }
            return noErr
        }
        AppPermissions.SnapshotLoader().load(environment: dependencies, timeout: 0.05) { statuses in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(statuses.first { $0.permission == .accessibility }?.state, .authorized)
            XCTAssertEqual(statuses.first { $0.permission == .inputMonitoring }?.state, .authorized)
            XCTAssertEqual(statuses.first { $0.permission == .finderExtension }?.state, .enabled)
            XCTAssertEqual(statuses.first { $0.permission == .finderAutomation }?.state, .unavailable)
            XCTAssertEqual(statuses.first { $0.permission == .iTermAutomation }?.state, .authorized)
            XCTAssertEqual(statuses.first { $0.permission == .fullDiskAccess }?.state, .requiresSystemSettings)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)
    }

    func testRetryReusesAStillBlockedAutomationCallAndRechecksOtherPermissions() {
        let blocked = DispatchSemaphore(value: 0), lock = NSLock()
        defer { blocked.signal() }
        var calls = 0
        let loader = AppPermissions.SnapshotLoader()
        let first = expectation(description: "First bounded snapshot"), second = expectation(description: "Retry bounded snapshot")
        var dependencies = environment(running: ["com.apple.finder"]) { _, _, _ in
            lock.lock(); calls += 1; lock.unlock()
            blocked.wait()
            return noErr
        }
        loader.load(environment: dependencies, timeout: 0.03) { statuses in
            XCTAssertEqual(statuses.first { $0.permission == .accessibility }?.state, .notAuthorized)
            first.fulfill()
        }
        wait(for: [first], timeout: 1)
        dependencies.hasAccessibilityPermission = { true }
        loader.load(environment: dependencies, timeout: 0.03) { statuses in
            XCTAssertEqual(statuses.first { $0.permission == .accessibility }?.state, .authorized)
            XCTAssertEqual(statuses.first { $0.permission == .finderAutomation }?.state, .unavailable)
            second.fulfill()
        }
        wait(for: [second], timeout: 1)
        lock.lock(); let observed = calls; lock.unlock()
        XCTAssertEqual(observed, 1, "A stuck system call must not create another worker on every refresh.")
    }
}
