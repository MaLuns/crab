import XCTest
@testable import Crab

final class ThreeFingerMonitorTests: XCTestCase {
    func testThreeFingerTapFiresOnceOnlyAfterRelease() {
        var recognizer = ThreeFingerTapRecognizer()
        XCTAssertFalse(recognizer.consume(frame(0, fingers(3))))
        XCTAssertFalse(recognizer.consume(frame(0.06, fingers(3, shift: 0.003))))
        XCTAssertTrue(recognizer.consume(frame(0.10, fingers(3, state: 5))))
        XCTAssertFalse(recognizer.consume(frame(0.11, fingers(3, state: 7))))
        XCTAssertFalse(recognizer.consume(frame(0.12, [])))
    }

    func testStaggeredLandingAndReleaseStillRecognizesOneTap() {
        var recognizer = ThreeFingerTapRecognizer()
        XCTAssertFalse(recognizer.consume(frame(0, fingers(1))))
        XCTAssertFalse(recognizer.consume(frame(0.02, fingers(2))))
        XCTAssertFalse(recognizer.consume(frame(0.04, fingers(3))))
        XCTAssertFalse(recognizer.consume(frame(0.07, fingers(2))))
        XCTAssertTrue(recognizer.consume(frame(0.10, [])))
    }

    func testOneTwoAndFourFingersNeverTrigger() {
        for count in [1, 2, 4, 5] {
            var recognizer = ThreeFingerTapRecognizer()
            XCTAssertFalse(recognizer.consume(frame(0, fingers(count))))
            XCTAssertFalse(recognizer.consume(frame(0.1, [])), "count=\(count)")
        }
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.consume(frame(0, fingers(3)))
        _ = recognizer.consume(frame(0.04, fingers(4)))
        _ = recognizer.consume(frame(0.06, fingers(3)))
        XCTAssertFalse(recognizer.consume(frame(0.1, [])))
    }

    func testSwipeLongPressLateLandingAndSlowReleaseAreRejected() {
        var swipe = ThreeFingerTapRecognizer()
        _ = swipe.consume(frame(0, fingers(3))); _ = swipe.consume(frame(0.05, fingers(3, shift: 0.1)))
        XCTAssertFalse(swipe.consume(frame(0.1, [])))
        var hold = ThreeFingerTapRecognizer()
        for time in [0.0, 0.10, 0.20, 0.31] { _ = hold.consume(frame(time, fingers(3))) }
        XCTAssertFalse(hold.consume(frame(0.32, [])))
        var late = ThreeFingerTapRecognizer()
        _ = late.consume(frame(0, fingers(1))); _ = late.consume(frame(0.15, fingers(3)))
        XCTAssertFalse(late.consume(frame(0.20, [])))
        var release = ThreeFingerTapRecognizer()
        _ = release.consume(frame(0, fingers(3))); _ = release.consume(frame(0.05, fingers(2)))
        XCTAssertFalse(release.consume(frame(0.19, [])))
    }

    func testHoverAndSequentialNonoverlappingFingersAreRejected() {
        var hover = ThreeFingerTapRecognizer()
        _ = hover.consume(frame(0, fingers(3, state: 2)))
        XCTAssertFalse(hover.consume(frame(0.1, fingers(3, state: 7))))
        var sequential = ThreeFingerTapRecognizer()
        _ = sequential.consume(frame(0, fingers(2)))
        _ = sequential.consume(frame(0.04, Array(fingers(3).suffix(2))))
        XCTAssertFalse(sequential.consume(frame(0.1, [])))
    }

    func testPhysicalClickInvalidationAndNextTapAfterIdle() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.consume(frame(0, fingers(3)))
        recognizer.invalidateCurrentGesture()
        XCTAssertFalse(recognizer.consume(frame(0.1, [])))
        XCTAssertFalse(recognizer.consume(frame(2, fingers(3))))
        XCTAssertTrue(recognizer.consume(frame(2.1, [])))
        XCTAssertFalse(recognizer.consume(frame(5, fingers(3))))
        XCTAssertTrue(recognizer.consume(frame(5.1, [])))
    }

    func testTimestampGapsNonfiniteInputAndReplacedFingerRejectGesture() {
        var gap = ThreeFingerTapRecognizer()
        _ = gap.consume(frame(0, fingers(3)))
        XCTAssertFalse(gap.consume(frame(0.25, [])))
        var replaced = ThreeFingerTapRecognizer()
        _ = replaced.consume(frame(0, fingers(3)))
        var contacts = fingers(3); contacts[2] = ThreeFingerContact(id: 44, state: 4, x: 0.5, y: 0.4)
        _ = replaced.consume(frame(0.04, contacts))
        XCTAssertFalse(replaced.consume(frame(0.1, [])))
        var invalid = ThreeFingerTapRecognizer()
        _ = invalid.consume(frame(0, fingers(3)))
        XCTAssertFalse(invalid.consume(frame(.nan, [])))
        XCTAssertFalse(invalid.consume(frame(0.1, [])))
    }

    func testContactDecoderUsesVerified96ByteLayoutAndRejectsInvalidBuffers() throws {
        var bytes = Data(count: 3 * ThreeFingerFrameDecoder.contactStride)
        for index in 0..<3 {
            let offset = index * 96
            put(Int32(101 + index), at: offset + 16, in: &bytes)
            put(Int32(4), at: offset + 20, in: &bytes)
            put(Float(0.2 + Double(index) * 0.2), at: offset + 32, in: &bytes)
            put(Float(0.4), at: offset + 36, in: &bytes)
        }
        let decoded = try XCTUnwrap(bytes.withUnsafeBytes { ThreeFingerFrameDecoder.decode($0, count: 3, timestamp: 10) })
        XCTAssertEqual(decoded.contacts.map(\.id), [101, 102, 103])
        XCTAssertTrue(decoded.contacts.allSatisfy(\.isTouching))
        XCTAssertEqual(decoded.contacts[2].x, 0.6, accuracy: 0.00001)
        XCTAssertNil(bytes.withUnsafeBytes { ThreeFingerFrameDecoder.decode($0, count: 4, timestamp: 10) })
        XCTAssertNil(bytes.withUnsafeBytes { ThreeFingerFrameDecoder.decode($0, count: -1, timestamp: 10) })
        put(Int32(9), at: 20, in: &bytes)
        XCTAssertNil(bytes.withUnsafeBytes { ThreeFingerFrameDecoder.decode($0, count: 3, timestamp: 10) })
        put(Int32(4), at: 20, in: &bytes); put(Float.nan, at: 32, in: &bytes)
        XCTAssertNil(bytes.withUnsafeBytes { ThreeFingerFrameDecoder.decode($0, count: 3, timestamp: 10) })
    }

    private func fingers(_ count: Int, state: Int32 = 4, shift: Double = 0) -> [ThreeFingerContact] {
        (0..<count).map { ThreeFingerContact(id: Int32($0 + 1), state: state, x: 0.2 + Double($0) * 0.15 + shift, y: 0.4) }
    }
    private func frame(_ time: Double, _ contacts: [ThreeFingerContact]) -> ThreeFingerFrame { ThreeFingerFrame(timestamp: time, contacts: contacts) }
    private func put<T>(_ value: T, at offset: Int, in data: inout Data) {
        var value = value
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }
}
