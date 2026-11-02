import AppKit
import XCTest
@testable import Crab

@MainActor
final class StatusBarPresentationTests: XCTestCase {
    private final class SettingsTarget: NSObject {
        var openCount = 0
        var quitCount = 0
        @objc func openSettings() { openCount += 1 }
        @objc func quit() { quitCount += 1 }
    }

    func testEveryLanguageOffersOnlyWorkingSettingsAndQuitCommands() {
        let originalLanguage = AppLocalization.languageCode
        defer { AppLocalization.languageCode = originalLanguage }
        let target = SettingsTarget()
        let action = #selector(SettingsTarget.openSettings)
        let quitAction = #selector(SettingsTarget.quit)
        for language in AppLocalization.supportedLanguages where !language.code.isEmpty {
            AppLocalization.languageCode = language.code
            let menu = StatusBarPresentation.menu(target: target, settingsAction: action, quitAction: quitAction)
            menu.update()
            XCTAssertEqual(menu.items.map(\.title), [L("通用设置"), L("退出")], language.code)
            XCTAssertEqual(menu.items.count, 2)
            XCTAssertFalse(menu.items.contains { $0.isSeparatorItem || $0.submenu != nil })
            guard menu.items.count == 2 else { continue }
            XCTAssertTrue(menu.items[0].target === target)
            XCTAssertEqual(menu.items[0].action, action)
            XCTAssertEqual(menu.items[0].keyEquivalent, ",")
            XCTAssertTrue(menu.items[1].target === target)
            XCTAssertEqual(menu.items[1].action, quitAction)
            XCTAssertNotEqual(menu.items[1].action, #selector(NSApplication.terminate(_:)))
            XCTAssertNil(menu.items[1].image)
            XCTAssertEqual(menu.items[1].keyEquivalent, "q")
            menu.performActionForItem(at: 0)
            menu.performActionForItem(at: 1)
        }
        XCTAssertEqual(target.openCount, 9)
        XCTAssertEqual(target.quitCount, 9)
    }

}
