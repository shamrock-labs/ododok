import Foundation

/// 끼니별 알림 설정 한 줄. Toggle off면 enabled=false로 시각은 보존.
struct MealSlot: Codable, Equatable {
    var enabled: Bool
    var hour: Int    // 0..23
    var minute: Int  // 0..59
}

/// 아침·점심·저녁 알림 시각 + 활성화 상태.
/// 다중 기기 동기화는 정책상 없음 — UserDefaults 단일 키로만 영속화.
struct MealReminderSettings: Codable, Equatable {
    var breakfast: MealSlot
    var lunch: MealSlot
    var dinner: MealSlot

    static let `default` = MealReminderSettings(
        breakfast: MealSlot(enabled: false, hour: 8,  minute: 0),
        lunch:     MealSlot(enabled: false, hour: 12, minute: 30),
        dinner:    MealSlot(enabled: false, hour: 19, minute: 0)
    )

    var anyEnabled: Bool {
        breakfast.enabled || lunch.enabled || dinner.enabled
    }
}

extension MealReminderSettings {
    private static let userDefaultsKey = "ChewChewIOS.MealReminders.v1"

    static func load() -> MealReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(MealReminderSettings.self, from: data)
        else { return .default }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
