import Foundation

// MARK: - 서버 권위 응답 (ODO-54 thin-client)
//
// ODO-45 이후 도토리/오늘완료 정본은 서버이며, 스트릭은 출석 응답의 정본을 따른다. 아래 DTO는 Spring 응답(camelCase,
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
    var streak: AttendanceStreakDTO
    var userStats: HomeStateDTO

    init(
        grantedPoints: Int,
        capped: Bool,
        idempotentReplay: Bool,
        streak: AttendanceStreakDTO = .empty,
        userStats: HomeStateDTO
    ) {
        self.grantedPoints = grantedPoints
        self.capped = capped
        self.idempotentReplay = idempotentReplay
        self.streak = streak
        self.userStats = userStats
    }
}

enum AttendanceRecoveryStatus: String, Codable, Equatable {
    case notNeeded = "NOT_NEEDED"
    case recoveryAvailable = "RECOVERY_AVAILABLE"
    case insufficient = "INSUFFICIENT"
}

struct AttendanceStatusDTO: Codable, Equatable {
    var asOf: String
    var status: AttendanceRecoveryStatus
    var missedDates: [String]
    var requiredFreezes: Int
    var freezeInventory: Int
}

enum FreezeDecisionDTO: String, Codable, Equatable {
    case use = "USE"
    case skip = "SKIP"
}

/// 출석과 같은 트랜잭션에서 서버가 확정한 스트릭 결과.
struct AttendanceStreakDTO: Codable, Equatable {
    var current: Int
    var longest: Int
    var startedOn: String?
    var event: String
    var freezeInventory: Int
    var freezeConsumed: Int
    var freezeGranted: Int

    static let empty = AttendanceStreakDTO(
        current: 0,
        longest: 0,
        startedOn: nil,
        event: "NONE",
        freezeInventory: 0,
        freezeConsumed: 0,
        freezeGranted: 0
    )
}

struct StreakDetailDTO: Codable, Equatable {
    var asOf: String
    var current: Int
    var longest: Int
    var startedOn: String?
    var freezeInventory: Int
    var days: [StreakDayDTO]

    /// Spring 응답 대체값이 아니라 Noop/non-Spring fallback 전용 중립 상세.
    /// 로컬 KST 기준일만 채우고 출석/프리즈 원장 행은 만들지 않는다.
    static var empty: StreakDetailDTO {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return StreakDetailDTO(
            asOf: formatter.string(from: Date()),
            current: 0,
            longest: 0,
            startedOn: nil,
            freezeInventory: 0,
            days: []
        )
    }
}

struct StreakDayDTO: Codable, Equatable, Identifiable {
    var date: String
    var state: StreakDayState
    var id: String { date }
}

enum StreakDayState: String, Codable, Equatable {
    case attended = "ATTENDED"
    case frozen = "FROZEN"
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
