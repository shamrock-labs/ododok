import XCTest
@testable import ChewChewIOS

/// 3-2-1 카운트다운 상태 전이 순수 함수 테스트.
final class StartCountdownStateTests: XCTestCase {

    func testFromThree_returnsTwo() {
        XCTAssertEqual(AppState.nextCountdownValue(from: 3), 2)
    }

    func testFromTwo_returnsOne() {
        XCTAssertEqual(AppState.nextCountdownValue(from: 2), 1)
    }

    func testFromOne_returnsNil_meaningFinished() {
        XCTAssertNil(AppState.nextCountdownValue(from: 1))
    }
}
