import Foundation

// MARK: - 서버 권위 응답 (ODO-54 thin-client)
//
// ODO-45 이후 도토리/스트릭/오늘완료 정본은 서버다. 아래 DTO는 Spring 응답(camelCase,
// wrapping의 `result` 안쪽)과 1:1 매핑한다. iOS는 이 값을 표시만 하고 재계산하지 않는다.

/// 홈 상태 응답(`GET /v1/me/home`, 세션 저장 응답의 `userStats`). 서버가 계산한 화면 정본.
struct HomeStateDTO: Codable, Equatable {
    var deviceId: String
    var userId: String? = nil
    var displayName: String?
    var points: Int
    var streak: Int
    var freezeInventory: Int
    var todayRealChewCount: Int
    var dailyGoal: Int
    var todayProgress: Double
    var todayCompleted: Bool

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case userId
        case displayName
        case points
        case streak
        case freezeInventory
        case todayRealChewCount
        case dailyGoal
        case todayProgress
        case todayCompleted
    }

    init(
        deviceId: String,
        displayName: String?,
        points: Int,
        streak: Int,
        freezeInventory: Int,
        todayRealChewCount: Int,
        dailyGoal: Int,
        todayProgress: Double,
        todayCompleted: Bool,
        userId: String? = nil
    ) {
        self.deviceId = deviceId
        self.userId = userId
        self.displayName = displayName
        self.points = points
        self.streak = streak
        self.freezeInventory = freezeInventory
        self.todayRealChewCount = todayRealChewCount
        self.dailyGoal = dailyGoal
        self.todayProgress = todayProgress
        self.todayCompleted = todayCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? userId ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        points = try container.decode(Int.self, forKey: .points)
        streak = try container.decode(Int.self, forKey: .streak)
        freezeInventory = try container.decode(Int.self, forKey: .freezeInventory)
        todayRealChewCount = try container.decode(Int.self, forKey: .todayRealChewCount)
        dailyGoal = try container.decode(Int.self, forKey: .dailyGoal)
        todayProgress = try container.decode(Double.self, forKey: .todayProgress)
        todayCompleted = try container.decode(Bool.self, forKey: .todayCompleted)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(points, forKey: .points)
        try container.encode(streak, forKey: .streak)
        try container.encode(freezeInventory, forKey: .freezeInventory)
        try container.encode(todayRealChewCount, forKey: .todayRealChewCount)
        try container.encode(dailyGoal, forKey: .dailyGoal)
        try container.encode(todayProgress, forKey: .todayProgress)
        try container.encode(todayCompleted, forKey: .todayCompleted)
    }
}

extension HomeStateDTO {
    /// 서버가 줄 게 없을 때(Noop/레거시 신규 기기)의 중립 홈. `dailyGoal=0`은 호출처에서
    /// 진행도 분모 가드로 처리한다.
    static func empty(deviceId: String) -> HomeStateDTO {
        HomeStateDTO(
            deviceId: deviceId,
            displayName: nil,
            points: 0,
            streak: 0,
            freezeInventory: 0,
            todayRealChewCount: 0,
            dailyGoal: 0,
            todayProgress: 0,
            todayCompleted: false
        )
    }
}

/// 출석 적립 응답(`POST /v1/me/attendance`). 세션 응답과 같은 패턴 — 적립량 + 갱신된 홈.
struct AttendanceResultDTO: Codable, Equatable {
    var grantedPoints: Int
    var capped: Bool
    var idempotentReplay: Bool
    var userStats: HomeStateDTO
}

enum RewardEventType: String, Codable, Equatable {
    case session = "SESSION"
    case attendance = "ATTENDANCE"
    case friendBonus = "FRIEND_BONUS"

    var displayTitle: String {
        switch self {
        case .session: "식사 완료"
        case .attendance: "출석 보상"
        case .friendBonus: "친구 초대"
        }
    }
}

struct RewardHistoryDTO: Codable, Equatable, Identifiable {
    var id: UUID
    var eventType: RewardEventType
    var eventDay: String
    var grantedPoints: Int
    var capped: Bool
    var sessionId: UUID?
}
