import XCTest
import CoreGraphics
import AppKit
@testable import Crab

final class FinderFallbackTests: XCTestCase {
    func testEachConfiguredModifierTriggersAndOtherModifiersDoNot() {
        for modifier in FallbackModifier.allCases {
            var config = AppConfiguration(); config.fallbackShortcut = true; config.fallbackModifier = modifier
            var policy = FinderFallbackTriggerState(settings: FinderFallbackTriggerSettings(config))
            XCTAssertEqual(policy.handle(type: .rightMouseDown, flags: modifier.flags, button: 1, isAllowed: true), .trigger)
            XCTAssertEqual(policy.handle(type: .rightMouseUp, flags: [], button: 1, isAllowed: false), .consume)
            XCTAssertEqual(policy.handle(type: .rightMouseUp, flags: [], button: 1, isAllowed: false), .passThrough)
            for other in FallbackModifier.allCases where other != modifier {
                XCTAssertEqual(policy.handle(type: .rightMouseDown, flags: other.flags, button: 1, isAllowed: true), .passThrough)
            }
        }
    }

    func testMiddleButtonIsIndependentAndConsumesOnlyItsPairedUp() throws {
        var config = AppConfiguration(); config.fallbackShortcut = false; config.fallbackMiddleClick = true
        var policy = FinderFallbackTriggerState(settings: FinderFallbackTriggerSettings(config))
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center))
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 2)
        XCTAssertEqual(policy.handle(type: event.type, flags: event.flags, button: event.getIntegerValueField(.mouseEventButtonNumber), isAllowed: true), .trigger)
        XCTAssertEqual(policy.handle(type: .otherMouseUp, flags: [], button: 3, isAllowed: false), .passThrough)
        XCTAssertEqual(policy.handle(type: .otherMouseUp, flags: [], button: 2, isAllowed: false), .consume)
        XCTAssertEqual(policy.handle(type: .otherMouseUp, flags: [], button: 2, isAllowed: true), .passThrough)
        XCTAssertEqual(policy.handle(type: .rightMouseDown, flags: .maskAlternate, button: 1, isAllowed: true), .passThrough)
    }

    func testPermissionAndFinderScopeGuardCannotBeBypassed() {
        var config = AppConfiguration(); config.fallbackShortcut = true; config.fallbackMiddleClick = true
        var policy = FinderFallbackTriggerState(settings: FinderFallbackTriggerSettings(config))
        XCTAssertEqual(policy.handle(type: .rightMouseDown, flags: .maskAlternate, button: 1, isAllowed: false), .passThrough)
        XCTAssertEqual(policy.handle(type: .otherMouseDown, flags: [], button: 2, isAllowed: false), .passThrough)
        XCTAssertEqual(policy.handle(type: .rightMouseUp, flags: [], button: 1, isAllowed: true), .passThrough)
        XCTAssertEqual(policy.handle(type: .otherMouseUp, flags: [], button: 2, isAllowed: true), .passThrough)
    }

    func testOnlyRequestedInputsAreEnabledAndResetClearsConsumedState() {
        var config = AppConfiguration(); config.fallbackShortcut = false; config.fallbackThreeFingerTap = true
        let settings = FinderFallbackTriggerSettings(config)
        XCTAssertTrue(settings.anyEnabled); XCTAssertFalse(settings.shortcutEnabled); XCTAssertFalse(settings.middleClickEnabled)
        var policy = FinderFallbackTriggerState(settings: settings)
        XCTAssertEqual(policy.handle(type: .rightMouseDown, flags: .maskAlternate, button: 1, isAllowed: true), .passThrough)
        config.fallbackThreeFingerTap = false
        XCTAssertFalse(FinderFallbackTriggerSettings(config).anyEnabled)
        config.fallbackShortcut = true; policy.settings = FinderFallbackTriggerSettings(config)
        XCTAssertEqual(policy.handle(type: .leftMouseDown, flags: .maskAlternate, button: 0, isAllowed: true), .passThrough)
        XCTAssertEqual(policy.handle(type: .rightMouseDown, flags: .maskAlternate, button: 1, isAllowed: true), .trigger)
        policy.reset()
        XCTAssertEqual(policy.handle(type: .rightMouseUp, flags: [], button: 1, isAllowed: true), .passThrough)
    }
}

final class FinderFallbackScopeTests: XCTestCase {
    private var homeDirectory: URL!
    private var scope: FinderFallbackScope!

    override func setUpWithError() throws {
        homeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-FallbackScope-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        scope = FinderFallbackScope(homeDirectory: homeDirectory)
    }

    override func tearDownWithError() throws {
        scope = nil
        try FileManager.default.removeItem(at: homeDirectory)
        homeDirectory = nil
    }

    @discardableResult
    private func directory(_ relativePath: String) throws -> URL {
        let url = homeDirectory.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testICloudRootAndNestedDocumentsAreAllowed() throws {
        for path in ["Library/Mobile Documents", "Library/Mobile Documents/com~apple~CloudDocs",
                     "Library/Mobile Documents/com~apple~CloudDocs/项目/资料",
                     "Library/Mobile Documents/com~apple~Pages/Documents"] {
            XCTAssertTrue(scope.contains(directory: try directory(path)), path)
        }
    }

    func testOneDrivePersonalAndMultipleBusinessAccountRootsAndChildrenAreAllowed() throws {
        for rootName in ["OneDrive", "OneDrive-Personal", "OneDrive-企业甲", "OneDrive-企业乙"] {
            let root = "Library/CloudStorage/" + rootName
            XCTAssertTrue(scope.contains(directory: try directory(root)), root)
            XCTAssertTrue(scope.contains(directory: try directory(root + "/项目/资料")), root)
        }
    }

    func testICloudMetadataRecognizesSyncedDesktopAndDocumentsAtTheirUsualPaths() throws {
        let desktop = try directory("Desktop").resolvingSymlinksInPath()
        let documents = try directory("Documents/项目").resolvingSymlinksInPath()
        let local = try directory("Downloads")
        let metadataScope = FinderFallbackScope(homeDirectory: homeDirectory, isUbiquitousItem: {
            [desktop.path, documents.path].contains($0.path)
        })
        XCTAssertTrue(metadataScope.contains(directory: desktop))
        XCTAssertTrue(metadataScope.contains(directory: documents))
        XCTAssertFalse(metadataScope.contains(directory: local))
        let unavailableMetadata = FinderFallbackScope(homeDirectory: homeDirectory, isUbiquitousItem: { _ in false })
        XCTAssertFalse(unavailableMetadata.contains(directory: desktop))
        XCTAssertFalse(unavailableMetadata.contains(directory: documents))
    }

    func testLocalDirectoriesOtherProvidersAndLookalikeRootsAreRejected() throws {
        for path in ["Documents", "Desktop", "OneDrive", "Documents/OneDrive-Personal",
                     "Documents/iCloud", "Library", "Library/CloudStorage",
                     "Library/CloudStorage/Dropbox/OneDrive-Personal",
                     "Library/CloudStorage/GoogleDrive-account",
                     "Library/CloudStorage/OneDriveBackup", "Library/CloudStorage/OneDrive-",
                     "Library/CloudStorage Backup/OneDrive-Personal",
                     "Library/Mobile Documents Backup/com~apple~CloudDocs"] {
            XCTAssertFalse(scope.contains(directory: try directory(path)), path)
        }
    }

    func testParentTraversalCannotEscapeAnAllowedRoot() throws {
        _ = try directory("Library/Mobile Documents/com~apple~CloudDocs")
        _ = try directory("Library/CloudStorage/OneDrive-Personal")
        _ = try directory("Documents")
        let escapedICloud = URL(fileURLWithPath: homeDirectory.path + "/Library/Mobile Documents/../../Documents", isDirectory: true)
        let escapedOneDrive = URL(fileURLWithPath: homeDirectory.path + "/Library/CloudStorage/OneDrive-Personal/../../../Documents", isDirectory: true)
        XCTAssertFalse(scope.contains(directory: escapedICloud))
        XCTAssertFalse(scope.contains(directory: escapedOneDrive))
    }

    func testSymbolicLinksIntoTheCloudAreAllowedAndLinksOutAreRejected() throws {
        let cloud = try directory("Library/CloudStorage/OneDrive-Personal")
        let iCloud = try directory("Library/Mobile Documents/com~apple~CloudDocs")
        let outside = try directory("Documents/Local")
        for (name, destination) in [("OneDriveAlias", cloud), ("ICloudAlias", iCloud)] {
            let link = homeDirectory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
            XCTAssertTrue(scope.contains(directory: link), name)
        }
        for root in [cloud, iCloud] {
            let link = root.appendingPathComponent("LocalAlias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            XCTAssertFalse(scope.contains(directory: link), root.lastPathComponent)
        }
    }

    func testDocumentURLRequiresAFileURLAndPreservesEncodedDirectoryNames() throws {
        for value in [nil, "", "not a URL", "https://example.com/OneDrive", "smb://server/OneDrive",
                      "file://server/Library/CloudStorage/OneDrive-Personal"] as [String?] {
            XCTAssertNil(FinderFallbackScope.directoryURL(fromDocument: value), value ?? "nil")
        }
        let directory = try directory("Library/CloudStorage/OneDrive-企业/带 空格 # 目录")
        let decoded = try XCTUnwrap(FinderFallbackScope.directoryURL(fromDocument: directory.absoluteString))
        XCTAssertEqual(decoded.path, directory.path)
        XCTAssertTrue(scope.contains(directory: decoded))
        XCTAssertFalse(scope.contains(directory: try XCTUnwrap(URL(string: "https://example.com/OneDrive"))))
    }

    func testLocalMouseEventsPassThroughAndCloudMouseUpIsConsumedAfterLeavingScope() throws {
        let localDirectory = try directory("Documents")
        let cloudDirectory = try directory("Library/CloudStorage/OneDrive-Personal")
        var config = AppConfiguration()
        config.fallbackShortcut = true
        config.fallbackMiddleClick = true
        for (down, up, flags, button) in [(CGEventType.rightMouseDown, CGEventType.rightMouseUp, CGEventFlags.maskAlternate, Int64(1)),
                                          (CGEventType.otherMouseDown, CGEventType.otherMouseUp, CGEventFlags(), Int64(2))] {
            var policy = FinderFallbackTriggerState(settings: FinderFallbackTriggerSettings(config))
            XCTAssertEqual(policy.handle(type: down, flags: flags, button: button,
                                         isAllowed: scope.contains(directory: localDirectory)), .passThrough)
            XCTAssertEqual(policy.handle(type: up, flags: [], button: button,
                                         isAllowed: scope.contains(directory: localDirectory)), .passThrough)
            XCTAssertEqual(policy.handle(type: down, flags: flags, button: button,
                                         isAllowed: scope.contains(directory: cloudDirectory)), .trigger)
            XCTAssertEqual(policy.handle(type: up, flags: [], button: button,
                                         isAllowed: scope.contains(directory: localDirectory)), .consume)
            XCTAssertEqual(policy.handle(type: up, flags: [], button: button,
                                         isAllowed: scope.contains(directory: localDirectory)), .passThrough)
        }
    }
}

@MainActor
final class FinderFallbackPermissionSettingsTests: XCTestCase {
    private var directory: URL!
    private var controller: SettingsWindowController?
    private var originalLanguage = ""
    private let triggers: [(id: String, flag: WritableKeyPath<AppConfiguration, Bool>)] = [
        ("fallbackShortcut", \.fallbackShortcut),
        ("fallbackMiddleClick", \.fallbackMiddleClick),
        ("fallbackThreeFingerTap", \.fallbackThreeFingerTap)
    ]

    override func setUpWithError() throws {
        originalLanguage = AppLocalization.languageCode
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-FallbackPermission-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        controller?.window?.close(); controller = nil
        try? FileManager.default.removeItem(at: directory)
        AppLocalization.languageCode = originalLanguage
    }

    private func configuration(enabled: Bool = false) -> AppConfiguration {
        var config = AppConfiguration()
        config.languageCode = "zh-Hans"
        config.fallbackModifier = .command
        config.showStatusItem = false
        config.operations = [.init(name: "Keep my action name", parameters: .tool(.init(action: .copyPath)))]
        for trigger in triggers { config[keyPath: trigger.flag] = enabled }
        return config
    }

    private func makeStore(_ config: AppConfiguration) -> (ConfigurationStore, URL) {
        let storage = directory.appendingPathComponent("settings-" + UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(directory: storage)
        store.replace(config)
        XCTAssertNil(store.lastError)
        return (store, storage)
    }

    private func makeController(store: ConfigurationStore, hasPermission: @escaping () -> Bool,
                                requestPermission: @escaping () -> Void) {
        controller = SettingsWindowController(store: store,
            hasAccessibilityPermission: hasPermission, requestAccessibilityPermission: requestPermission)
        controller?.selectPage(SettingsPage.general.rawValue)
        controller?.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(controller?.window?.isVisible ?? true)
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func checkbox(_ identifier: String) throws -> ClosureCheck {
        let root = try XCTUnwrap(controller?.window?.contentView)
        let matches = descendants(ClosureCheck.self, in: root).filter { $0.identifier?.rawValue == identifier }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    private func assertConfiguration(_ store: ConfigurationStore, storage: URL, equals expected: AppConfiguration,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(store.configuration, expected, file: file, line: line)
        XCTAssertEqual(ConfigurationStore(directory: storage).configuration, expected, file: file, line: line)
        for trigger in triggers {
            XCTAssertEqual(try checkbox(trigger.id).state, expected[keyPath: trigger.flag] ? .on : .off,
                           trigger.id, file: file, line: line)
        }
    }

    func testDeniedClicksRestoreEachCheckboxBeforeRequestAndNeverPersistEnabled() throws {
        let initial = configuration()
        let (store, storage) = makeStore(initial)
        var requestCount = 0
        var requestedControl: ClosureCheck?
        makeController(store: store, hasPermission: { false }, requestPermission: {
            requestCount += 1
            XCTAssertEqual(requestedControl?.state, NSControl.StateValue.off,
                           "The checkbox must be off before the permission request opens.")
            XCTAssertEqual(store.configuration, initial)
        })
        for (index, trigger) in triggers.enumerated() {
            let control = try checkbox(trigger.id)
            requestedControl = control
            control.performClick(nil)
            XCTAssertEqual(requestCount, index + 1)
            assertConfiguration(store, storage: storage, equals: initial)
        }
    }

    func testTrustedCheckboxesToggleIndependentlyWithoutRequestingPermission() throws {
        let initial = configuration()
        let (store, storage) = makeStore(initial)
        var requestCount = 0
        makeController(store: store, hasPermission: { true }, requestPermission: { requestCount += 1 })
        var expected = initial
        for enabled in [true, false] {
            for trigger in triggers {
                try checkbox(trigger.id).performClick(nil)
                expected[keyPath: trigger.flag] = enabled
                assertConfiguration(store, storage: storage, equals: expected)
            }
        }
        XCTAssertEqual(requestCount, 0)
    }

    func testPermissionGrantedDuringRequestEnablesOnlyTheRequestedCheckbox() throws {
        let initial = configuration()
        let (store, storage) = makeStore(initial)
        var granted = false
        var requestCount = 0
        var requestedControl: ClosureCheck?
        makeController(store: store, hasPermission: { granted }, requestPermission: {
            requestCount += 1
            XCTAssertEqual(requestedControl?.state, NSControl.StateValue.off)
            granted = true
        })
        requestedControl = try checkbox("fallbackMiddleClick")
        requestedControl?.performClick(nil)
        var expected = initial
        expected.fallbackMiddleClick = true
        assertConfiguration(store, storage: storage, equals: expected)
        XCTAssertEqual(requestCount, 1)
    }

    func testPreviouslyEnabledCheckboxesWithoutPermissionAreClearedInOneCommit() throws {
        let initial = configuration(enabled: true)
        let (store, storage) = makeStore(initial)
        let changes = FallbackPermissionChangeCounter()
        let storeID = ObjectIdentifier(store)
        let observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged, object: nil, queue: nil) { note in
            if let changedStore = note.object as? ConfigurationStore, ObjectIdentifier(changedStore) == storeID { changes.increment() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var requestCount = 0
        makeController(store: store, hasPermission: { false }, requestPermission: { requestCount += 1 })
        var expected = initial
        for trigger in triggers { expected[keyPath: trigger.flag] = false }
        assertConfiguration(store, storage: storage, equals: expected)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(requestCount, 0, "Loading settings must not request system authorization.")
    }

    func testReturningAfterPermissionRevocationClearsAllEnabledCheckboxesInOneCommit() throws {
        let initial = configuration(enabled: true)
        let (store, storage) = makeStore(initial)
        var granted = true
        var requestCount = 0
        makeController(store: store, hasPermission: { granted }, requestPermission: { requestCount += 1 })
        assertConfiguration(store, storage: storage, equals: initial)
        let changes = FallbackPermissionChangeCounter()
        let storeID = ObjectIdentifier(store)
        let observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged, object: nil, queue: nil) { note in
            if let changedStore = note.object as? ConfigurationStore, ObjectIdentifier(changedStore) == storeID { changes.increment() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        granted = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        var expected = initial
        for trigger in triggers { expected[keyPath: trigger.flag] = false }
        assertConfiguration(store, storage: storage, equals: expected)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(requestCount, 0)
    }

    func testReturningAfterGrantDoesNotEnableDeniedChoiceUntilClickedAgain() throws {
        let initial = configuration()
        let (store, storage) = makeStore(initial)
        var granted = false
        var requestCount = 0
        makeController(store: store, hasPermission: { granted }, requestPermission: { requestCount += 1 })
        try checkbox("fallbackThreeFingerTap").performClick(nil)
        XCTAssertEqual(requestCount, 1)
        assertConfiguration(store, storage: storage, equals: initial)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        assertConfiguration(store, storage: storage, equals: initial)
        granted = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        assertConfiguration(store, storage: storage, equals: initial)
        try checkbox("fallbackThreeFingerTap").performClick(nil)
        var expected = initial
        expected.fallbackThreeFingerTap = true
        assertConfiguration(store, storage: storage, equals: expected)
        XCTAssertEqual(requestCount, 1)
    }
}

private final class FallbackPermissionChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
