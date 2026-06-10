import Foundation

/// Spring 백엔드(Tailscale staging) 접속 설정.
/// baseURL 예: http://100.99.252.124:8080
/// 인증 없음 — OAuth/JWT 는 ODO-44에서 추가 예정.
struct SpringConfig {
    let baseURL: URL
}

/// Spring REST 백엔드 구현체.
///
/// InsForge(PostgREST)와의 주요 차이점:
///   - JSON key 변환 없음 — DTO 필드명(camelCase)이 wire format 그대로.
///   - 인증 헤더 없음 — 모든 요청에 X-Device-Id 헤더만 첨부.
///   - GET retry 없음 — Tailscale IP 직접 접속이라 IPv6 cold-start 회피 불필요.
///   - fetchProfile: Spring은 신규 디바이스에도 200 + displayName=null 반환.
///     displayName이 null이면 nil을 반환 — 호출처(AppState.fetchAndApplyDisplayName)는
///     profile?.displayName이 nil/빈 문자열일 때 온보딩을 열도록 설계되어 있어
///     InsForge의 "row 없음 = nil" 의미와 동일하게 처리할 수 있다.
///   - fetchUserStats: 404 → nil 반환 (첫 기기 등록 전 stats 미존재 정상 케이스).
final class SpringRemoteStore: RemoteStore {
    private let config: SpringConfig
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(config: SpringConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session

        let enc = JSONEncoder()
        // camelCase 그대로 — convertToSnakeCase 사용 안 함.
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Self.isoFormatter.string(from: date))
        }
        self.encoder = enc

        let dec = JSONDecoder()
        // camelCase 그대로 — convertFromSnakeCase 사용 안 함.
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = Self.isoFormatter.date(from: s) { return d }
            if let d = Self.isoFormatterNoFractional.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid ISO8601: \(s)")
        }
        self.decoder = dec
    }

    // MARK: - profile

    func upsertProfile(_ profile: ProfileDTO) async throws {
        var req = jsonRequest(method: "PUT", path: "/v1/me/profile", deviceId: profile.deviceId)
        req.httpBody = try encoder.encode(profile)
        _ = try await sendExpectingStatus(req, expected: 200)
    }

    /// Spring은 신규 디바이스에도 200 + displayName=null 반환.
    /// displayName이 null(nil)인 경우 nil을 돌려줘 InsForge의 "row 없음 = nil" 계약을 유지한다.
    /// AppState.fetchAndApplyDisplayName은 nil/빈 문자열 모두 온보딩 미완료로 간주하므로
    /// 동작이 동일하다.
    func fetchProfile(deviceId: String) async throws -> ProfileDTO? {
        let req = jsonRequest(method: "GET", path: "/v1/me/profile", deviceId: deviceId)
        let data = try await sendExpectingStatus(req, expected: 200)
        let dto = try decoder.decode(ProfileDTO.self, from: data)
        // displayName == nil → 신규 디바이스, 호출처가 기대하는 "등록 전" 의미로 nil 반환.
        guard dto.displayName != nil else { return nil }
        return dto
    }

    // MARK: - user_stats

    func upsertUserStats(_ stats: UserStatsDTO) async throws {
        var req = jsonRequest(method: "PUT", path: "/v1/me/stats", deviceId: stats.deviceId)
        req.httpBody = try encoder.encode(stats)
        _ = try await sendExpectingStatus(req, expected: 200)
    }

    /// 404 → nil (첫 기기 등록 전 stats 없음은 정상).
    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO? {
        let req = jsonRequest(method: "GET", path: "/v1/me/stats", deviceId: deviceId)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.http(status: -1, body: "no response")
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteStoreError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(UserStatsDTO.self, from: data)
    }

    // MARK: - user data

    func deleteUserData(deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me", deviceId: deviceId)
        _ = try await sendExpectingStatus(req, expected: 204)
    }

    // MARK: - chewing_session

    func insertSession(_ session: ChewingSessionDTO) async throws {
        var req = jsonRequest(method: "POST", path: "/v1/me/sessions", deviceId: session.deviceId)
        req.httpBody = try encoder.encode(session)
        _ = try await sendExpectingStatus(req, expected: 201)
    }

    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] {
        let sinceIso = Self.isoFormatter.string(from: since)
        // since/until 값에 +, : が含まれるため URL エンコード必須.
        guard let encodedSince = sinceIso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw RemoteStoreError.http(status: -1, body: "failed to percent-encode since value")
        }
        var path = "/v1/me/sessions?since=\(encodedSince)"
        if let until {
            let untilIso = Self.isoFormatter.string(from: until)
            guard let encodedUntil = untilIso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw RemoteStoreError.http(status: -1, body: "failed to percent-encode until value")
            }
            path += "&until=\(encodedUntil)"
        }
        let req = jsonRequest(method: "GET", path: path, deviceId: deviceId)
        let data = try await sendExpectingStatus(req, expected: 200)
        return try decoder.decode([ChewingSessionDTO].self, from: data)
    }

    func deleteChewingSession(id: UUID, deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me/sessions/\(id.uuidString.lowercased())", deviceId: deviceId)
        // device 불일치도 204 반환 — 멱등 설계.
        _ = try await sendExpectingStatus(req, expected: 204)
    }

    func deleteAllChewingSessions(deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me/sessions", deviceId: deviceId)
        _ = try await sendExpectingStatus(req, expected: 204)
    }

    // MARK: - imu CSV

    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String {
        let path = "/v1/me/sessions/\(sessionId.uuidString.lowercased())/imu"
        var req = baseRequest(method: "POST", path: path, deviceId: deviceId)
        req.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        req.httpBody = csvData
        let data = try await sendExpectingStatus(req, expected: 200)
        struct UploadResponse: Decodable { let key: String }
        let resp = try JSONDecoder().decode(UploadResponse.self, from: data)
        return resp.key
    }

    // MARK: - Helpers

    /// JSON Content-Type 포함 요청 빌더.
    private func jsonRequest(method: String, path: String, deviceId: String) -> URLRequest {
        var req = baseRequest(method: method, path: path, deviceId: deviceId)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    /// 공통 요청 빌더 — X-Device-Id 헤더 첨부.
    private func baseRequest(method: String, path: String, deviceId: String) -> URLRequest {
        var base = config.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        let url = URL(string: base + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        return req
    }

    /// 단일 expected 상태코드를 expect하는 전송. 범위가 아닌 정확한 코드 비교 — Spring API는
    /// 각 엔드포인트별 코드가 확정되어 있으므로 엄격하게 검사한다.
    @discardableResult
    private func sendExpectingStatus(_ req: URLRequest, expected: Int) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.http(status: -1, body: "no response")
        }
        guard http.statusCode == expected else {
            throw RemoteStoreError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Date formatters
    //
    // 송신: fractional seconds 포함 ISO8601.
    // 수신: fractional 유무 둘 다 허용 (InsForgeRemoteStore 패턴 재사용).

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
