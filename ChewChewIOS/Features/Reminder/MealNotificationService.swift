import Foundation
import UserNotifications

/// 끼니 알림 스케줄링 래퍼.
/// 5개 슬롯(breakfast/lunch/dinner/extra1/extra2)을 매번 전부 remove한 뒤
/// enabled인 것만 daily 반복 trigger로 다시 add — 원자적 교체.
enum MealNotificationService {
    enum Meal: String, CaseIterable {
        case breakfast, lunch, dinner, extra1, extra2

        var identifier: String { "meal.\(rawValue)" }

        /// 끼니별 알림 제목(디자인: "🕐 곧 {끼니} 식사 시간이에요!"). 서버 푸시 제목과 일치시킨다.
        var reminderTitle: String {
            switch self {
            case .breakfast: return "🕐 곧 아침 식사 시간이에요!"
            case .lunch:     return "🕐 곧 점심 식사 시간이에요!"
            case .dinner:    return "🕐 곧 저녁 식사 시간이에요!"
            case .extra1, .extra2: return "🕐 곧 식사 시간이에요!"
            }
        }
    }

    private static let center = UNUserNotificationCenter.current()

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 알림 발송 가능 여부(.authorized / .provisional).
    static func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// `.notDetermined`이면 다이얼로그를 띄우고, 이미 결정된 상태면 즉시 현재 권한 반영.
    /// 반환값 true = 알림 가능 (.authorized / .provisional).
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// 끼니 알림 5개 pending 제거. 서버 발송으로 전환할 때 로컬 예약을 취소하는 용도로도 쓴다.
    static func cancelMealReminders() {
        center.removePendingNotificationRequests(withIdentifiers: Meal.allCases.map(\.identifier))
    }

    /// 5개 identifier 모두 pending 제거 후, enabled인 슬롯만 daily 반복으로 add.
    /// 권한 없음/거부 상태면 add 없이 remove만.
    static func reschedule(_ settings: MealReminderSettings) async {
        cancelMealReminders()

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let slots: [(Meal, MealSlot)] = [
            (.breakfast, settings.breakfast),
            (.lunch,     settings.lunch),
            (.dinner,    settings.dinner),
            (.extra1,    settings.extra1),
            (.extra2,    settings.extra2),
        ]

        for (meal, slot) in slots where slot.enabled {
            let content = UNMutableNotificationContent()
            content.title = meal.reminderTitle
            content.body  = CaptionPool.random(from: CaptionPool.mealReminder)
            content.sound = .default
            content.userInfo = [
                "deepLink": deepLinkStart,
                "notificationKind": "mealReminder"
            ]
            content.categoryIdentifier = mealReminderCategoryId

            var components = DateComponents()
            components.hour = slot.hour
            components.minute = slot.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let request = UNNotificationRequest(
                identifier: meal.identifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static let deepLinkStart = "chewchew://start"

    /// 끼니 리마인더 알림에 붙는 카테고리 + "식사 시작" 액션 식별자.
    /// 이 알림은 Live Activity가 아니라 단순 푸시로 오고, 버튼으로 바로 측정을 시작한다.
    static let mealReminderCategoryId = "MEAL_REMINDER"
    static let startActionId = "MEAL_START"

    // MARK: - 측정 중단/재개 알림 (전화 인터럽트)

    static let deepLinkResume = "chewchew://resume"

    /// 중단 알림에 붙는 액션 카테고리 + 두 버튼(계속하기/그만하기) 식별자.
    static let interruptionCategoryId = "MEAL_INTERRUPTION"
    static let resumeActionId = "MEAL_RESUME"
    static let stopActionId = "MEAL_STOP"

    /// 중단 알림은 한 번에 하나만 유지 — 고정 identifier로 중복 발사를 막는다.
    private static let interruptionId = "session.interruption"

    /// 중단 알림 액션 카테고리 등록. 앱 시작 시 1회 호출.
    static func registerCategories() {
        let resume = UNNotificationAction(
            identifier: resumeActionId,
            title: "계속하기",
            options: [.foreground]
        )
        let stop = UNNotificationAction(
            identifier: stopActionId,
            title: "그만하기",
            options: [.foreground, .destructive]
        )
        let interruption = UNNotificationCategory(
            identifier: interruptionCategoryId,
            actions: [resume, stop],
            intentIdentifiers: [],
            options: []
        )

        // 끼니 리마인더 — 알림에서 바로 측정을 시작하는 "식사 시작" 버튼.
        let start = UNNotificationAction(
            identifier: startActionId,
            title: "기록하러 가기",
            options: [.foreground]
        )
        let reminder = UNNotificationCategory(
            identifier: mealReminderCategoryId,
            actions: [start],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([interruption, reminder])
    }

    /// 전화로 측정이 멈췄을 때 "이어서 측정하시겠어요?" 알림을 즉시 띄운다.
    /// 통화 도중(앱이 살아있을 때) 발사해두면 통화 길이와 무관하게 알림이 남아,
    /// 통화를 끊은 뒤 계속하기/그만하기를 고를 수 있다.
    static func scheduleInterruptionPrompt() async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "식사 측정이 중단되었어요!"
        content.body = "방금 알림이나 전화가 왔나요? 식사 기록을 이어서 계속 진행하시겠어요?"
        content.sound = .default
        content.categoryIdentifier = interruptionCategoryId
        content.userInfo = ["deepLink": deepLinkResume]

        let request = UNNotificationRequest(
            identifier: interruptionId,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// 중단 알림 제거 — 재개했거나 세션이 끝났을 때 pending/delivered 양쪽을 정리.
    static func cancelInterruptionPrompt() {
        center.removePendingNotificationRequests(withIdentifiers: [interruptionId])
        center.removeDeliveredNotifications(withIdentifiers: [interruptionId])
    }
}
