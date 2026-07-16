import Foundation

/// Spring 백엔드(Tailscale staging) 접속 설정.
/// baseURL 예: http://100.99.252.124:8080
/// `/v1/me/*`는 JWT(user_id)로만 스코프하므로 Authorization Bearer만 첨부한다.
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
///   - 인증: JWT(Authorization Bearer)로만 스코프. device 헤더는 보내지 않는다.
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
    private let tokenStore: any AuthTokenStorage
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

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct TokenResult: Decodable {
        let accessToken: String
    }

    private enum AuthorizationSource {
        case tokenManager
        case captured(String?)
    }

    init(
        config: SpringConfig,
        session: URLSession = .shared,
        tokenStore: any AuthTokenStorage = KeychainAuthTokenStorage()
    ) {
        self.config = config
        self.session = session
        self.tokenStore = tokenStore
        self.authClient = SpringAuthClient(config: config, session: session, tokenStore: tokenStore)

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
        var req = jsonRequest(method: "PUT", path: "/v1/me/profile")
        req.httpBody = try encoder.encode(profile)
        _ = try await sendExpectingSuccess(req)
    }

    /// Spring은 신규 디바이스에도 200 + result.displayName=null 반환.
    /// displayName이 null(nil)인 경우 nil을 돌려줘 InsForge의 "row 없음 = nil" 계약을 유지한다.
    /// AppState.fetchAndApplyDisplayName은 nil/빈 문자열 모두 온보딩 미완료로 간주하므로
    /// 동작이 동일하다.
    func fetchProfile() async throws -> ProfileDTO? {
        let req = jsonRequest(method: "GET", path: "/v1/me/profile")
        let data = try await sendExpectingSuccess(req)
        // result 없음 또는 displayName == nil → 신규 디바이스, 호출처가 기대하는 "등록 전" 의미로 nil.
        guard let dto = try decodeOptionalResult(ProfileDTO.self, from: data), dto.displayName != nil else { return nil }
        return dto
    }

    func fetchCurrentChewDetectionProfile(modelVersion: String) async throws -> ChewDetectionProfileDTO? {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "modelVersion", value: modelVersion)]
        guard let query = components.percentEncodedQuery else {
            throw RemoteStoreError.malformed("failed to encode DSP model version")
        }
        let req = jsonRequest(
            method: "GET",
            path: "/v1/me/chew-detection-profiles/current?\(query)"
        )
        let data = try await sendExpectingSuccess(req)
        return try decodeOptionalResult(ChewDetectionProfileDTO.self, from: data)
    }

    func createChewDetectionProfile(
        _ profile: ChewDetectionProfileRequestDTO,
        idempotencyKey: String
    ) async throws -> ChewDetectionProfileDTO {
        var req = jsonRequest(method: "POST", path: "/v1/me/chew-detection-profiles")
        req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        req.httpBody = try encoder.encode(profile)
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(ChewDetectionProfileDTO.self, from: data)
    }

    func resetCurrentChewDetectionProfile(modelVersion: String) async throws {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "modelVersion", value: modelVersion)]
        guard let query = components.percentEncodedQuery else {
            throw RemoteStoreError.malformed("failed to encode DSP model version")
        }
        let req = jsonRequest(
            method: "DELETE",
            path: "/v1/me/chew-detection-profiles/current?\(query)"
        )
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - user_stats

    /// 404 → nil (첫 기기 등록 전 stats 없음은 정상). 200 → wrapping의 result 디코드.
    func fetchUserStats() async throws -> UserStatsDTO? {
        let req = jsonRequest(method: "GET", path: "/v1/me/stats")
        let (data, http) = try await send(req)
        if http.statusCode == 404 { return nil }
        try validateSuccess(statusCode: http.statusCode, data: data)
        return try decodeOptionalResult(UserStatsDTO.self, from: data)
    }

    // MARK: - user data

    func deleteUserData() async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me")
        _ = try await sendExpectingSuccess(req)
    }

    func deleteUserData(accessToken: String?) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me", authorization: .captured(accessToken))
        _ = try await sendExpectingSuccess(req)
    }

    func deleteUserData(accessToken: String?, refreshToken: String?) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me", authorization: .captured(accessToken))
        let (data, http) = try await sendRaw(req)
        if http.statusCode == 401, let refreshToken {
            let refreshedAccessToken = try await refreshAccessToken(refreshToken)
            let retried = jsonRequest(method: "DELETE", path: "/v1/me", authorization: .captured(refreshedAccessToken))
            _ = try await sendExpectingSuccess(retried)
            return
        }
        try validateSuccess(statusCode: http.statusCode, data: data)
    }

    // MARK: - chewing_session

    /// 정책 엔드포인트 — 세션 저장 + 서버 계산 적립/스트릭/오늘/홈을 한 번에 받는다.
    /// 같은 id 재전송은 서버가 멱등 처리(reward는 idempotentReplay=true).
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        var req = jsonRequest(method: "POST", path: "/v1/me/chewing-sessions")
        req.timeoutInterval = Self.sessionUploadTimeout
        req.httpBody = try encoder.encode(session)
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(CreateSessionResultDTO.self, from: data)
    }

    func fetchHome(deviceId: String) async throws -> HomeStateDTO {
        let req = jsonRequest(method: "GET", path: "/v1/me/home")
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(HomeStateDTO.self, from: data)
    }

    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        var req = jsonRequest(method: "POST", path: "/v1/me/attendance")
        req.httpBody = try encoder.encode(AttendanceRequest(idempotencyKey: idempotencyKey))
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(AttendanceResultDTO.self, from: data)
    }

    func fetchRewardHistory() async throws -> [RewardHistoryDTO] {
        let req = jsonRequest(method: "GET", path: "/v1/me/rewards")
        let data = try await sendExpectingSuccess(req)
        return try decodeOptionalResult([RewardHistoryDTO].self, from: data) ?? []
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
        let req = jsonRequest(method: "GET", path: path)
        let data = try await sendExpectingSuccess(req)
        return try decodeOptionalResult([ChewingSessionDTO].self, from: data) ?? []
    }

    func fetchDailyReport(date: String) async throws -> DailyReportDTO {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let query = components.percentEncodedQuery else {
            throw RemoteStoreError.malformed("failed to encode daily report date")
        }
        let req = jsonRequest(method: "GET", path: "/v1/me/reports/daily?\(query)")
        let data = try await sendExpectingSuccess(req)
        let report = try decodeResult(DailyReportDTO.self, from: data)
        guard report.date == date else {
            throw RemoteStoreError.malformed("daily report date does not match requested date")
        }
        guard dailyReportAggregatesAreValid(report) else {
            throw RemoteStoreError.malformed("daily report aggregate contract violation")
        }
        guard report.meals.allSatisfy({
            MealSessionReportability.completeGeneratedReport(
                $0.mealReport,
                sessionId: $0.sessionId
            ) != nil
        }) else {
            throw RemoteStoreError.malformed("daily mealReport contract violation")
        }
        return report
    }

    private func dailyReportAggregatesAreValid(_ report: DailyReportDTO) -> Bool {
        guard report.mealCount == report.meals.count,
              report.totalEatingSeconds.isFinite,
              report.totalEatingSeconds >= 0,
              report.totalChews >= 0,
              report.meals.allSatisfy({
                  $0.durationSec.isFinite && $0.durationSec > 0
                      && ($0.totalChews.map { $0 >= 0 } ?? false)
              }) else { return false }

        let summedDuration = report.meals.reduce(0) { $0 + $1.durationSec }
        let summedChews = report.meals.compactMap(\.totalChews).reduce(0, +)
        guard approximatelyEqual(report.totalEatingSeconds, summedDuration),
              report.totalChews == summedChews else { return false }

        if report.meals.isEmpty {
            return report.totalEatingSeconds == 0
                && report.totalChews == 0
                && report.avgChewRatePerMin == nil
                && report.avgChewingFraction == nil
                && report.avgTotalScore == nil
        }

        return finite(report.avgChewRatePerMin, in: 0...Double.greatestFiniteMagnitude)
            && finite(report.avgChewingFraction, in: 0...1)
            && finite(report.avgTotalScore, in: 0...100)
    }

    private func finite(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        guard let value else { return false }
        return value.isFinite && range.contains(value)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(0.001, abs(rhs) * 0.000_001)
    }

    func deleteChewingSession(id: UUID, deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me/sessions/\(id.uuidString.lowercased())")
        // device 불일치도 성공(204→200) 반환 — 멱등 설계.
        _ = try await sendExpectingSuccess(req)
    }

    func deleteAllChewingSessions(deviceId: String) async throws {
        let req = jsonRequest(method: "DELETE", path: "/v1/me/sessions")
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - imu CSV

    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String {
        let path = "/v1/me/sessions/\(sessionId.uuidString.lowercased())/imu"
        var req = baseRequest(method: "POST", path: path)
        req.timeoutInterval = Self.sessionUploadTimeout
        req.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        req.httpBody = csvData
        let data = try await sendExpectingSuccess(req)
        struct UploadResult: Decodable { let key: String }
        return try decodeResult(UploadResult.self, from: data).key
    }

    func uploadCalibrationArtifacts(_ bundle: CalibrationArtifactBundle) async throws {
        struct UploadTarget: Decodable {
            let type: CalibrationArtifactKind
            let key: String
            let uploadUrl: URL
            let headers: [String: String]
        }
        struct UploadPlan: Decodable {
            let calibrationId: UUID
            let expiresAt: Date
            let uploads: [UploadTarget]
        }

        let path = "/v1/me/calibrations/\(bundle.calibrationId.uuidString.lowercased())/upload-plan"
        let planData = try await sendExpectingSuccess(jsonRequest(method: "POST", path: path))
        let plan = try decodeResult(UploadPlan.self, from: planData)
        let targets = Dictionary(uniqueKeysWithValues: plan.uploads.map { ($0.type, $0) })

        for artifact in bundle.artifacts {
            guard let target = targets[artifact.kind] else {
                throw RemoteStoreError.invalidUploadResponse
            }
            var request = URLRequest(url: target.uploadUrl)
            request.httpMethod = "PUT"
            request.httpBody = artifact.data
            target.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let (responseData, response) = try await sendRaw(request)
            try validateSuccess(statusCode: response.statusCode, data: responseData)
        }
    }

    // MARK: - push (ODO-56)

    func registerPushToken(_ token: String, environment: String) async throws {
        var req = jsonRequest(method: "POST", path: "/v1/me/push-tokens")
        req.httpBody = try encoder.encode(
            PushTokenRegisterRequestDTO(token: token, platform: "ios", environment: environment)
        )
        _ = try await sendExpectingSuccess(req)
    }

    func deactivatePushToken(_ token: String) async throws {
        // APNs device token은 hex라 path에 그대로 실어도 URL-safe.
        let req = jsonRequest(method: "DELETE", path: "/v1/me/push-tokens/\(token)")
        _ = try await sendExpectingSuccess(req)
    }

    func upsertMealNotifications(_ settings: MealReminderSettings, timeZone: String) async throws {
        var req = jsonRequest(method: "PUT", path: "/v1/me/meal-notifications")
        req.httpBody = try encoder.encode(
            MealNotificationsRequestDTO(timeZone: timeZone, slots: settings.toServerSlots())
        )
        _ = try await sendExpectingSuccess(req)
    }

    /// 미설정(404) → nil. 200 → wrapping result를 끼니 설정으로 복원.
    func fetchMealNotifications() async throws -> MealReminderSettings? {
        let req = jsonRequest(method: "GET", path: "/v1/me/meal-notifications")
        let (data, http) = try await send(req)
        if http.statusCode == 404 { return nil }
        try validateSuccess(statusCode: http.statusCode, data: data)
        let dto = try decodeResult(MealNotificationsResponseDTO.self, from: data)
        return MealReminderSettings(serverSlots: dto.slots)
    }

    // MARK: - friend

    func fetchFriendInviteCode() async throws -> FriendInviteCodeDTO {
        let req = jsonRequest(method: "GET", path: "/v1/me/friends/invite-code")
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(FriendInviteCodeDTO.self, from: data)
    }

    func acceptFriendInvite(code: String) async throws -> FriendAcceptResultDTO {
        var req = jsonRequest(method: "POST", path: "/v1/me/friends/accept")
        req.httpBody = try encoder.encode(["code": code])
        let data = try await sendExpectingSuccess(req)
        return try decodeResult(FriendAcceptResultDTO.self, from: data)
    }

    func fetchFriendRanking() async throws -> [FriendRankingDTO] {
        let req = jsonRequest(method: "GET", path: "/v1/me/friends/ranking")
        let data = try await sendExpectingSuccess(req)
        return try decodeOptionalResult([FriendRankingDTO].self, from: data) ?? []
    }

    // MARK: - Helpers

    /// JSON Content-Type 포함 요청 빌더.
    private func jsonRequest(
        method: String,
        path: String,
        authorization: AuthorizationSource = .tokenManager
    ) -> URLRequest {
        var req = baseRequest(method: method, path: path, authorization: authorization)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    /// 공통 요청 빌더 — JWT Bearer 첨부. `/v1/me/*`는 user_id로만 스코프하므로 device 헤더는 보내지 않는다.
    private func baseRequest(
        method: String,
        path: String,
        authorization: AuthorizationSource = .tokenManager
    ) -> URLRequest {
        var base = config.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        let url = URL(string: base + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        // ODO-47: 로그인 토큰이 있으면 Bearer 첨부.
        let token: String?
        switch authorization {
        case .tokenManager:
            token = tokenStore.accessToken
        case .captured(let capturedToken):
            token = capturedToken
        }
        if let token {
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
        let (data, http) = try await sendRaw(req)
        // ODO-47: access 만료(401) 처리. refresh 보유 시 1회 재발급 후 원요청 재시도하고,
        // 재시도 후에도 401이면 만료로 확정해 authExpired를 던진다(AppState가 로그인 게이트로 내려보냄).
        if http.statusCode == 401 {
            guard retryingOn401 else { throw RemoteStoreError.authExpired }
            guard tokenStore.refreshToken != nil else { throw RemoteStoreError.authExpired }
            guard await authClient.refresh() else { throw RemoteStoreError.authExpired }
            var retried = req
            if let token = tokenStore.accessToken {
                retried.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await send(retried, retryingOn401: false)
        }
        return (data, http)
    }

    private func sendRaw(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        return (data, http)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        var req = jsonRequest(method: "POST", path: "/auth/refresh", authorization: .captured(nil))
        req.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))
        let (data, http) = try await sendRaw(req)
        try validateSuccess(statusCode: http.statusCode, data: data)
        return try decodeResult(TokenResult.self, from: data).accessToken
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
