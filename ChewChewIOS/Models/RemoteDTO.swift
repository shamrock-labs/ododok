import Foundation

/// `user_progress` row와 1:1로 매핑되는 DTO. 기존 PersistedSnapshot(`AppState.swift`)이
/// JSON Blob으로 갖고 있던 필드 그대로를 컬럼 단위로 풀어놓은 것.
///
/// snake_case ↔ camelCase 매핑은 PostgREST 호출부에서 keyEncodingStrategy로 처리한다.
struct ProgressDTO: Codable, Equatable {
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
}

/// AirPods CMDeviceMotion에서 받은 한 샘플의 추론용 6채널 + 시간.
/// CSV 직렬화 전용이라 Codable 불필요. 학습 레포 18컬럼 중 실제 추론에 쓰이는 것만.
struct IMURow {
    let tRelSec: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let userAccelX: Double
    let userAccelY: Double
    let userAccelZ: Double

    static let csvHeader =
        "t_rel_sec,rotation_x,rotation_y,rotation_z,user_accel_x,user_accel_y,user_accel_z"

    /// CSV 한 줄. Double은 `%.6f` 고정 — Locale 영향 없도록 C locale 포맷터 사용.
    func csvLine() -> String {
        String(
            format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
            tRelSec, rotationX, rotationY, rotationZ, userAccelX, userAccelY, userAccelZ
        )
    }
}
