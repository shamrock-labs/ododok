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
    var savedAt: Date

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case userId
        case streak
        case points
        case owned
        case equipped
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
        savedAt: Date,
        userId: String? = nil
    ) {
        self.deviceId = deviceId
        self.userId = userId
        self.streak = streak
        self.points = points
        self.owned = owned
        self.equipped = equipped
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
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(streak, forKey: .streak)
        try container.encode(points, forKey: .points)
        try container.encode(owned, forKey: .owned)
        try container.encode(equipped, forKey: .equipped)
        try container.encode(savedAt, forKey: .savedAt)
    }
}
