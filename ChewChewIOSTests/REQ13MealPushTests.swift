import XCTest
@testable import ChewChewIOS

@MainActor
final class REQ13MealPushTests: XCTestCase {

    // MARK: - Meal enum (5슬롯)

    func testMealAllCasesCount_is5() {
        XCTAssertEqual(MealNotificationService.Meal.allCases.count, 5)
    }

    func testMealAllCases_containsExtra1AndExtra2() {
        let cases = MealNotificationService.Meal.allCases
        XCTAssertTrue(cases.contains(.extra1))
        XCTAssertTrue(cases.contains(.extra2))
    }

    // MARK: - CaptionPool.mealReminder

    func testMealReminderPool_hasAtLeast8Captions() {
        XCTAssertGreaterThanOrEqual(CaptionPool.mealReminder.count, 8)
    }

    func testMealReminderPool_allCaptionsWithin32Chars() {
        for caption in CaptionPool.mealReminder {
            XCTAssertLessThanOrEqual(
                caption.count, 32,
                "문장이 32자를 초과합니다: \"\(caption)\" (\(caption.count)자)"
            )
        }
    }

    // MARK: - deepLink userInfo

    func testDeepLinkConstant_isChewchewStart() {
        XCTAssertEqual(MealNotificationService.deepLinkStart, "chewchew://start")
    }

    // MARK: - MealReminderSettings (5슬롯)

    func testDefaultSettings_hasFiveSlots() {
        let s = MealReminderSettings.default
        // 5개 슬롯이 모두 접근 가능한지 확인
        _ = s.breakfast
        _ = s.lunch
        _ = s.dinner
        _ = s.extra1
        _ = s.extra2
        XCTAssertEqual(
            MealNotificationService.Meal.allCases.count,
            5,
            "슬롯 수가 Meal.allCases와 일치해야 함"
        )
    }

    func testAnyEnabled_includesExtra1AndExtra2() {
        var s = MealReminderSettings.default
        XCTAssertFalse(s.anyEnabled)
        s.extra1.enabled = true
        XCTAssertTrue(s.anyEnabled)
        s.extra1.enabled = false
        s.extra2.enabled = true
        XCTAssertTrue(s.anyEnabled)
    }

    // MARK: - requestStartHighlight

    func testRequestStartHighlight_immediatelyTrue() {
        let state = AppState(remoteStore: NoopRemoteStore())
        XCTAssertFalse(state.startButtonHighlighted)
        state.requestStartHighlight(duration: 60) // 長 duration → 테스트 중 false로 안 바뀜
        XCTAssertTrue(state.startButtonHighlighted)
    }

    // MARK: - Notification stop routing

    func testNotificationStop_usesShortSessionConfirmationForSubMinuteMeal() {
        let state = AppState(remoteStore: NoopRemoteStore())
        state.startEating()

        state.stopMeasurementFromNotification()

        XCTAssertTrue(state.isEating)
        XCTAssertTrue(state.showShortSessionConfirm)
    }

    func testShouldConfirmStopForShortSession_matchesInAppStopThreshold() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(AppState.shouldConfirmShortSessionStop(startedAt: startedAt, now: startedAt.addingTimeInterval(59)))
        XCTAssertFalse(AppState.shouldConfirmShortSessionStop(startedAt: startedAt, now: startedAt.addingTimeInterval(60)))
        XCTAssertFalse(AppState.shouldConfirmShortSessionStop(startedAt: nil, now: startedAt))
    }
}
