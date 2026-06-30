import XCTest
@testable import ChewChewIOS

/// ODO-99: 초당 isChewing 과반을 '0'/'1'로 굳혀 chewing_timeline 문자열을 만드는 누적기 검증.
/// 서버 chewing_session.chewing_timeline(1초당 1글자, 인덱스=경과 초)과 같은 의미를 산출해야 한다.
final class ChewingTimelineAccumulatorTests: XCTestCase {

    private func feed(_ acc: inout ChewingTimelineAccumulator, chewing: Bool, count: Int) {
        for _ in 0..<count { acc.feed(isChewing: chewing) }
    }

    func testEmpty_returnsNil() {
        let acc = ChewingTimelineAccumulator()
        XCTAssertNil(acc.makeTimeline())
    }

    func testFullSeconds_chewThenRest_mapsToOneZero() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)
        feed(&acc, chewing: false, count: 50)
        XCTAssertEqual(acc.makeTimeline(), "10")
    }

    /// 사용자 예시: 총 3초, 씹기 2초 + 쉬기 1초 → "110".
    func testUserExample_chew2Rest1_is110() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)
        feed(&acc, chewing: true, count: 50)
        feed(&acc, chewing: false, count: 50)
        XCTAssertEqual(acc.makeTimeline(), "110")
    }

    /// 사용자 예시: 총 3초, 씹기 1초 + 쉬기 1초 + 씹기 1초 → "101".
    func testUserExample_chewRestChew_is101() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)
        feed(&acc, chewing: false, count: 50)
        feed(&acc, chewing: true, count: 50)
        XCTAssertEqual(acc.makeTimeline(), "101")
    }

    func testMajority_moreThanHalf_isChewing() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 26)   // 26/50 = 과반
        feed(&acc, chewing: false, count: 24)
        XCTAssertEqual(acc.makeTimeline(), "1")
    }

    func testMajority_exactHalf_isNotChewing() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 25)   // 25/50 = 동률, 과반 아님
        feed(&acc, chewing: false, count: 25)
        XCTAssertEqual(acc.makeTimeline(), "0")
    }

    func testPartialLastSecond_chewMajority_isFlushed() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)   // 꽉 찬 1초
        feed(&acc, chewing: true, count: 10)   // 남은 부분 초(전부 씹기)
        XCTAssertEqual(acc.makeTimeline(), "11")
    }

    func testPartialLastSecond_restMajority_isFlushed() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)
        feed(&acc, chewing: false, count: 10)
        XCTAssertEqual(acc.makeTimeline(), "10")
    }

    func testReset_clearsAccumulation() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)
        acc.reset()
        XCTAssertNil(acc.makeTimeline())
        feed(&acc, chewing: false, count: 50)
        XCTAssertEqual(acc.makeTimeline(), "0")
    }

    /// makeTimeline은 비파괴적 — 여러 번 불러도 같은 값, 부분 초가 누적 상태를 바꾸지 않는다.
    func testMakeTimeline_isNonMutating_repeatable() {
        var acc = ChewingTimelineAccumulator()
        feed(&acc, chewing: true, count: 50)
        feed(&acc, chewing: false, count: 25)  // 부분 초
        let first = acc.makeTimeline()
        let second = acc.makeTimeline()
        XCTAssertEqual(first, "10")
        XCTAssertEqual(first, second)
    }

    /// 상한 초과분은 버려 서버 varchar(7200)을 넘기지 않는다.
    func testCap_dropsSecondsBeyondMax() {
        var acc = ChewingTimelineAccumulator(samplesPerSecond: 1, maxSeconds: 3)
        feed(&acc, chewing: true, count: 10)   // 10초어치지만 상한 3
        XCTAssertEqual(acc.makeTimeline(), "111")
    }
}
