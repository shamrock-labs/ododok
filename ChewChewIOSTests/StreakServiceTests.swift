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
}
