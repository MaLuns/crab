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
}
