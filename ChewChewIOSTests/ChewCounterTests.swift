import XCTest
@testable import ChewChewIOS

final class ChewCounterTests: XCTestCase {
    func testFeedReturnsDetectionEventWhenPeakIsCounted() async {
        let counter = ChewCounter()
        var events: [ChewDetectionEvent] = []

        for index in 0..<500 {
            if let event = await counter.feed(
                rotX: 0,
                rotY: chewingRotationY(index: index),
                rotZ: 0,
                accelX: 0,
                accelY: 0,
                accelZ: 0
            ) {
                events.append(event)
            }
        }

        let snapshot = await counter.snapshot()

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.last?.count, snapshot.chewCount)
        XCTAssertEqual(events.map(\.count), Array(1...events.count))
        XCTAssertEqual(events.map(\.timestamp), snapshot.chewTimestamps)
        XCTAssertEqual(events.map(\.amplitude), snapshot.chewAmplitudes)
    }

    func testFeedDoesNotReturnDetectionEventForFlatMotion() async {
        let counter = ChewCounter()
        var events: [ChewDetectionEvent] = []

        for _ in 0..<500 {
            if let event = await counter.feed(
                rotX: 0,
                rotY: 0,
                rotZ: 0,
                accelX: 0,
                accelY: 0,
                accelZ: 0
            ) {
                events.append(event)
            }
        }

        let snapshot = await counter.snapshot()

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(snapshot.chewCount, 0)
        XCTAssertTrue(snapshot.chewTimestamps.isEmpty)
        XCTAssertTrue(snapshot.chewAmplitudes.isEmpty)
    }

    private func chewingRotationY(index: Int) -> Double {
        let elapsed = Double(index) / 50.0
        return 0.08 * sin(2 * Double.pi * 1.4 * elapsed)
    }
}
