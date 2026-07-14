import Foundation

enum MealReportStatusDTO: String, Codable, Equatable {
    case generated = "GENERATED"
    case unreportable = "UNREPORTABLE"
}

enum MealReportReasonDTO: String, Codable, Equatable {
    case sessionTooShort = "SESSION_TOO_SHORT"
    case analysisMissing = "ANALYSIS_MISSING"
    case invalidAnalysisInput = "INVALID_ANALYSIS_INPUT"
}

enum MealReportGradeDTO: String, Codable, Equatable {
    case good
    case soso
    case bad
}

struct MealReportAxisScoresDTO: Codable, Equatable {
    var chewingRate: Int
    var chewingTimeRatio: Int
    var totalChewCount: Int
    var mealDuration: Int
}

struct MealReportMetricsDTO: Codable, Equatable {
    var chewingRatePerMin: Double?
    var legacyMealRatePerMin: Double
    var chewingTimeRatio: Double
    var totalChewCount: Int
    var mealDurationSec: Double
}

struct MealReportTargetDTO: Codable, Equatable {
    var target: Double
}

struct MealReportRecommendedBaselineDTO: Codable, Equatable {
    var chewingRatePerMin: MealReportTargetDTO
    var chewingTimeRatio: Double
    var totalChewCount: Int
    var mealDurationSec: Double
}

struct MealReportDTO: Codable, Equatable {
    var status: MealReportStatusDTO
    var reason: MealReportReasonDTO? = nil
    var sessionId: UUID? = nil
    var scorePolicyVersion: String? = nil
    var analysisModelVersion: String? = nil
    var totalScore: Int? = nil
    var axisScores: MealReportAxisScoresDTO? = nil
    var metrics: MealReportMetricsDTO? = nil
    var grade: MealReportGradeDTO? = nil
    var recommendedBaseline: MealReportRecommendedBaselineDTO? = nil
}

/// `chewing_session` row와 1:1 DTO. 클라이언트가 한 끼 식사 종료 시 INSERT.
/// raw IMU는 별도로 imu-sessions 버킷에 gzip CSV로 올리고 `storagePath`에 경로만 보관.
///
/// 분석 6필드(`chewingSeconds`/`restSeconds`/`chewingFraction`/`estimatedTotalChews`/`modelVersion`/`chewingTimeline`)는
/// 온디바이스 DSP 감지(`ChewDetectionEngine`)가 동작한 세션에서만 채워진다. 시뮬레이터/AirPods 미연결 등
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
    var chewingTimeline: String?
    var mealReport: MealReportDTO?

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
        case chewingTimeline
        case mealReport
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
        chewingTimeline: String? = nil,
        mealReport: MealReportDTO? = nil,
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
        self.chewingTimeline = chewingTimeline
        self.mealReport = mealReport
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
        chewingTimeline = try container.decodeIfPresent(String.self, forKey: .chewingTimeline)
        mealReport = try container.decodeIfPresent(MealReportDTO.self, forKey: .mealReport)
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
        try container.encodeIfPresent(chewingTimeline, forKey: .chewingTimeline)
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
    var mealReport: MealReportDTO?
    var chewingSessionAccepted: Bool
    var rewardEligible: Bool
    var ineligibleReason: String?
    var reward: SessionRewardDTO
    var streak: SessionStreakDTO
    var today: SessionTodayDTO
    var userStats: HomeStateDTO
}
