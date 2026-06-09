import XCTest
@testable import ChewChewIOS

@MainActor
final class StreakServiceTests: XCTestCase {

    // Each test creates a fresh AppState with NoopRemoteStore
    private func makeState() -> AppState {
        AppState(remoteStore: NoopRemoteStore())
    }

    // Convenience: a Date offset by `days` from now (using Calendar)
    private func date(daysAgo days: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - evaluate(_:now:)

    func testFirstSuccess_streak1() {
        let state = makeState()
        state.lastSuccessDate = nil
        let events = StreakService.evaluate(state)
        XCTAssertEqual(state.streak, 1)
        XCTAssertTrue(events.contains(.incremented(newCount: 1)))
    }

    func testConsecutive_streakIncrement() {
        let state = makeState()
        state.streak = 1
        state.lastSuccessDate = date(daysAgo: 1)
        let events = StreakService.evaluate(state)
        XCTAssertEqual(state.streak, 2)
        XCTAssertTrue(events.contains(.incremented(newCount: 2)))
    }

    func testSameDay_noop() {
        let state = makeState()
        state.streak = 3
        state.lastSuccessDate = Date()
        let events = StreakService.evaluate(state)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(state.streak, 3)
    }

    func testMilestone7_freezeGain() {
        let state = makeState()
        state.streak = 6
        state.freezeInventory = 0
        state.lastSuccessDate = date(daysAgo: 1)
        let events = StreakService.evaluate(state)
        XCTAssertEqual(state.streak, 7)
        XCTAssertEqual(state.freezeInventory, 1)
        let hasMilestone = events.contains(where: {
            if case .milestone(count: 7, freezeGain: 1) = $0 { return true }
            return false
        })
        XCTAssertTrue(hasMilestone)
    }

    func testMilestoneAtCap_noGain() {
        let state = makeState()
        state.streak = 29
        state.freezeInventory = 3 // already at cap
        state.lastSuccessDate = date(daysAgo: 1)
        let events = StreakService.evaluate(state)
        XCTAssertEqual(state.streak, 30)
        XCTAssertEqual(state.freezeInventory, 3) // cap unchanged
        // milestone event should either be absent or have amount==0
        let milestoneGain = events.compactMap({ event -> Int? in
            if case .milestone(count: 30, freezeGain: let g) = event { return g }
            return nil
        }).first
        if let gain = milestoneGain {
            XCTAssertEqual(gain, 0)
        }
        // freeze inventory must not exceed cap
        XCTAssertLessThanOrEqual(state.freezeInventory, StreakService.maxFreezeInventory)
    }

    func testTwoDayGapWithFreeze_savedByFreeze() {
        let state = makeState()
        state.streak = 5
        state.freezeInventory = 1
        state.lastSuccessDate = date(daysAgo: 3)
        let events = StreakService.evaluate(state)
        XCTAssertEqual(state.freezeInventory, 0)
        XCTAssertEqual(state.streak, 6)
        let hasSaved = events.contains(where: {
            if case .savedByFreeze = $0 { return true }
            return false
        })
        XCTAssertTrue(hasSaved)
        XCTAssertTrue(events.contains(.incremented(newCount: 6)))
    }

    func testTwoDayGapNoFreeze_reset() {
        let state = makeState()
        state.streak = 5
        state.freezeInventory = 0
        state.lastSuccessDate = date(daysAgo: 3)
        let events = StreakService.evaluate(state)
        XCTAssertEqual(state.streak, 1)
        XCTAssertTrue(events.contains(.reset))
    }

    // MARK: - effectiveGapDays(last:now:tolerance:)

    func testEffectiveGapDays_withinTolerance_sameDay() {
        // last=어제 23:00, now=오늘 00:30 → 로컬 일자 차 1이지만 elapsed=1.5h < 6h → 0
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let last = today.addingTimeInterval(-3600)          // 어제 23:00 (자정 -1h)
        let now  = today.addingTimeInterval(30 * 60)        // 오늘 00:30
        let gap = StreakService.effectiveGapDays(last: last, now: now)
        XCTAssertEqual(gap, 0, "6h 관용 내 경계는 같은 날로 판정해야 한다")
    }

    func testEffectiveGapDays_beyondTolerance_nextDay() {
        // last=어제 22:00, now=오늘 05:00 → elapsed=7h > 6h → 1
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let last = today.addingTimeInterval(-2 * 3600)      // 어제 22:00 (자정 -2h)
        let now  = today.addingTimeInterval(5 * 3600)       // 오늘 05:00
        let gap = StreakService.effectiveGapDays(last: last, now: now)
        XCTAssertEqual(gap, 1, "6h 초과 경계는 정상 다음 날로 판정해야 한다")
    }

    // MARK: - 6시간 관용 — evaluate 통합

    func testEvaluate_boundaryWithinTolerance_noop() {
        // 어제 23:30에 성공, 오늘 00:30에 재호출 → 관용 내 같은 날 → noop
        let cal = Calendar(identifier: .gregorian)
        let state = makeState()
        state.streak = 3
        let today = cal.startOfDay(for: Date())
        state.lastSuccessDate = today.addingTimeInterval(-30 * 60)   // 어제 23:30
        let now = today.addingTimeInterval(30 * 60)                   // 오늘 00:30
        let events = StreakService.evaluate(state, now: now)
        XCTAssertTrue(events.isEmpty, "관용 경계 내 호출은 noop이어야 한다")
        XCTAssertEqual(state.streak, 3)
    }

    func testEvaluate_boundaryBeyondTolerance_increments() {
        // 어제 22:00에 성공, 오늘 05:00에 재호출 → elapsed 7h > 6h → +1
        let cal = Calendar(identifier: .gregorian)
        let state = makeState()
        state.streak = 3
        let today = cal.startOfDay(for: Date())
        state.lastSuccessDate = today.addingTimeInterval(-2 * 3600)  // 어제 22:00
        let now = today.addingTimeInterval(5 * 3600)                  // 오늘 05:00
        let events = StreakService.evaluate(state, now: now)
        XCTAssertEqual(state.streak, 4)
        XCTAssertTrue(events.contains(.incremented(newCount: 4)))
    }

    // MARK: - noticeGrant 우선순위 및 첫 날 토스트

    func testNoticeGrant_firstDay_nonNil() {
        let events: [StreakService.Event] = [.incremented(newCount: 1)]
        let grant = StreakService.noticeGrant(from: events)
        XCTAssertNotNil(grant, "첫 성공(newCount:1)은 non-nil grant를 반환해야 한다")
        XCTAssertEqual(grant?.kind, .streakFirstDay)
    }

    func testNoticeGrant_sameDay_noGrant() {
        // 같은 날 두 번째 호출은 events가 빈 배열 → nil
        let events: [StreakService.Event] = []
        let grant = StreakService.noticeGrant(from: events)
        XCTAssertNil(grant, "같은 날 2회는 grant가 없어야 한다")
    }

    func testNoticeGrant_milestone_overridesFirstDay() {
        // incremented(1) + milestone 동시 발생 시 milestone 우선 (현실적으로 없지만 방어)
        let events: [StreakService.Event] = [
            .incremented(newCount: 7),
            .milestone(count: 7, freezeGain: 1)
        ]
        let grant = StreakService.noticeGrant(from: events)
        if case .streakMilestone(let count) = grant?.kind {
            XCTAssertEqual(count, 7)
        } else {
            XCTFail("마일스톤이 firstDay보다 우선되어야 한다")
        }
    }

    func testNoticeGrant_savedByFreeze_overridesFirstDay() {
        // savedByFreeze + incremented(1) 동시 발생 시 savedByFreeze 우선
        let events: [StreakService.Event] = [
            .savedByFreeze(remainingFreeze: 0),
            .incremented(newCount: 1)
        ]
        let grant = StreakService.noticeGrant(from: events)
        XCTAssertEqual(grant?.kind, .streakSaved)
    }

    // MARK: - evaluateForegroundDefense(_:now:)

    func testForegroundDefense_noop_when_recent() {
        let state = makeState()
        state.streak = 3
        state.lastSuccessDate = date(daysAgo: 1)
        let events = StreakService.evaluateForegroundDefense(state)
        XCTAssertTrue(events.isEmpty)
    }

    func testForegroundDefense_savedByFreeze() {
        let state = makeState()
        state.streak = 5
        state.freezeInventory = 1
        state.lastSuccessDate = date(daysAgo: 2)
        let events = StreakService.evaluateForegroundDefense(state)
        XCTAssertEqual(state.freezeInventory, 0)
        XCTAssertNotNil(state.lastSuccessDate)
        let hasSaved = events.contains(where: {
            if case .savedByFreeze = $0 { return true }
            return false
        })
        XCTAssertTrue(hasSaved)
        // streak count itself is not changed by foreground defense
        XCTAssertEqual(state.streak, 5)
    }

    func testForegroundDefense_reset() {
        let state = makeState()
        state.streak = 5
        state.freezeInventory = 0
        state.lastSuccessDate = date(daysAgo: 3)
        let events = StreakService.evaluateForegroundDefense(state)
        XCTAssertNil(state.lastSuccessDate)
        XCTAssertTrue(events.contains(.reset))
        // streak count is NOT touched by foreground defense (next session sets to 1)
        XCTAssertEqual(state.streak, 5)
    }

    // MARK: - currentStreak (홈 표시용 "오늘 기준" 값)

    func testCurrentStreak_zero_whenNoSuccessEver() {
        let state = makeState()
        state.lastSuccessDate = nil
        state.streak = 5
        XCTAssertEqual(state.currentStreak, 0)
    }

    func testCurrentStreak_showsCount_whenSuccessToday() {
        let state = makeState()
        state.streak = 4
        state.lastSuccessDate = Date()
        XCTAssertEqual(state.currentStreak, 4)
    }

    func testCurrentStreak_showsCount_whenSuccessYesterday() {
        let state = makeState()
        state.streak = 4
        state.lastSuccessDate = date(daysAgo: 1)
        XCTAssertEqual(state.currentStreak, 4, "어제 성공이면 오늘 유지 가능 — 아직 살아 있음")
    }

    func testCurrentStreak_zero_whenBrokenTwoDayGap() {
        let state = makeState()
        state.streak = 9
        state.lastSuccessDate = date(daysAgo: 2)
        XCTAssertEqual(state.currentStreak, 0, "2일 이상 비면 오늘 기준 끊긴 것으로 0")
    }

    func testCurrentStreak_zero_afterForegroundDefenseReset() {
        // 회귀: foreground defense가 streak count(=5)를 안 건드려도 표시값은 0이어야 한다
        let state = makeState()
        state.streak = 5
        state.freezeInventory = 0
        state.lastSuccessDate = date(daysAgo: 3)
        _ = StreakService.evaluateForegroundDefense(state)   // lastSuccessDate → nil
        XCTAssertEqual(state.streak, 5)                       // 저장값은 그대로
        XCTAssertEqual(state.currentStreak, 0)               // 표시값은 끊김
    }
}
