import AppKit
import XCTest
@testable import Crab

@MainActor
final class SettingsPageLayoutTests: XCTestCase {
    private var directory: URL!
    private var language = ""
    private var controllers: [SettingsWindowController] = []

    private struct Scene {
        let controller: SettingsWindowController
        let store: ConfigurationStore
        let window: NSWindow
        let root: NSView
        let content: NSView
    }

    override func setUpWithError() throws {
        language = AppLocalization.languageCode
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-SettingsLayout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for controller in controllers { controller.window?.close() }
        controllers = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        AppLocalization.languageCode = language
        try? FileManager.default.removeItem(at: directory)
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

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func find<T: NSView>(_ identifier: String, in root: NSView, as type: T.Type = T.self) throws -> T {
        let matches = descendants(root).compactMap { $0 as? T }.filter { $0.identifier?.rawValue == identifier }
        XCTAssertEqual(matches.count, 1, identifier)
        return try XCTUnwrap(matches.first, identifier)
    }

    private func pump(until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func makeScene(language: String,
                           load: ((@escaping ([AppPermissionStatus]) -> Void) -> Void)? = nil) throws -> Scene {
        let location = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(directory: location)
        let copy = OperationRecord(id: "layout.copy", name: "示例文件操作", parameters: .tool(.init(action: .copyPath)))
        let folder = OperationRecord(id: "layout.directory", name: "示例目录", parameters: .directory(directory.path))
        let group = MenuNode(id: "layout.group", kind: .group, name: "示例分组", children: [.reference(copy.id)])
        XCTAssertTrue(store.update {
            $0.operations = [copy, folder]
            $0.menu = [group, .reference(folder.id)]
            $0.languageCode = language
        })
        let statuses = fixture
        let controller = SettingsWindowController(store: store,
            hasAccessibilityPermission: { true },
            requestAccessibilityPermission: { XCTFail("Layout verification must not request Accessibility permission.") },
            loadPermissionStatuses: load ?? { $0(statuses) },
            requestPermission: { _, _ in XCTFail("Layout verification must not request system authorization.") },
            openPermissionSettings: { _ in XCTFail("Layout verification must not open System Settings.") })
        controllers.append(controller)
        let window = try XCTUnwrap(controller.window)
        window.animationBehavior = .none; window.orderFront(nil)
        let root = try XCTUnwrap(window.contentView)
        let content: NSView = try find("settings-content", in: root)
        root.layoutSubtreeIfNeeded()
        return Scene(controller: controller, store: store, window: window, root: root, content: content)
    }

    private func assertHorizontalMargins(_ rect: NSRect, content: NSView, message: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, 40, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(rect.width, 620, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(content.bounds.maxX - rect.maxX, 40, accuracy: 0.5, message, file: file, line: line)
    }

    @discardableResult
    private func assertPageTitle(_ page: SettingsPage, scene: Scene, language: String) throws -> NSTextField {
        let title: NSTextField = try find("settings-page-title", in: scene.content)
        XCTAssertEqual(title.stringValue, L(page.rawValue), language)
        XCTAssertEqual(title.font, NSFont.systemFont(ofSize: 22, weight: .semibold), language)
        let rect = title.convert(title.bounds, to: scene.content)
        assertHorizontalMargins(rect, content: scene.content, message: language + "/" + page.rawValue + " title")
        XCTAssertEqual(rect.minY, 24, accuracy: 0.5, language + "/" + page.rawValue)
        XCTAssertEqual(rect.height, 32, accuracy: 0.5, language + "/" + page.rawValue)
        return title
    }

    func testAllNineLanguagesShareTitleTypographyAndFortyPointContentMarginsOnEveryPage() throws {
        for entry in AppLocalization.supportedLanguages where !entry.code.isEmpty {
            let scene = try makeScene(language: entry.code)
            let original = scene.store.configuration
            for page in SettingsPage.allCases {
                scene.controller.selectPage(page.rawValue)
                scene.root.layoutSubtreeIfNeeded()
                _ = try assertPageTitle(page, scene: scene, language: entry.code)
                switch page {
                case .library:
                    let toolbar: NSView = try find("library-toolbar", in: scene.content)
                    assertHorizontalMargins(toolbar.convert(toolbar.bounds, to: scene.content), content: scene.content,
                                            message: entry.code + "/library toolbar")
                    let collection = try XCTUnwrap(descendants(scene.content).compactMap { $0 as? NSCollectionView }.first)
                    let scroll = try XCTUnwrap(collection.enclosingScrollView)
                    for style in [NSScroller.Style.legacy, .overlay, .legacy] {
                        scroll.scrollerStyle = style
                        scene.root.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
                        pump {
                            guard let item = collection.visibleItems().first else { return false }
                            return abs(item.view.convert(item.view.bounds, to: scene.content).minX - 40) < 0.5
                        }
                        for item in collection.visibleItems() {
                            assertHorizontalMargins(item.view.convert(item.view.bounds, to: scene.content), content: scene.content,
                                                    message: entry.code + "/visible library card/" + String(style.rawValue))
                        }
                    }
                case .menu:
                    let left: ReferenceMaterialCard = try find("menu-primary-panel", in: scene.content)
                    let right: ReferenceMaterialCard = try find("menu-secondary-panel", in: scene.content)
                    let leftRect = left.convert(left.bounds, to: scene.content)
                    let rightRect = right.convert(right.bounds, to: scene.content)
                    XCTAssertEqual(leftRect.width, 300, accuracy: 0.5, entry.code)
                    XCTAssertEqual(rightRect.width, 300, accuracy: 0.5, entry.code)
                    XCTAssertEqual(rightRect.minX - leftRect.maxX, 20, accuracy: 0.5, entry.code)
                    assertHorizontalMargins(leftRect.union(rightRect), content: scene.content,
                                            message: entry.code + "/menu columns")
                case .general:
                    let scroll: NSScrollView = try find("general-scroll", in: scene.content)
                    XCTAssertEqual(scroll.frame.minY, 72, accuracy: 0.5, entry.code)
                    XCTAssertEqual(scroll.frame.height, 628, accuracy: 0.5, entry.code)
                    for identifier in ["general-launch-card", "general-cloud-card", "general-permissions-card"] {
                        let card: ReferenceMaterialCard = try find(identifier, in: scene.content)
                        assertHorizontalMargins(card.convert(card.bounds, to: scene.content), content: scene.content,
                                                message: entry.code + "/" + identifier)
                    }
                }
            }
            XCTAssertEqual(scene.store.configuration, original)
            scene.window.close()
        }
    }

    private func assertGeneralSectionsDoNotOverlap(scene: Scene) throws {
        let scroll: NSScrollView = try find("general-scroll", in: scene.content)
        let document = try XCTUnwrap(scroll.documentView)
        let identifiers = ["general-heading-launch", "general-launch-card", "general-heading-cloud", "general-cloud-card",
                           "general-heading-permissions", "general-permissions-card"]
        let frames = try identifiers.map { identifier -> NSRect in
            let view: NSView = try find(identifier, in: document)
            return view.convert(view.bounds, to: document)
        }
        for index in 1..<frames.count {
            XCTAssertGreaterThanOrEqual(frames[index].minY, frames[index - 1].maxY, identifiers[index])
        }
        let permissions: ReferenceMaterialCard = try find("general-permissions-card", in: document)
        let list: SettingsPermissionsView = try find("permission-list", in: permissions)
        XCTAssertTrue(permissions.bounds.contains(list.frame))
        let rows = descendants(list).filter { $0.identifier?.rawValue.hasPrefix("permission-row-") == true }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertFalse(rows.isEmpty)
        for row in rows { XCTAssertTrue(list.bounds.contains(row.frame), row.identifier?.rawValue ?? "permission row") }
        for index in rows.indices.dropFirst() { XCTAssertGreaterThanOrEqual(rows[index].frame.minY, rows[index - 1].frame.maxY) }
    }

    func testGeneralTitleStaysFixedWhileItsDocumentScrollsAndPermissionsRefreshAsynchronously() throws {
        var pending: [([AppPermissionStatus]) -> Void] = []
        let scene = try makeScene(language: "zh-Hans", load: { pending.append($0) })
        let original = scene.store.configuration
        scene.controller.selectPage(SettingsPage.general.rawValue)
        scene.root.layoutSubtreeIfNeeded()
        let title = try assertPageTitle(.general, scene: scene, language: "zh-Hans")
        let titleBefore = title.convert(title.bounds, to: scene.root)
        let scroll: NSScrollView = try find("general-scroll", in: scene.content)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertFalse(title.isDescendant(of: document))
        let launch: NSView = try find("general-heading-launch", in: document)
        let launchBefore = launch.convert(launch.bounds, to: scene.content)
        let maximum = document.bounds.height - scroll.contentView.bounds.height
        XCTAssertGreaterThan(maximum, 20)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(140, maximum)))
        scroll.reflectScrolledClipView(scroll.contentView)
        scene.root.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 20)
        XCTAssertLessThan(launch.convert(launch.bounds, to: scene.content).minY, launchBefore.minY - 20)
        XCTAssertEqual(title.convert(title.bounds, to: scene.root), titleBefore)
        XCTAssertTrue(title.visibleRect.contains(title.bounds))
        try assertGeneralSectionsDoNotOverlap(scene: scene)

        let initialCompletion = try XCTUnwrap(pending.first)
        pending.removeFirst()
        let statuses = fixture
        DispatchQueue.global(qos: .userInitiated).async { initialCompletion(statuses) }
        pump { self.descendants(scene.content).contains { $0.identifier?.rawValue == "permission-status-iTermAutomation" } }
        scene.root.layoutSubtreeIfNeeded()
        XCTAssertEqual(title.convert(title.bounds, to: scene.root), titleBefore)
        XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 0)
        try assertGeneralSectionsDoNotOverlap(scene: scene)

        let refresh: NSButton = try find("permission-refresh", in: scene.content)
        XCTAssertTrue(refresh.isEnabled)
        refresh.performClick(nil)
        pump { !pending.isEmpty }
        XCTAssertEqual(title.convert(title.bounds, to: scene.root), titleBefore)
        try assertGeneralSectionsDoNotOverlap(scene: scene)
        let refreshedCompletion = pending.removeFirst()
        var refreshed = statuses
        refreshed[1] = .init(permission: .inputMonitoring, state: .authorized)
        let finalStatuses = refreshed
        DispatchQueue.global(qos: .userInitiated).async { refreshedCompletion(finalStatuses) }
        pump {
            (self.descendants(scene.content).first { $0.identifier?.rawValue == "permission-status-inputMonitoring" } as? NSTextField)?.stringValue == L("已授权")
        }
        scene.root.layoutSubtreeIfNeeded()
        XCTAssertEqual(title.convert(title.bounds, to: scene.root), titleBefore)
        XCTAssertTrue(title.visibleRect.contains(title.bounds))
        try assertGeneralSectionsDoNotOverlap(scene: scene)
        XCTAssertEqual(scene.store.configuration, original)
    }
}
