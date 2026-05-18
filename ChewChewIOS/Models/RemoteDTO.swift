import Foundation

/// `profiles` row와 1:1 매핑되는 DTO. 디바이스 신원 메타.
/// display_name은 향후 사용을 위해 비워둠.
struct ProfileDTO: Codable, Equatable {
    var deviceId: String
    var displayName: String?
}

/// `user_stats` row와 1:1 매핑되는 DTO. 게임 진행 상태(카운터 + 인벤토리 + 플래그)를 보관.
/// 기존 PersistedSnapshot(`AppState.swift`)이 JSON Blob으로 갖고 있던 필드를 컬럼 단위로 풀어놓은 것.
///
/// snake_case ↔ camelCase 매핑은 PostgREST 호출부에서 keyEncodingStrategy로 처리한다.
struct UserStatsDTO: Codable, Equatable {
    var deviceId: String
    var chewCount: Int
    var streak: Int
    var points: Int
    var weeklyScores: [Int]
    var goalAlreadyHit: Bool
    var owned: [String]
    var equipped: EquippedDTO
    var ownedAcornPacks: [String: Int]
    var savedAt: Date

    struct EquippedDTO: Codable, Equatable {
        var hat: String?
        var glasses: String?
        var acc: String?
    }
}

/// `chewing_session` row와 1:1 DTO. 클라이언트가 한 끼 식사 종료 시 INSERT.
/// raw IMU는 별도로 imu-sessions 버킷에 gzip CSV로 올리고 `storagePath`에 경로만 보관.
///
/// 분석 5필드(`chewingSeconds`/`restSeconds`/`chewingFraction`/`estimatedTotalChews`/`modelVersion`)는
/// 온디바이스 ChewingPredictor 추론이 동작한 세션에서만 채워진다. 시뮬레이터/AirPods 미연결 등
/// 추론이 돌지 않은 세션은 모두 nil — DB 컬럼도 nullable.
struct ChewingSessionDTO: Codable, Equatable {
    var id: UUID
    var deviceId: String
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
