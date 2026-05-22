import Foundation
import UserNotifications

/// 끼니 알림 스케줄링 래퍼.
/// 세 슬롯(meal.breakfast / meal.lunch / meal.dinner)을 매번 전부 remove한 뒤
/// enabled인 것만 daily 반복 trigger로 다시 add — 원자적 교체.
enum MealNotificationService {
    enum Meal: String, CaseIterable {
        case breakfast, lunch, dinner

        var identifier: String { "meal.\(rawValue)" }

        var bodyText: String {
            switch self {
            case .breakfast: return "아침 시간이에요"
            case .lunch:     return "점심 시간이에요"
            case .dinner:    return "저녁 시간이에요"
            }
        }
    }

    private static let titleText = "주인님 밥주세요"
    private static let center = UNUserNotificationCenter.current()

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
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
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// 3개 identifier 모두 pending 제거 후, enabled인 슬롯만 daily 반복으로 add.
    /// 권한 없음/거부 상태면 add 없이 remove만.
    static func reschedule(_ settings: MealReminderSettings) async {
        let allIds = Meal.allCases.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return
        }

        let slots: [(Meal, MealSlot)] = [
            (.breakfast, settings.breakfast),
            (.lunch,     settings.lunch),
            (.dinner,    settings.dinner),
        ]

        for (meal, slot) in slots where slot.enabled {
            let content = UNMutableNotificationContent()
            content.title = titleText
            content.body  = meal.bodyText
            content.sound = .default

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
}
