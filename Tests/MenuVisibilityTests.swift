import AppKit
import XCTest
@testable import Crab

@MainActor
final class MenuVisibilityTests: XCTestCase {
    private var directory: URL!
    private var language = ""

    override func setUpWithError() throws {
        language = AppLocalization.languageCode
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-MenuVisibility-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        AppLocalization.languageCode = language
        try? FileManager.default.removeItem(at: directory)
    }

    private func context() -> OperationContext {
        .init(urls: [directory.appendingPathComponent("sample.txt")], directory: directory)
    }

    private func fixture() -> (AppConfiguration, String, String, String, String) {
        let repeated = OperationRecord(id: "repeated", name: "Repeated", parameters: .tool(.init(action: .copyPath)))
        let other = OperationRecord(id: "other", name: "Other", parameters: .tool(.init(action: .copyName)))
        var root = MenuNode.reference(repeated.id); root.name = "Root reference"
        var child = MenuNode.reference(repeated.id); child.name = "Child reference"
        var sibling = MenuNode.reference(other.id); sibling.name = "Sibling reference"
        let group = MenuNode(kind: .group, name: "Group", children: [child, sibling])
        var config = AppConfiguration(); config.operations = [repeated, other]; config.menu = [root, group]
        return (config, root.id, group.id, child.id, sibling.id)
    }

    private func assertMenu(_ config: AppConfiguration, rootIDs: [String], childIDs: [String],
                            file: StaticString = #filePath, line: UInt = #line) {
        let planned = MenuPlanner.items(configuration: config, context: context())
        XCTAssertEqual(planned.map { $0.node.id }, rootIDs, file: file, line: line)
        XCTAssertEqual(planned.flatMap(\.children).map { $0.node.id }, childIDs, file: file, line: line)
        let menu = ContextMenuBuilder(configuration: config, handler: { _ in }).menu(selectedURLs: context().urls, directory: directory)
        XCTAssertEqual(menu.items.map(\.title), planned.map(\.title), file: file, line: line)
        XCTAssertEqual(menu.items.flatMap { $0.submenu?.items ?? [] }.map(\.title), planned.flatMap(\.children).map(\.title), file: file, line: line)
    }

    func testRootChildAndGroupVisibilityStayIndependentAcrossHidingAndRestoring() throws {
        let (config, rootID, groupID, childID, siblingID) = fixture()
        let location = directory.appendingPathComponent("master")
        let store = ConfigurationStore(directory: location)
        XCTAssertTrue(store.replace(config))
        assertMenu(store.configuration, rootIDs: [rootID, groupID], childIDs: [childID, siblingID])

        XCTAssertTrue(store.update { $0.updateMenuNode(childID) { $0.visible = false } })
        assertMenu(store.configuration, rootIDs: [rootID, groupID], childIDs: [siblingID])
        XCTAssertEqual(store.configuration.menuNode(rootID)?.visible, true)

        XCTAssertTrue(store.update { $0.updateMenuNode(groupID) { $0.visible = false } })
        assertMenu(store.configuration, rootIDs: [rootID], childIDs: [])
        XCTAssertEqual(store.configuration.menuNode(childID)?.visible, false)
        XCTAssertEqual(store.configuration.menuNode(siblingID)?.visible, true)
        XCTAssertEqual(ConfigurationStore(directory: location).configuration.menu, store.configuration.menu)

        XCTAssertTrue(store.update { $0.updateMenuNode(groupID) { $0.visible = true } })
        assertMenu(store.configuration, rootIDs: [rootID, groupID], childIDs: [siblingID])
        XCTAssertTrue(store.update { $0.updateMenuNode(rootID) { $0.visible = false } })
        assertMenu(store.configuration, rootIDs: [groupID], childIDs: [siblingID])
        XCTAssertTrue(store.update { $0.updateMenuNode(childID) { $0.visible = true } })
        assertMenu(store.configuration, rootIDs: [groupID], childIDs: [childID, siblingID])
        XCTAssertTrue(store.update { $0.updateMenuNode(rootID) { $0.visible = true } })
        assertMenu(store.configuration, rootIDs: [rootID, groupID], childIDs: [childID, siblingID])
        XCTAssertEqual(store.configuration, config)
    }

    func testBroadcastCacheBuildsOnlyVisibleReferencesAndRetainsChildFlagsWhenGroupIsHidden() throws {
        let channel = Notification.Name("dev.crab.tests.menu-visibility." + UUID().uuidString)
        let source = ConfigurationStore(directory: directory.appendingPathComponent("source"), notificationName: channel)
        let cacheLocation = directory.appendingPathComponent("finder-cache")
        let cache = ConfigurationStore(directory: cacheLocation, notificationName: channel, cacheReceivedConfiguration: true)
        let (config, rootID, groupID, childID, siblingID) = fixture()
        XCTAssertTrue(source.replace(config))

        func waitForCache(file: StaticString = #filePath, line: UInt = #line) {
            let deadline = Date().addingTimeInterval(5)
            while cache.configuration.menu != source.configuration.menu, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertEqual(cache.configuration.menu, source.configuration.menu, file: file, line: line)
            XCTAssertEqual(cache.configuration.operations, source.configuration.operations, file: file, line: line)
        }
        waitForCache()
        assertMenu(cache.configuration, rootIDs: [rootID, groupID], childIDs: [childID, siblingID])
        XCTAssertEqual(MenuPlanner.items(configuration: cache.configuration, context: context(), allowFileRead: false).map { $0.node.id }, [rootID, groupID])

        XCTAssertTrue(source.update {
            $0.updateMenuNode(rootID) { $0.visible = false }
            $0.updateMenuNode(childID) { $0.visible = false }
        })
        waitForCache()
        assertMenu(cache.configuration, rootIDs: [groupID], childIDs: [siblingID])
        XCTAssertTrue(source.update { $0.updateMenuNode(groupID) { $0.visible = false } })
        waitForCache()
        assertMenu(cache.configuration, rootIDs: [], childIDs: [])
        XCTAssertEqual(cache.configuration.menuNode(childID)?.visible, false)
        XCTAssertEqual(cache.configuration.menuNode(siblingID)?.visible, true)

        XCTAssertTrue(source.update { $0.updateMenuNode(groupID) { $0.visible = true } })
        waitForCache()
        assertMenu(cache.configuration, rootIDs: [groupID], childIDs: [siblingID])
        let persistedCache = ConfigurationStore(directory: cacheLocation, cacheReceivedConfiguration: true)
        XCTAssertEqual(persistedCache.configuration.menu, cache.configuration.menu)
        XCTAssertTrue(source.configuration.previews.isEmpty)
    }
}
