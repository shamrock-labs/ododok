import Foundation

/// `profiles` row와 1:1 매핑되는 DTO. 디바이스 신원 + 표시 이름.
/// displayName은 온보딩에서 입력한 값으로, `/auth/me` 응답의 onboardingCompleted 판정과 함께
/// JWT(user_id) 스코프로 관리된다.
struct ProfileDTO: Codable, Equatable {
    var deviceId: String
    var userId: String? = nil
    var displayName: String?

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case userId
        case displayName
    }

    init(deviceId: String, displayName: String?, userId: String? = nil) {
        self.deviceId = deviceId
        self.userId = userId
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? userId ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }
}

/// `user_stats` row와 1:1 매핑되는 DTO. 게임 진행 상태(카운터 + 인벤토리 + 플래그)를 보관.
/// 기존 PersistedSnapshot(`AppState.swift`)이 JSON Blob으로 갖고 있던 필드를 컬럼 단위로 풀어놓은 것.
///
/// snake_case ↔ camelCase 매핑은 PostgREST 호출부에서 keyEncodingStrategy로 처리한다.
struct UserStatsDTO: Codable, Equatable {
    var deviceId: String
    var userId: String? = nil
    var streak: Int
    var points: Int
    var owned: [String]
    var equipped: EquippedDTO
    var ownedAcornPacks: [String: Int]
    var savedAt: Date

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case userId
        case streak
        case points
        case owned
        case equipped
        case ownedAcornPacks
        case savedAt
    }

    struct EquippedDTO: Codable, Equatable {
        var hat: String?
        var glasses: String?
        var acc: String?
    }

    init(
        deviceId: String,
        streak: Int,
        points: Int,
        owned: [String],
        equipped: EquippedDTO,
        ownedAcornPacks: [String: Int],
        savedAt: Date,
        userId: String? = nil
    ) {
        self.deviceId = deviceId
        self.userId = userId
        self.streak = streak
        self.points = points
        self.owned = owned
        self.equipped = equipped
        self.ownedAcornPacks = ownedAcornPacks
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? userId ?? ""
        streak = try container.decode(Int.self, forKey: .streak)
        points = try container.decode(Int.self, forKey: .points)
        owned = try container.decode([String].self, forKey: .owned)
        equipped = try container.decode(EquippedDTO.self, forKey: .equipped)
        ownedAcornPacks = try container.decode([String: Int].self, forKey: .ownedAcornPacks)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(streak, forKey: .streak)
        try container.encode(points, forKey: .points)
        try container.encode(owned, forKey: .owned)
        try container.encode(equipped, forKey: .equipped)
        try container.encode(ownedAcornPacks, forKey: .ownedAcornPacks)
        try container.encode(savedAt, forKey: .savedAt)
    }
}

/// `chewing_session` row와 1:1 DTO. 클라이언트가 한 끼 식사 종료 시 INSERT.
/// raw IMU는 별도로 imu-sessions 버킷에 gzip CSV로 올리고 `storagePath`에 경로만 보관.
///
/// 분석 5필드(`chewingSeconds`/`restSeconds`/`chewingFraction`/`estimatedTotalChews`/`modelVersion`)는
/// 온디바이스 DSP 감지(`ChewCounter`)가 동작한 세션에서만 채워진다. 시뮬레이터/AirPods 미연결 등
/// 감지가 돌지 않은 세션은 모두 nil — DB 컬럼도 nullable.
struct ChewingSessionDTO: Codable, Equatable, Identifiable {
    var id: UUID
    var deviceId: String
    var userId: String? = nil
    var startedAt: Date
    var endedAt: Date
    var durationSec: Double
    var sensorLocation: String
    var sampleCount: Int
    var sampleRateHz: Int
    var storagePath: String?
    var appVersion: String?
    var chewingSeconds: Double?
    var restSeconds: Double?
    var chewingFraction: Double?
    var estimatedTotalChews: Int?
    var modelVersion: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case deviceId
        case userId
        case startedAt
        case endedAt
        case durationSec
        case sensorLocation
        case sampleCount
        case sampleRateHz
        case storagePath
        case appVersion
        case chewingSeconds
        case restSeconds
        case chewingFraction
        case estimatedTotalChews
        case modelVersion
    }

    init(
        id: UUID,
        deviceId: String,
        startedAt: Date,
        endedAt: Date,
        durationSec: Double,
        sensorLocation: String,
        sampleCount: Int,
        sampleRateHz: Int,
        storagePath: String?,
        appVersion: String?,
        chewingSeconds: Double?,
        restSeconds: Double?,
        chewingFraction: Double?,
        estimatedTotalChews: Int?,
        modelVersion: String?,
        userId: String? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.userId = userId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSec = durationSec
        self.sensorLocation = sensorLocation
        self.sampleCount = sampleCount
        self.sampleRateHz = sampleRateHz
        self.storagePath = storagePath
        self.appVersion = appVersion
        self.chewingSeconds = chewingSeconds
        self.restSeconds = restSeconds
        self.chewingFraction = chewingFraction
        self.estimatedTotalChews = estimatedTotalChews
        self.modelVersion = modelVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? userId ?? ""
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationSec = try container.decode(Double.self, forKey: .durationSec)
        sensorLocation = try container.decode(String.self, forKey: .sensorLocation)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        sampleRateHz = try container.decode(Int.self, forKey: .sampleRateHz)
        storagePath = try container.decodeIfPresent(String.self, forKey: .storagePath)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        chewingSeconds = try container.decodeIfPresent(Double.self, forKey: .chewingSeconds)
        restSeconds = try container.decodeIfPresent(Double.self, forKey: .restSeconds)
        chewingFraction = try container.decodeIfPresent(Double.self, forKey: .chewingFraction)
        estimatedTotalChews = try container.decodeIfPresent(Int.self, forKey: .estimatedTotalChews)
        modelVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(durationSec, forKey: .durationSec)
        try container.encode(sensorLocation, forKey: .sensorLocation)
        try container.encode(sampleCount, forKey: .sampleCount)
        try container.encode(sampleRateHz, forKey: .sampleRateHz)
        try container.encodeIfPresent(storagePath, forKey: .storagePath)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(chewingSeconds, forKey: .chewingSeconds)
        try container.encodeIfPresent(restSeconds, forKey: .restSeconds)
        try container.encodeIfPresent(chewingFraction, forKey: .chewingFraction)
        try container.encodeIfPresent(estimatedTotalChews, forKey: .estimatedTotalChews)
        try container.encodeIfPresent(modelVersion, forKey: .modelVersion)
    }
}

/// AirPods CMDeviceMotion에서 받은 한 샘플. 학습 레포의 18컬럼 CSV와 컬럼 1:1 매칭.
/// 출시 후 모인 raw 데이터를 그대로 재학습 데이터셋으로 쓸 수 있도록 attitude/gravity/
/// magneticField까지 보존한다. 추론 input(rotation + user_accel 6채널)은 이 중 일부.
struct IMURow {
    let tMach: Double
    let tRelSec: Double
    let attitudeRoll: Double
    let attitudePitch: Double
    let attitudeYaw: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    let userAccelX: Double
    let userAccelY: Double
    let userAccelZ: Double
    let magneticFieldX: Double
    let magneticFieldY: Double
    let magneticFieldZ: Double
    let sensorLocation: String

    static let csvHeader = "t_mach,t_rel_sec,attitude_roll,attitude_pitch,attitude_yaw,rotation_x,rotation_y,rotation_z,gravity_x,gravity_y,gravity_z,user_accel_x,user_accel_y,user_accel_z,magnetic_field_x,magnetic_field_y,magnetic_field_z,sensor_location"

    /// CSV 한 줄. Double은 `%.6f` 고정 — Locale 영향 없도록 C locale 포맷터 사용.
    func csvLine() -> String {
        let nums = String(
            format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
            tMach, tRelSec,
            attitudeRoll, attitudePitch, attitudeYaw,
            rotationX, rotationY, rotationZ,
            gravityX, gravityY, gravityZ,
            userAccelX, userAccelY, userAccelZ,
            magneticFieldX, magneticFieldY, magneticFieldZ
        )
        return "\(nums),\(sensorLocation)"
    }
}

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

/// 세션 적립 결과(`reward`). 멱등 재전송이면 `idempotentReplay=true` — 알림 억제 신호.
struct SessionRewardDTO: Codable, Equatable {
    var grantedPoints: Int
    var capped: Bool
    var idempotentReplay: Bool
}

/// 세션 스트릭 결과(`streak`). `event`는 서버 StreakEvent enum 문자열
/// (NONE/FIRST_DAY/INCREMENTED/SAVED_BY_FREEZE/RESET/MILESTONE).
struct SessionStreakDTO: Codable, Equatable {
    var current: Int
    var event: String
    var freezeInventory: Int
}

/// 오늘 완료 여부(`today`).
struct SessionTodayDTO: Codable, Equatable {
    var completed: Bool
}

/// 정책 세션 저장 응답(`POST /v1/me/chewing-sessions`). 저장된 세션 + 적립/스트릭/오늘/홈을 한 번에.
struct CreateSessionResultDTO: Codable, Equatable {
    var chewingSession: ChewingSessionDTO
    var chewingSessionAccepted: Bool
    var rewardEligible: Bool
    var ineligibleReason: String?
    var reward: SessionRewardDTO
    var streak: SessionStreakDTO
    var today: SessionTodayDTO
    var userStats: HomeStateDTO
}

/// 출석 적립 응답(`POST /v1/me/attendance`). 세션 응답과 같은 패턴 — 적립량 + 갱신된 홈.
struct AttendanceResultDTO: Codable, Equatable {
    var grantedPoints: Int
    var capped: Bool
    var idempotentReplay: Bool
    var userStats: HomeStateDTO
}

struct FriendInviteCodeDTO: Codable, Equatable {
    var code: String
    /// 공유용 딥링크(chewchew://invite?code=...). 구버전 서버 호환 위해 옵셔널.
    var deepLink: String?
}

struct FriendAcceptResultDTO: Codable, Equatable {
    var accepted: Bool
    var bonusGranted: Bool
}

struct FriendRankingDTO: Codable, Equatable, Identifiable {
    var userId: UUID
    var name: String?
    var points: Int
    var me: Bool

    var id: UUID { userId }
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
