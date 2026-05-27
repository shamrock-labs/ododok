import XCTest
@testable import ChewChewIOS

final class RewardLedgerCappedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RewardLedger.resetAll()
    }

    // MARK: - 상수 단일 소스

    func testPointsPerChewIs0_15() {
        XCTAssertEqual(Constants.pointsPerChew, 0.15, accuracy: 1e-9)
    }

    func testAccrueUsesConstantsPointsPerChew() {
        // 300 × 0.15 = 45 — Constants.pointsPerChew 기반 계산이어야 함
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        let expected = max(1, Int((300.0 * Constants.pointsPerChew).rounded()))
        XCTAssertEqual(result, expected)
    }

    // MARK: - capped 흔적 기록

    func testCappedEventRecordedWhenCapExceeded() {
        let day = "2026-05-26"
        let date = makeDate(day)

        // 7회 × 45 = 315 → 6회까지 270, 7회째는 잔여 30만 적립 후 capped 아님
        // 6회 = 270, 7회 = 30 granted (not capped), 8회 = 0 remaining → capped
        for _ in 0..<6 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        }
        // 7번째: 잔여 30만 적립 (granted > 0, not capped)
        RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        // 8번째: 잔여 0 → capped 흔적 기록
        RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)

        XCTAssertEqual(RewardLedger.cappedEventCount(for: day), 1)
    }

    func testCappedEventNotRecordedBeforeCap() {
        let day = "2026-05-26"
        let date = makeDate(day)

        // 270 적립 (캡 미달) — capped 없음
        for _ in 0..<6 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        }

        XCTAssertEqual(RewardLedger.cappedEventCount(for: day), 0)
    }

    func testCappedEventCountMultiple() {
        let day = "2026-05-26"
        let date = makeDate(day)

        // 캡 채우기: 7회로 300 채움 (6×45=270 + 1×30=300)
        for _ in 0..<7 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        }
        // 이후 2회 → 각각 capped 흔적
        RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)

        XCTAssertEqual(RewardLedger.cappedEventCount(for: day), 2)
    }

    // MARK: - capped idempotency

    func testCappedEventIdempotent() {
        let day = "2026-05-26"
        let date = makeDate(day)
        let id = UUID()

        // 캡 채우기
        for _ in 0..<7 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        }

        // 같은 id로 2회 호출 → capped 흔적 1건만
        RewardLedger.accrue(forSession: id, chewCount: 300, now: date)
        RewardLedger.accrue(forSession: id, chewCount: 300, now: date)

        XCTAssertEqual(RewardLedger.cappedEventCount(for: day), 1)
    }

    // MARK: - 잔여 적립 정확성

    func testPartialGrantBeforeCap() {
        let day = "2026-05-26"
        let date = makeDate(day)

        // 6회 × 45 = 270, 잔여 30
        for _ in 0..<6 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        }
        let partial = RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        XCTAssertEqual(partial, 30)
    }

    func testGrantedAfterPartialIsZeroAndCapped() {
        let day = "2026-05-26"
        let date = makeDate(day)

        // 캡 정확히 채움
        for _ in 0..<7 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        }
        let afterCap = RewardLedger.accrue(forSession: UUID(), chewCount: 300, now: date)
        XCTAssertEqual(afterCap, 0)
        XCTAssertEqual(RewardLedger.cappedEventCount(for: day), 1)
    }

    // MARK: - 마이그레이션 안전성 (cappedKeysKey 없는 기존 데이터)

    func testCappedEventCountDefaultsToZeroWhenKeyAbsent() {
        // resetAll 이후 cappedKeysKey 키 자체가 없는 상태 — 0 반환해야 함
        XCTAssertEqual(RewardLedger.cappedEventCount(for: "2026-01-01"), 0)
    }

    // MARK: - Helpers

    private func makeDate(_ isoDay: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: isoDay) ?? .now
    }
}
