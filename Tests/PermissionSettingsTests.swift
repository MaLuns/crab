import AppKit
import XCTest
@testable import Crab

@MainActor
final class PermissionSettingsTests: XCTestCase {
    private var directory: URL!
    private var originalLanguage = ""

    override func setUpWithError() throws {
        originalLanguage = AppLocalization.languageCode
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-PermissionSettings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        AppLocalization.languageCode = originalLanguage
    }

    private var fixture: [AppPermissionStatus] {
        [
            .init(permission: .accessibility, state: .authorized),
            .init(permission: .inputMonitoring, state: .notAuthorized),
            .init(permission: .finderAutomation, state: .notDetermined),
            .init(permission: .iTermAutomation, state: .notRunning),
            .init(permission: .filesAndFolders, state: .requiresSystemSettings),
            .init(permission: .fullDiskAccess, state: .requiresSystemSettings),
            .init(permission: .finderExtension, state: .disabled)
        ]
    }

    private func makeScene(name: String,
                           load: @escaping (@escaping ([AppPermissionStatus]) -> Void) -> Void,
                           request: @escaping (AppPermission, @escaping () -> Void) -> Void = { _, _ in
                               XCTFail("Reading permission status must not request system authorization.")
                           },
                           open: @escaping (AppPermission) -> Void = { _ in
                               XCTFail("Reading permission status must not open System Settings.")
                           }) -> (ConfigurationStore, SettingsWindowController) {
        let store = ConfigurationStore(directory: directory.appendingPathComponent(name))
        store.update { $0.languageCode = "zh-Hans" }
        let scene = SettingsWindowController(store: store,
            hasAccessibilityPermission: { true },
            requestAccessibilityPermission: { XCTFail("Tests must not request actual Accessibility permission.") },
            loadPermissionStatuses: load, requestPermission: request, openPermissionSettings: open)
        scene.selectPage(SettingsPage.general.rawValue)
        scene.window?.contentView?.layoutSubtreeIfNeeded()
        return (store, scene)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func find<T: NSView>(_ identifier: String, as type: T.Type, in root: NSView,
                                 file: StaticString = #filePath, line: UInt = #line) throws -> T {
        let matches = descendants(root).compactMap { $0 as? T }.filter { $0.identifier?.rawValue == identifier }
        XCTAssertEqual(matches.count, 1, identifier, file: file, line: line)
        return try XCTUnwrap(matches.first, identifier, file: file, line: line)
    }

    private func activate(_ button: NSButton, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(button.isEnabled, button.identifier?.rawValue ?? "button", file: file, line: line)
        let action = try XCTUnwrap(button.action, file: file, line: line)
        XCTAssertTrue(button.sendAction(action, to: button.target), file: file, line: line)
    }

    func testAllPermissionsShareOneCardWithReasonHelpAndHonestIndependentStatus() throws {
        let statuses = fixture
        let (store, scene) = makeScene(name: "content", load: { $0(statuses) })
        defer { scene.window?.close() }
        let before = store.configuration
        let root = try XCTUnwrap(scene.window?.contentView)
        let card = try find("general-permissions-card", as: ReferenceMaterialCard.self, in: root)
        let list = try find("permission-list", as: SettingsPermissionsView.self, in: card)
        XCTAssertTrue(list.superview === card)
        for item in statuses {
            let suffix = item.permission.rawValue
            let row = try find("permission-row-" + suffix, as: NSView.self, in: list)
            XCTAssertTrue(row.superview === list)
            let name = try find("permission-name-" + suffix, as: NSTextField.self, in: row)
            let help = try find("permission-help-" + suffix, as: HoverHelpButton.self, in: row)
            let status = try find("permission-status-" + suffix, as: NSTextField.self, in: row)
            let action = try find("permission-action-" + suffix, as: NSButton.self, in: row)
            XCTAssertEqual(name.stringValue, item.permission.title)
            XCTAssertFalse(item.permission.explanation.isEmpty)
            XCTAssertEqual(help.accessibilityHelp(), item.permission.explanation)
            XCTAssertNotNil(help.image, "The permission reason must be discoverable through its question-mark icon.")
            XCTAssertEqual(status.stringValue, item.state.title)
            XCTAssertFalse(action.title.isEmpty)
        }
        for permission in [AppPermission.filesAndFolders, .fullDiskAccess] {
            let status = try find("permission-status-" + permission.rawValue, as: NSTextField.self, in: list)
            XCTAssertEqual(status.stringValue, L("需在系统设置中确认"))
            XCTAssertNotEqual(status.stringValue, L("已授权"))
            XCTAssertNotEqual(status.stringValue, L("未授权"))
        }
        XCTAssertEqual(store.configuration, before)
        XCTAssertFalse(try XCTUnwrap(scene.window).isVisible)
    }

    func testManualRefreshAndApplicationActivationReadNewStatusWithoutRequestingAccess() throws {
        var statuses = fixture
        var loads = 0
        let (store, scene) = makeScene(name: "refresh", load: { completion in
            loads += 1
            completion(statuses)
        })
        defer { scene.window?.close() }
        let before = store.configuration
        let root = try XCTUnwrap(scene.window?.contentView)
        XCTAssertEqual(loads, 1)
        statuses[1] = .init(permission: .inputMonitoring, state: .authorized)
        try activate(find("permission-refresh", as: NSButton.self, in: root))
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(try find("permission-status-inputMonitoring", as: NSTextField.self, in: root).stringValue, L("已授权"))
        statuses[0] = .init(permission: .accessibility, state: .notAuthorized)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(loads, 3)
        XCTAssertEqual(try find("permission-status-accessibility", as: NSTextField.self, in: root).stringValue, L("未授权"))
        XCTAssertEqual(store.configuration, before)
    }

    func testOrdinaryActivationAndHiddenPermissionSourcesDoNotRestoreAWindow() throws {
        let (_, scene) = makeScene(name: "no-window-return", load: { $0([]) })
        let window = try XCTUnwrap(scene.window)
        defer { window.close() }
        let applicationCenter = NotificationCenter(), workspaceCenter = NotificationCenter()
        var restores = 0
        let coordinator = PermissionWindowReturnCoordinator(window: window, applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter, restoreWindow: { _ in restores += 1 })
        applicationCenter.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        coordinator.begin(windowIsVisible: false)
        applicationCenter.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(restores, 0)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.hidesOnDeactivate)
    }

    func testAuthorizationReturnRestoresOnlyTheOriginalWindowAndKeepsTheSelectedPage() throws {
        let (_, scene) = makeScene(name: "return-original-page", load: { $0([]) })
        let window = try XCTUnwrap(scene.window)
        defer { window.close() }
        scene.selectPage(SettingsPage.library.rawValue)
        let content = try XCTUnwrap(window.contentView)
        let originalSubviews = descendants(content).map(ObjectIdentifier.init)
        let applicationCenter = NotificationCenter(), workspaceCenter = NotificationCenter()
        var restored: [NSWindow] = []
        let coordinator = PermissionWindowReturnCoordinator(window: window, applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter, restoreWindow: { restored.append($0) })
        coordinator.begin(windowIsVisible: true)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertTrue(restored.isEmpty, "The authorization handoff has not left the app yet.")
        applicationCenter.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(restored.count, 1)
        XCTAssertTrue(restored.first === window)
        XCTAssertEqual(descendants(content).map(ObjectIdentifier.init), originalSubviews)
    }

    func testLeavingSystemSettingsRestoresOrderingOnceWithoutWaitingForProcessExit() throws {
        let (_, scene) = makeScene(name: "return-from-system-settings", load: { $0([]) })
        let window = try XCTUnwrap(scene.window)
        defer { window.close() }
        let applicationCenter = NotificationCenter(), workspaceCenter = NotificationCenter()
        let simulatedSettings = NSRunningApplication.current
        let bundleIdentifier = try XCTUnwrap(simulatedSettings.bundleIdentifier)
        let userInfo: [String: Any] = [NSWorkspace.applicationUserInfoKey: simulatedSettings]
        var restores = 0
        let coordinator = PermissionWindowReturnCoordinator(window: window, applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter, settingsBundleIdentifier: bundleIdentifier,
            restoreWindow: { restored in
                XCTAssertTrue(restored === window)
                restores += 1
            })
        coordinator.begin(windowIsVisible: true)
        workspaceCenter.post(name: NSWorkspace.didDeactivateApplicationNotification, object: nil, userInfo: userInfo)
        XCTAssertEqual(restores, 0, "Unrelated application switches do not finish an authorization handoff.")
        workspaceCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: userInfo)
        XCTAssertEqual(restores, 0, "Opening System Settings must leave its own window in front.")
        coordinator.begin(windowIsVisible: true)
        workspaceCenter.post(name: NSWorkspace.didDeactivateApplicationNotification, object: nil, userInfo: userInfo)
        workspaceCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: userInfo)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(restores, 1)
    }

    func testClosingMinimizingOrHidingTheSourceCancelsAuthorizationReturn() throws {
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSApplication.didHideNotification] {
            let (_, scene) = makeScene(name: "cancel-return-" + name.rawValue, load: { $0([]) })
            let window = try XCTUnwrap(scene.window)
            defer { window.close() }
            let applicationCenter = NotificationCenter(), workspaceCenter = NotificationCenter()
            var restores = 0
            let coordinator = PermissionWindowReturnCoordinator(window: window, applicationCenter: applicationCenter,
                workspaceCenter: workspaceCenter, restoreWindow: { _ in restores += 1 })
            coordinator.begin(windowIsVisible: true)
            applicationCenter.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            applicationCenter.post(name: name, object: name == NSApplication.didHideNotification ? NSApp : window)
            applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            XCTAssertEqual(restores, 0, name.rawValue)
        }
    }

    func testExplicitGrantUsesOnlyTheSelectedPermissionAndRefreshesAfterCompletion() throws {
        for permission in [AppPermission.accessibility, .inputMonitoring, .finderAutomation, .iTermAutomation] {
            let initialState: AppPermissionState = [.accessibility, .inputMonitoring].contains(permission) ? .notAuthorized : .notDetermined
            var statuses = fixture.map { item in
                AppPermissionStatus(permission: item.permission,
                                    state: item.permission == permission ? initialState : item.state)
            }
            var requested: [AppPermission] = []
            var opened: [AppPermission] = []
            var loads = 0
            let (store, scene) = makeScene(name: "grant-" + permission.rawValue, load: { completion in
                loads += 1
                completion(statuses)
            }, request: { selected, completion in
                requested.append(selected)
                statuses = statuses.map { AppPermissionStatus(permission: $0.permission, state: $0.permission == selected ? .authorized : $0.state) }
                completion()
            }, open: { opened.append($0) })
            defer { scene.window?.close() }
            let before = store.configuration
            let root = try XCTUnwrap(scene.window?.contentView)
            XCTAssertTrue(requested.isEmpty)
            let button = try find("permission-action-" + permission.rawValue, as: NSButton.self, in: root)
            XCTAssertEqual(button.title, L("授权"))
            try activate(button)
            XCTAssertEqual(requested, [permission])
            XCTAssertEqual(opened, [.accessibility, .inputMonitoring].contains(permission) ? [permission] : [])
            XCTAssertEqual(loads, 2)
            XCTAssertEqual(try find("permission-status-" + permission.rawValue, as: NSTextField.self, in: root).stringValue, L("已授权"))
            XCTAssertEqual(store.configuration, before, "Granting access must not enable a shortcut or change user preferences.")
        }
    }

    func testUnconfirmedDeniedAndStoppedTargetsOpenOnlyTheirOwnSettings() throws {
        let cases: [(AppPermission, AppPermissionState)] = [
            (.finderAutomation, .notRunning), (.iTermAutomation, .notRunning),
            (.finderAutomation, .notAuthorized), (.filesAndFolders, .requiresSystemSettings),
            (.fullDiskAccess, .requiresSystemSettings), (.finderExtension, .disabled)
        ]
        for (permission, state) in cases {
            let statuses = fixture.map { AppPermissionStatus(permission: $0.permission, state: $0.permission == permission ? state : $0.state) }
            var opened: [AppPermission] = []
            let (store, scene) = makeScene(name: permission.rawValue + "-" + String(describing: state),
                                           load: { $0(statuses) }, open: { opened.append($0) })
            defer { scene.window?.close() }
            let before = store.configuration
            let root = try XCTUnwrap(scene.window?.contentView)
            try activate(find("permission-action-" + permission.rawValue, as: NSButton.self, in: root))
            XCTAssertEqual(opened, [permission])
            XCTAssertEqual(store.configuration, before)
        }
        let prefix = "x-apple.systempreferences:com.apple.preference.security?"
        XCTAssertEqual(AppPermission.accessibility.settingsURL, prefix + "Privacy_Accessibility")
        XCTAssertEqual(AppPermission.inputMonitoring.settingsURL, prefix + "Privacy_ListenEvent")
        XCTAssertEqual(AppPermission.finderAutomation.settingsURL, prefix + "Privacy_Automation")
        XCTAssertEqual(AppPermission.iTermAutomation.settingsURL, prefix + "Privacy_Automation")
        XCTAssertEqual(AppPermission.filesAndFolders.settingsURL, prefix + "Privacy_FilesAndFolders")
        XCTAssertEqual(AppPermission.fullDiskAccess.settingsURL, prefix + "Privacy_AllFiles")
        XCTAssertNil(AppPermission.finderExtension.settingsURL, "Extension activation uses its dedicated system interface.")
    }

    func testDelayedSnapshotCannotReplaceAnotherPageOrANewerPermissionList() throws {
        var completions: [([AppPermissionStatus]) -> Void] = []
        let (_, scene) = makeScene(name: "pending", load: { completions.append($0) })
        defer { scene.window?.close() }
        let root = try XCTUnwrap(scene.window?.contentView)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(try find("permission-status-accessibility", as: NSTextField.self, in: root).stringValue, L("检测中…"))
        XCTAssertFalse(try find("permission-refresh", as: NSButton.self, in: root).isEnabled)
        scene.selectPage(SettingsPage.menu.rawValue)
        completions[0](fixture)
        XCTAssertFalse(descendants(root).contains { $0 is SettingsPermissionsView })
        scene.selectPage(SettingsPage.general.rawValue)
        XCTAssertEqual(completions.count, 2)
        completions[0](fixture)
        XCTAssertEqual(try find("permission-status-accessibility", as: NSTextField.self, in: root).stringValue, L("检测中…"))
        let refreshed = fixture.map { AppPermissionStatus(permission: $0.permission, state: $0.permission == .accessibility ? .notAuthorized : $0.state) }
        completions[1](refreshed)
        XCTAssertEqual(try find("permission-status-accessibility", as: NSTextField.self, in: root).stringValue, L("未授权"))
        XCTAssertTrue(try find("permission-refresh", as: NSButton.self, in: root).isEnabled)
    }

    func testBackgroundSnapshotIsAppliedToTheExistingCard() throws {
        var completion: (([AppPermissionStatus]) -> Void)?
        let (_, scene) = makeScene(name: "background", load: { completion = $0 })
        defer { scene.window?.close() }
        let root = try XCTUnwrap(scene.window?.contentView)
        let list = try find("permission-list", as: SettingsPermissionsView.self, in: root)
        let refresh = try find("permission-refresh", as: NSButton.self, in: root)
        XCTAssertFalse(refresh.isEnabled)
        let apply = try XCTUnwrap(completion)
        let statuses = fixture
        DispatchQueue.global(qos: .utility).async { apply(statuses) }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !refresh.isEnabled && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertTrue(refresh.isEnabled, "The main queue must apply the completed background check.")
        XCTAssertTrue(try find("permission-list", as: SettingsPermissionsView.self, in: root) === list)
        XCTAssertEqual(try find("permission-status-accessibility", as: NSTextField.self, in: root).stringValue, L("已授权"))
    }

    func testActivationDuringARefreshQueuesAFreshReadAndShowsProgress() throws {
        var completions: [([AppPermissionStatus]) -> Void] = []
        let (_, scene) = makeScene(name: "activation-during-refresh", load: { completions.append($0) })
        defer { scene.window?.close() }
        let root = try XCTUnwrap(scene.window?.contentView)
        XCTAssertEqual(try find("permission-refresh-feedback", as: NSTextField.self, in: root).stringValue, L("检测中…"))
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(completions.count, 1)
        completions[0](fixture)
        XCTAssertEqual(completions.count, 2, "A grant made while the previous query ran must get a new snapshot.")
        XCTAssertFalse(try find("permission-refresh", as: NSButton.self, in: root).isEnabled)
        let updated = fixture.map { AppPermissionStatus(permission: $0.permission, state: $0.permission == .inputMonitoring ? .authorized : $0.state) }
        completions[0](updated)
        XCTAssertEqual(try find("permission-status-inputMonitoring", as: NSTextField.self, in: root).stringValue, L("未授权"))
        completions[1](updated)
        XCTAssertEqual(try find("permission-status-inputMonitoring", as: NSTextField.self, in: root).stringValue, L("已授权"))
        XCTAssertEqual(try find("permission-refresh-feedback", as: NSTextField.self, in: root).stringValue, L("已完成"))
        XCTAssertTrue(try find("permission-refresh", as: NSButton.self, in: root).isEnabled)
    }

    func testPermissionRowsFitAndRemainVerticallyCenteredForEveryLanguageAndState() throws {
        let states: [AppPermissionState] = [.authorized, .notAuthorized, .notDetermined, .notRunning,
                                           .requiresSystemSettings, .unavailable, .enabled, .disabled]
        for language in AppLocalization.supportedLanguages {
            AppLocalization.languageCode = language.code
            for state in states {
                let view = SettingsPermissionsView(refresh: { XCTFail("Layout must not refresh status.") },
                                                   action: { _ in XCTFail("Layout must not activate a permission.") })
                view.show(AppPermission.allCases.map { .init(permission: $0, state: state) })
                view.layoutRows(width: 580)
                for child in descendants(view) where child is NSTextField || child is NSButton {
                    let context = language.code + " / " + String(describing: state) + " / " + (child.identifier?.rawValue ?? "control")
                    let parent = try XCTUnwrap(child.superview)
                    XCTAssertTrue(parent.bounds.insetBy(dx: -1, dy: -1).contains(child.frame), context)
                    if let field = child as? NSTextField {
                        let size = try XCTUnwrap(field.cell).cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000))
                        XCTAssertGreaterThanOrEqual(field.bounds.height + 1, size.height, context)
                        if field.identifier?.rawValue.hasPrefix("permission-name-") == true ||
                            field.identifier?.rawValue.hasPrefix("permission-status-") == true {
                            XCTAssertEqual(field.bounds.height, ceil(size.height), accuracy: 0.5, context)
                        }
                    }
                    if let button = child as? NSButton, !button.title.isEmpty, let cell = button.cell {
                        let textRect = cell.titleRect(forBounds: button.bounds)
                        let measured = (button.title as NSString).size(withAttributes: [.font: button.font ?? NSFont.systemFont(ofSize: 13)])
                        XCTAssertGreaterThanOrEqual(textRect.width + 1, measured.width, context)
                        XCTAssertGreaterThanOrEqual(textRect.height + 1, measured.height, context)
                    }
                    if child.identifier?.rawValue.hasPrefix("permission-name-") == true ||
                        child.identifier?.rawValue.hasPrefix("permission-help-") == true ||
                        child.identifier?.rawValue.hasPrefix("permission-status-") == true ||
                        child.identifier?.rawValue.hasPrefix("permission-action-") == true {
                        XCTAssertEqual(child.frame.midY, parent.bounds.midY, accuracy: 0.5, context)
                    }
                }
                for parent in descendants(view) {
                    let children = parent.subviews.filter { $0 is NSTextField || $0 is NSButton }
                    for (index, first) in children.enumerated() {
                        for second in children.dropFirst(index + 1) {
                            let overlap = first.frame.intersection(second.frame)
                            XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                                          language.code + ": overlapping permission controls")
                        }
                    }
                }
            }
        }
    }
}
