import Foundation

/// Spring 백엔드(Tailscale staging) 접속 설정.
/// baseURL 예: http://100.99.252.124:8080
/// 토큰이 있으면 Authorization Bearer를 붙이고, 없으면 X-Device-Id 폴백으로 호출한다.
struct SpringConfig {
    let baseURL: URL
}

/// Spring REST 백엔드 구현체.
///
/// InsForge(PostgREST)와의 주요 차이점:
///   - 공통 응답 wrapping — 성공 응답은 `{code, message, result}` 형태이고, 실제 데이터는
///     `result`에 들어 있다. 조회 메서드는 `BaseResponse<T>`로 디코드한 뒤 `result`를 꺼낸다.
///     에러는 `{code, message}` wrapping + 4xx/5xx 상태코드로 내려온다.
///   - JSON key 변환 없음 — DTO 필드명(camelCase)이 wire format 그대로.
///   - 인증: JWT 우선, 로그인 전/테스트 환경은 X-Device-Id 폴백.
///   - GET retry 없음 — Tailscale IP 직접 접속이라 IPv6 cold-start 회피 불필요.
///   - fetchProfile: Spring은 신규 디바이스에도 200 + displayName=null 반환.
///     displayName이 null이면 nil을 반환 — 호출처(AppState.fetchAndApplyDisplayName)는
///     profile?.displayName이 nil/빈 문자열일 때 온보딩을 열도록 설계되어 있어
///     InsForge의 "row 없음 = nil" 의미와 동일하게 처리할 수 있다.
///   - fetchUserStats: 404 → nil 반환 (첫 기기 등록 전 stats 미존재 정상 케이스).
final class SpringRemoteStore: RemoteStore {
    private static let sessionUploadTimeout: TimeInterval = 8

    private let config: SpringConfig
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// access 만료(401) 시 토큰 재발급용. 로그인/로그아웃 자체는 LoginView가 별도 인스턴스로 호출.
    private let authClient: SpringAuthClient

    /// 서버 공통 응답 wrapping. 성공 응답의 실제 데이터는 `result`에 담긴다.
    /// 본문이 없는 성공(삭제 등)은 result가 생략되므로 옵셔널로 둔다.
    private struct BaseResponse<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let result: T?
    }

    /// 서버 에러 봉투 — 비-2xx 응답의 `{code, message}`(result 없음). 사용자에게 보여줄 사유 추출용.
    private struct BaseErrorResponse: Decodable {
        let code: Int
        let message: String
    }

    private struct AttendanceRequest: Encodable {
        let idempotencyKey: String
    }

    init(config: SpringConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.authClient = SpringAuthClient(config: config, session: session)

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
        _ = try await sendExpectingSuccess(req)
    }

    /// Spring은 신규 디바이스에도 200 + result.displayName=null 반환.
    /// displayName이 null(nil)인 경우 nil을 돌려줘 InsForge의 "row 없음 = nil" 계약을 유지한다.
    /// AppState.fetchAndApplyDisplayName은 nil/빈 문자열 모두 온보딩 미완료로 간주하므로
    /// 동작이 동일하다.
    func fetchProfile(deviceId: String) async throws -> ProfileDTO? {
        let req = jsonRequest(method: "GET", path: "/v1/me/profile", deviceId: deviceId)
        let data = try await sendExpectingSuccess(req)
        // result 없음 또는 displayName == nil → 신규 디바이스, 호출처가 기대하는 "등록 전" 의미로 nil.
        guard let dto = try decodeOptionalResult(ProfileDTO.self, from: data), dto.displayName != nil else { return nil }
        return dto
    }

    // MARK: - user_stats

    /// 404 → nil (첫 기기 등록 전 stats 없음은 정상). 200 → wrapping의 result 디코드.
    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO? {
        let req = jsonRequest(method: "GET", path: "/v1/me/stats", deviceId: deviceId)
        let (data, http) = try await send(req)
        if http.statusCode == 404 { return nil }
        try validateSuccess(statusCode: http.statusCode, data: data)
        return try decodeOptionalResult(UserStatsDTO.self, from: data)
    }

    // MARK: - user data

    func deleteUserData(deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me", deviceId: deviceId)
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - chewing_session

    /// 정책 엔드포인트 — 세션 저장 + 서버 계산 적립/스트릭/오늘/홈을 한 번에 받는다.
    /// 같은 id 재전송은 서버가 멱등 처리(reward는 idempotentReplay=true).
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        var req = jsonRequest(method: "POST", path: "/v1/me/chewing-sessions", deviceId: session.deviceId)
        req.timeoutInterval = Self.sessionUploadTimeout
        req.httpBody = try encoder.encode(session)
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(CreateSessionResultDTO.self, from: data)
    }

    func fetchHome(deviceId: String) async throws -> HomeStateDTO {
        let req = jsonRequest(method: "GET", path: "/v1/me/home", deviceId: deviceId)
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(HomeStateDTO.self, from: data)
    }

    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        var req = jsonRequest(method: "POST", path: "/v1/me/attendance", deviceId: deviceId)
        req.httpBody = try encoder.encode(AttendanceRequest(idempotencyKey: idempotencyKey))
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(AttendanceResultDTO.self, from: data)
    }

    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] {
        let sinceIso = Self.isoFormatter.string(from: since)
        // since/until 값에 +, : 가 포함되어 URL 인코딩 필수.
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
        let data = try await sendExpectingSuccess(req)
        return try decodeOptionalResult([ChewingSessionDTO].self, from: data) ?? []
    }

    func deleteChewingSession(id: UUID, deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me/sessions/\(id.uuidString.lowercased())", deviceId: deviceId)
        // device 불일치도 성공(204→200) 반환 — 멱등 설계.
        _ = try await sendExpectingSuccess(req)
    }

    func deleteAllChewingSessions(deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me/sessions", deviceId: deviceId)
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - imu CSV

    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String {
        let path = "/v1/me/sessions/\(sessionId.uuidString.lowercased())/imu"
        var req = baseRequest(method: "POST", path: path, deviceId: deviceId)
        req.timeoutInterval = Self.sessionUploadTimeout
        req.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        req.httpBody = csvData
        let data = try await sendExpectingSuccess(req)
        struct UploadResult: Decodable { let key: String }
        return try decodeResult(UploadResult.self, from: data).key
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
        // ODO-47: 로그인 토큰이 있으면 Bearer 첨부(서버는 JWT 우선, 없으면 X-Device-Id 폴백).
        if let token = TokenManager.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// 2xx 성공을 기대하는 전송. Spring 엔드포인트는 200/201(생성)/멱등 200이 섞여 있고
    /// 삭제도 wrapping 때문에 204가 아니라 200이라, 정확한 코드 대신 2xx 범위로 검사한다.
    @discardableResult
    private func sendExpectingSuccess(_ req: URLRequest) async throws -> Data {
        let (data, http) = try await send(req)
        try validateSuccess(statusCode: http.statusCode, data: data)
        return data
    }

    private func send(_ req: URLRequest, retryingOn401: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            // Task 취소(화면 이탈 등)는 오프라인이 아니다. CancellationError로 전파해
            // "인터넷 연결 확인" 오안내를 막는다.
            if error.code == .cancelled { throw CancellationError() }
            // 응답 자체가 오지 않음(연결 실패/타임아웃) → 오프라인으로 통일. 호출처는 캐시 fallback.
            throw RemoteStoreError.offline
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.malformed("no HTTP response")
        }
        // ODO-47: access 만료(401) 처리. refresh 보유 시 1회 재발급 후 원요청 재시도하고,
        // 재시도 후에도 401이면 만료로 확정해 authExpired를 던진다(AppState가 로그인 게이트로 내려보냄).
        if http.statusCode == 401 {
            guard retryingOn401 else { throw RemoteStoreError.authExpired }
            guard TokenManager.refreshToken != nil else { throw RemoteStoreError.authExpired }
            guard await authClient.refresh() else { throw RemoteStoreError.authExpired }
            var retried = req
            if let token = TokenManager.accessToken {
                retried.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await send(retried, retryingOn401: false)
        }
        return (data, http)
    }

    private func validateSuccess(statusCode: Int, data: Data) throws {
        guard (200..<300).contains(statusCode) else {
            throw decodeError(statusCode: statusCode, data: data)
        }
    }

    private func decodeError(statusCode: Int, data: Data) -> RemoteStoreError {
        if let envelope = try? decoder.decode(BaseErrorResponse.self, from: data) {
            return .server(status: statusCode, code: envelope.code, message: envelope.message)
        }
        return .http(status: statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }

    private func decodeOptionalResult<T: Decodable>(_ type: T.Type, from data: Data) throws -> T? {
        do {
            return try decoder.decode(BaseResponse<T>.self, from: data).result
        } catch {
            throw RemoteStoreError.malformed("decode failed: \(error)")
        }
    }

    /// BaseResponse<T> 본문을 디코드. 파싱 실패/`result` 누락은 malformed로 변환해, 2xx인데
    /// "잘못 온" 응답을 호출처가 일관되게 처리(친화 메시지 + 재시도)하게 한다.
    private func decodeResult<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            guard let result = try decoder.decode(BaseResponse<T>.self, from: data).result else {
                throw RemoteStoreError.malformed("empty result")
            }
            return result
        } catch let error as RemoteStoreError {
            throw error
        } catch {
            throw RemoteStoreError.malformed("decode failed: \(error)")
        }
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
