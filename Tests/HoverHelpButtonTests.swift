import AppKit
import XCTest
@testable import Crab

@MainActor
final class HoverHelpButtonTests: XCTestCase {
    private func waitForHoverTimer() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { continuation.resume() }
        }
    }
    func testPassingOverButtonDoesNotOpenHelp() async {
        var openings = 0
        let hover = HelpHoverCoordinator(showDelay: 0.01, hideDelay: 0.01, show: { openings += 1; return true }, hide: {})
        hover.enterButton(); hover.exitButton()
        await waitForHoverTimer()
        XCTAssertEqual(openings, 0)
    }
    func testPointerCanMoveIntoHelpBeforeItCloses() async {
        var openings = 0, closings = 0
        let hover = HelpHoverCoordinator(showDelay: 0.01, hideDelay: 0.01, show: { openings += 1; return true }, hide: { closings += 1 })
        hover.enterButton(); await waitForHoverTimer()
        XCTAssertEqual(openings, 1)
        hover.exitButton(); hover.enterContent(); await waitForHoverTimer()
        XCTAssertEqual(closings, 0)
        hover.exitContent(); await waitForHoverTimer()
        XCTAssertEqual(closings, 1)
    }
    func testDismissalCancelsPendingTimersAndDoesNotCloseTwice() async {
        var openings = 0, closings = 0
        let hover = HelpHoverCoordinator(showDelay: 0.01, hideDelay: 0.01, show: { openings += 1; return true }, hide: { closings += 1 })
        hover.enterButton(); hover.dismiss(); await waitForHoverTimer()
        XCTAssertEqual(openings, 0)
        hover.openImmediately(); hover.exitButton(); hover.dismiss(); await waitForHoverTimer()
        XCTAssertEqual(openings, 1); XCTAssertEqual(closings, 1)
        hover.presentationClosed(); hover.dismiss()
        XCTAssertEqual(closings, 1)
        hover.openImmediately(); hover.enterContent(); hover.presentationClosed()
        hover.openImmediately(); hover.exitButton(); await waitForHoverTimer()
        XCTAssertEqual(closings, 2)
    }
    func testWrappingHelpContentFitsChineseAndEnglishWithoutTruncation() throws {
        let examples = [
            ("使用范围", "访达扩展会监视本地用户目录；开启外接磁盘后也监视 /Volumes。请在扩展管理中启用 Crab Finder 菜单。"),
            ("Usage scope", "Finder Extension monitors local user folders. When external disks are enabled, /Volumes is monitored too. Enable Crab Finder Menu in Extension Management. " + String(repeating: "This explanation wraps onto the next line without truncating its contents. ", count: 4))
        ]
        for (title, message) in examples {
            let controller = HoverHelpContentController(title: title, message: message)
            let view = controller.view
            view.layoutSubtreeIfNeeded()
            XCTAssertFalse(view.hasAmbiguousLayout)
            XCTAssertEqual(view.frame.width, 332)
            XCTAssertGreaterThan(view.frame.height, 72)
            XCTAssertEqual(controller.preferredContentSize, view.frame.size)
            func labels(in view: NSView) -> [NSTextField] {
                view.subviews.flatMap { child in (child as? NSTextField).map { [$0] } ?? labels(in: child) }
            }
            let fields = labels(in: view)
            XCTAssertEqual(fields.count, 2)
            for field in fields {
                XCTAssertFalse(field.hasAmbiguousLayout)
                XCTAssertEqual(field.maximumNumberOfLines, 0)
                XCTAssertEqual(field.lineBreakMode, .byWordWrapping)
                XCTAssertGreaterThanOrEqual(field.frame.height + 1, field.fittingSize.height)
                XCTAssertEqual(field.alignmentRect(forFrame: field.frame).width, 300)
                XCTAssertTrue(view.bounds.contains(field.convert(field.bounds, to: view)))
            }
        }
    }
    func testDetachedButtonCancelsNativeHoverTrackingAndIsReleased() async throws {
        weak var released: HoverHelpButton?
        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            var button: HoverHelpButton? = HoverHelpButton(title: "使用范围", message: "隐藏验证窗口不会弹出说明。")
            released = button
            button!.frame = NSRect(x: 10, y: 10, width: 22, height: 22)
            window.contentView!.addSubview(button!)
            button!.updateTrackingAreas()
            XCTAssertTrue(button!.trackingAreas.contains { $0.options.contains([.mouseEnteredAndExited, .inVisibleRect]) })
            let event = NSEvent.enterExitEvent(with: .mouseEntered, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            button!.mouseEntered(with: event)
            button!.removeFromSuperview()
            button = nil
        }
        await waitForHoverTimer()
        XCTAssertNil(released)
    }
}
