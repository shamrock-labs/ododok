import Foundation

/// 원격 영속화 추상화. AppState는 이 프로토콜에만 의존해서, 시뮬레이터/유닛테스트에서
/// `NoopRemoteStore`로 갈아끼울 수 있다.
///
/// 게임 상태는 두 테이블로 분리되어 있다 (`profiles` + `user_stats`).
///   profiles: 디바이스 신원 — `upsertProfile`로 최초 1회 보장.
///   user_stats: 게임 진행 상태 — 매 mutate 시 `upsertUserStats`로 동기화.
/// 삭제는 `deleteUserData` 한 번 (profiles → user_stats FK ON DELETE CASCADE).
protocol RemoteStore {
    func upsertProfile(_ profile: ProfileDTO) async throws
    /// 디바이스 식별자에 매칭되는 profile 행 1개 조회. 신규 디바이스면 nil.
    /// `displayName` 등 사용자 식별 정보 로딩에 사용.
    func fetchProfile(deviceId: String) async throws -> ProfileDTO?
    func upsertUserStats(_ stats: UserStatsDTO) async throws
    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO?
    func deleteUserData(deviceId: String) async throws
    func insertSession(_ session: ChewingSessionDTO) async throws
    /// `since` 이후 + 옵셔널 `until` 이전에 시작된 세션을 시간 오름차순으로 조회.
    /// "오늘의 식사 기록"은 since=오늘 0시 / until=nil, 월간 캘린더는 since=월 첫날 /
    /// until=다음 달 첫날로 호출.
    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO]
    /// 단일 세션 삭제 (swipe 삭제). device_id 매칭을 추가로 걸어 안전장치.
    func deleteChewingSession(id: UUID, deviceId: String) async throws
    /// 이 기기의 모든 chewing_session 일괄 삭제. profiles/user_stats는 보존 — 게임
    /// 진행 상태는 남김.
    func deleteAllChewingSessions(deviceId: String) async throws
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String
}

extension RemoteStore {
    /// 상한 없는 편의 메서드 — `fetchChewingSessions(deviceId:since:until:)`에 `until: nil`을
    /// 위임. 기존 "오늘의 식사 기록" 호출자(`AppState.fetchTodaySessions`) 그대로 사용.
    func fetchChewingSessions(deviceId: String, since: Date) async throws -> [ChewingSessionDTO] {
        try await fetchChewingSessions(deviceId: deviceId, since: since, until: nil)
    }
}

struct NoopRemoteStore: RemoteStore {
    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile(deviceId: String) async throws -> ProfileDTO? { nil }
    func upsertUserStats(_ stats: UserStatsDTO) async throws {}
    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO? { nil }
    func deleteUserData(deviceId: String) async throws {}
    func insertSession(_ session: ChewingSessionDTO) async throws {}
    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String { "" }
}

struct InsForgeConfig {
    let baseURL: URL
    let apiKey: String
}

enum RemoteStoreError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case invalidUploadResponse

    var description: String {
        switch self {
        case .http(let s, let b): return "RemoteStoreError.http(\(s)): \(b)"
        case .invalidUploadResponse: return "RemoteStoreError.invalidUploadResponse"
        }
    }
}

/// InsForge REST 백엔드 구현. PostgREST 스타일 DB + 3단계 Storage 업로드(strategy → upload → confirm).
final class InsForgeRemoteStore: RemoteStore {
    private let config: InsForgeConfig
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(config: InsForgeConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Self.isoFormatter.string(from: date))
        }
        self.encoder = enc

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = Self.isoFormatter.date(from: s) { return d }
            if let d = Self.isoFormatterNoFractional.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid ISO8601: \(s)")
        }
        self.decoder = dec
    }

    // MARK: - profiles + user_stats

    func upsertProfile(_ profile: ProfileDTO) async throws {
        var req = try jsonRequest(method: "POST", path: "/api/database/records/profiles")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try encoder.encode([profile])
        _ = try await sendExpectingSuccess(req)
    }

    func fetchProfile(deviceId: String) async throws -> ProfileDTO? {
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "GET",
            path: "/api/database/records/profiles?device_id=eq.\(escaped)&limit=1"
        )
        let data = try await sendExpectingSuccess(req)
        let rows = try decoder.decode([ProfileDTO].self, from: data)
        return rows.first
    }

    func upsertUserStats(_ stats: UserStatsDTO) async throws {
        var req = try jsonRequest(method: "POST", path: "/api/database/records/user_stats")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try encoder.encode([stats])
        _ = try await sendExpectingSuccess(req)
    }

    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO? {
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "GET",
            path: "/api/database/records/user_stats?device_id=eq.\(escaped)&limit=1"
        )
        let data = try await sendExpectingSuccess(req)
        let rows = try decoder.decode([UserStatsDTO].self, from: data)
        return rows.first
    }

    /// profiles 삭제 → FK ON DELETE CASCADE로 user_stats도 함께 제거.
    func deleteUserData(deviceId: String) async throws {
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "DELETE",
            path: "/api/database/records/profiles?device_id=eq.\(escaped)"
        )
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - chewing_session

    func insertSession(_ session: ChewingSessionDTO) async throws {
        var req = try jsonRequest(method: "POST", path: "/api/database/records/chewing_session")
        req.httpBody = try encoder.encode([session])
        _ = try await sendExpectingSuccess(req)
    }

    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] {
        let escapedDevice = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let sinceIso = Self.isoFormatter.string(from: since)
        let escapedSince = sinceIso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sinceIso
        // 같은 컬럼에 두 조건이 필요한 경우 PostgREST는 query string 같은 key 중복을
        // 마지막 값으로만 처리하는 클라이언트가 있어 둘 다 보장되지 않을 수 있다.
        // `and=(a,b)` 명시 grouping을 쓰면 두 조건이 확실히 AND로 묶인다.
        var path: String
        if let until {
            let untilIso = Self.isoFormatter.string(from: until)
            let escapedUntil = untilIso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? untilIso
            let andClause = "and=(started_at.gte.\(escapedSince),started_at.lt.\(escapedUntil))"
            path = "/api/database/records/chewing_session?device_id=eq.\(escapedDevice)&\(andClause)"
        } else {
            path = "/api/database/records/chewing_session?device_id=eq.\(escapedDevice)&started_at=gte.\(escapedSince)"
        }
        path += "&order=started_at.asc"
        let req = try jsonRequest(method: "GET", path: path)
        let data = try await sendExpectingSuccess(req)
        return try decoder.decode([ChewingSessionDTO].self, from: data)
    }

    func deleteChewingSession(id: UUID, deviceId: String) async throws {
        let escapedDevice = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let idStr = id.uuidString.lowercased()
        let escapedId = idStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? idStr
        let req = try jsonRequest(
            method: "DELETE",
            path: "/api/database/records/chewing_session?id=eq.\(escapedId)&device_id=eq.\(escapedDevice)"
        )
        _ = try await sendExpectingSuccess(req)
    }

    func deleteAllChewingSessions(deviceId: String) async throws {
        let escapedDevice = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "DELETE",
            path: "/api/database/records/chewing_session?device_id=eq.\(escapedDevice)"
        )
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - imu-sessions storage (3-step)

    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String {
        let filename = "\(deviceId)/\(sessionId.uuidString).csv"
        let strategy = try await fetchUploadStrategy(
            bucket: "imu-sessions",
            filename: filename,
            contentType: "text/csv",
            size: csvData.count
        )
        try await performUpload(strategy: strategy, data: csvData)
        if strategy.confirmRequired {
            try await confirmUpload(strategy: strategy, size: csvData.count)
        }
        return strategy.key
    }

    private struct UploadStrategy: Decodable {
        let method: String           // "direct" (local) | "presigned" (S3)
        let uploadUrl: String
        let key: String
        let fields: [String: String]?
        let confirmRequired: Bool
        let confirmUrl: String?
    }

    private func fetchUploadStrategy(
        bucket: String, filename: String, contentType: String, size: Int
    ) async throws -> UploadStrategy {
        var req = try jsonRequest(
            method: "POST",
            path: "/api/storage/buckets/\(bucket)/upload-strategy"
        )
        let body: [String: Any] = [
            "filename": filename,
            "contentType": contentType,
            "size": size
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await sendExpectingSuccess(req)
        return try JSONDecoder().decode(UploadStrategy.self, from: data)
    }

    private func performUpload(strategy: UploadStrategy, data: Data) async throws {
        let boundary = "ChewChew-\(UUID().uuidString)"
        let isPresigned = strategy.method == "presigned"

        let endpoint: URL
        if isPresigned {
            guard let u = URL(string: strategy.uploadUrl) else {
                throw RemoteStoreError.invalidUploadResponse
            }
            endpoint = u
        } else {
            endpoint = resolveURL(strategy.uploadUrl)
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = isPresigned ? "POST" : "PUT"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !isPresigned {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = Self.makeMultipartBody(
            boundary: boundary,
            fields: isPresigned ? (strategy.fields ?? [:]) : [:],
            fileFieldName: "file",
            filename: strategy.key,
            fileContentType: "text/csv",
            fileData: data
        )
        _ = try await sendExpectingSuccess(req)
    }

    private func confirmUpload(strategy: UploadStrategy, size: Int) async throws {
        guard let confirmPath = strategy.confirmUrl else { return }
        var req = try jsonRequest(method: "POST", path: confirmPath, allowAbsolute: true)
        let body: [String: Any] = ["size": size, "contentType": "text/csv"]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - Helpers

    private func jsonRequest(method: String, path: String, allowAbsolute: Bool = false) throws -> URLRequest {
        let url = allowAbsolute && path.hasPrefix("http") ? URL(string: path)! : resolveURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func resolveURL(_ pathOrAbsolute: String) -> URL {
        if let u = URL(string: pathOrAbsolute), u.scheme != nil {
            return u
        }
        var base = config.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + pathOrAbsolute)!
    }

    private func sendExpectingSuccess(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.http(status: -1, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RemoteStoreError.http(status: http.statusCode, body: body)
        }
        return data
    }

    private static func makeMultipartBody(
        boundary: String,
        fields: [String: String],
        fileFieldName: String,
        filename: String,
        fileContentType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        for (key, value) in fields {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(crlf)\(crlf)".utf8))
            body.append(Data("\(value)\(crlf)".utf8))
        }

        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\(crlf)".utf8))
        body.append(Data("Content-Type: \(fileContentType)\(crlf)\(crlf)".utf8))
        body.append(fileData)
        body.append(Data("\(crlf)--\(boundary)--\(crlf)".utf8))
        return body
    }

    // MARK: - Date formatters
    //
    // Postgres `timestamptz`는 보통 millisecond까지 들어있는 ISO8601로 직렬화된다.
    // 송신은 fractional 포함, 수신은 둘 다 시도.

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
