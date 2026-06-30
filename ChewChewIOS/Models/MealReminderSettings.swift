import Foundation

/// 끼니별 알림 설정 한 줄. Toggle off면 enabled=false로 시각은 보존.
struct MealSlot: Codable, Equatable {
    var enabled: Bool
    var hour: Int    // 0..23
    var minute: Int  // 0..59
}

/// 아침·점심·저녁·추가1·추가2 알림 시각 + 활성화 상태.
/// 정본은 서버다(`/v1/me/meal-notifications`, 계정별 = JWT 스코프). UserDefaults는 현재 로그인 계정의
/// 로컬 캐시일 뿐 — 로그인/앱 시작 시 서버값으로 덮어쓰고 로그아웃 시 비운다(ODO-103). 같은 계정으로 보면
/// 기기가 달라도 서버값으로 일치한다.
struct MealReminderSettings: Equatable {
    var breakfast: MealSlot
    var lunch: MealSlot
    var dinner: MealSlot
    var extra1: MealSlot
    var extra2: MealSlot

    static let `default` = MealReminderSettings(
        breakfast: MealSlot(enabled: false, hour: 8,  minute: 0),
        lunch:     MealSlot(enabled: false, hour: 12, minute: 30),
        dinner:    MealSlot(enabled: false, hour: 19, minute: 0),
        extra1:    MealSlot(enabled: false, hour: 10, minute: 0),
        extra2:    MealSlot(enabled: false, hour: 15, minute: 0)
    )

    var anyEnabled: Bool {
        breakfast.enabled || lunch.enabled || dinner.enabled
            || extra1.enabled || extra2.enabled
    }
}

// MARK: - Codable (extra1/extra2 backward-compatible — 구버전 JSON에 키 없으면 기본값)
extension MealReminderSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case breakfast, lunch, dinner, extra1, extra2
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        breakfast = try c.decode(MealSlot.self, forKey: .breakfast)
        lunch     = try c.decode(MealSlot.self, forKey: .lunch)
        dinner    = try c.decode(MealSlot.self, forKey: .dinner)
        extra1    = (try? c.decode(MealSlot.self, forKey: .extra1))
                    ?? MealSlot(enabled: false, hour: 10, minute: 0)
        extra2    = (try? c.decode(MealSlot.self, forKey: .extra2))
                    ?? MealSlot(enabled: false, hour: 15, minute: 0)
    }
}

extension MealReminderSettings {
    static let userDefaultsKey = "ChewChewIOS.MealReminders.v1"

    /// 로컬 캐시에서 읽는다. 정본은 서버이며 이 값은 마지막 동기화 스냅샷이다.
    /// `defaults`는 테스트에서 격리된 suite를 주입하기 위한 seam(기본 `.standard`).
    static func load(from defaults: UserDefaults = .standard) -> MealReminderSettings {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(MealReminderSettings.self, from: data)
        else { return .default }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    /// 로컬 캐시 제거 — 로그아웃/세션 만료 시 다음 계정이 이전 계정 값을 보지 않도록(ODO-103).
    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}
