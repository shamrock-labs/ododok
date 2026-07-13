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

    // 디자인 개편(ODO-56): 끼니 알림 본문이 길어졌다. 푸시 표시 한도(≤80자) 안인지만 확인한다.
    func testMealReminderPool_captionsWithinDisplayLimit() {
        for caption in CaptionPool.mealReminder {
            XCTAssertLessThanOrEqual(
                caption.count, 80,
                "문장이 너무 깁니다: \"\(caption)\" (\(caption.count)자)"
            )
        }
    }

    // MARK: - 끼니별 제목 (ODO-56 디자인)

    func testReminderTitle_perSlot() {
        XCTAssertEqual(MealNotificationService.Meal.breakfast.reminderTitle, "🕐 곧 아침 식사 시간이에요!")
        XCTAssertEqual(MealNotificationService.Meal.lunch.reminderTitle, "🕐 곧 점심 식사 시간이에요!")
        XCTAssertEqual(MealNotificationService.Meal.dinner.reminderTitle, "🕐 곧 저녁 식사 시간이에요!")
        XCTAssertEqual(MealNotificationService.Meal.extra1.reminderTitle, "🕐 곧 식사 시간이에요!")
        XCTAssertEqual(MealNotificationService.Meal.extra2.reminderTitle, "🕐 곧 식사 시간이에요!")
    }

    // MARK: - 서버 슬롯 변환 (ODO-56)

    func testServerSlotRoundTrip_preservesEnabledAndTime() {
        var settings = MealReminderSettings.default
        settings.breakfast = MealSlot(enabled: true, hour: 8, minute: 5)
        settings.lunch = MealSlot(enabled: false, hour: 12, minute: 30)
        settings.dinner = MealSlot(enabled: true, hour: 19, minute: 0)

        let slots = settings.toServerSlots()
        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(slots[0].slotIndex, 0)
        XCTAssertEqual(slots[0].timeOfDay, "08:05")
        XCTAssertTrue(slots[0].enabled)
        XCTAssertEqual(slots[1].timeOfDay, "12:30")
        XCTAssertFalse(slots[1].enabled)

        let restored = MealReminderSettings(serverSlots: slots)
        XCTAssertEqual(restored, settings)
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
        XCTAssertFalse(state.mealSession.startButtonHighlighted)
        state.mealSession.requestStartHighlight(duration: 60) // 長 duration → 테스트 중 false로 안 바뀜
        XCTAssertTrue(state.mealSession.startButtonHighlighted)
    }

    // MARK: - Notification stop routing

    func testNotificationStop_usesShortSessionConfirmationBeforeMinimumDuration() {
        let state = AppState(remoteStore: NoopRemoteStore())
        state.mealSession.startEating()

        state.mealSession.stopMeasurementFromNotification()

        XCTAssertTrue(state.mealSession.isEating)
        XCTAssertTrue(state.mealSession.showShortSessionConfirm)
    }

    func testShouldConfirmStopForShortSession_matchesInAppStopThreshold() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(MealSessionRuntimeRules.shouldConfirmShortSessionStop(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(29)
        ))
        XCTAssertFalse(MealSessionRuntimeRules.shouldConfirmShortSessionStop(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(30)
        ))
        XCTAssertFalse(MealSessionRuntimeRules.shouldConfirmShortSessionStop(startedAt: nil, now: startedAt))
    }
}
