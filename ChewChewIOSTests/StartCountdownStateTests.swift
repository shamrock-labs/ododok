import XCTest
@testable import ChewChewIOS

/// 3-2-1 카운트다운 상태 전이 순수 함수 테스트.
final class StartCountdownStateTests: XCTestCase {

    func testFromThree_returnsTwo() {
        XCTAssertEqual(StartCountdownController.nextCountdownValue(from: 3), 2)
    }

    func testFromTwo_returnsOne() {
        XCTAssertEqual(StartCountdownController.nextCountdownValue(from: 2), 1)
    }

    func testFromOne_returnsNil_meaningFinished() {
        XCTAssertNil(StartCountdownController.nextCountdownValue(from: 1))
    }
}
