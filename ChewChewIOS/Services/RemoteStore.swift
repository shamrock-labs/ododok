import Foundation

/// 원격 영속화 추상화. AppState는 이 프로토콜에만 의존해서, 시뮬레이터/유닛테스트에서
/// `NoopRemoteStore`로 갈아끼울 수 있다.
///
/// ODO-54 이후 도토리/스트릭/오늘완료/출석 정본은 서버 정책 엔드포인트다
/// (`createChewingSession`·`fetchHome`·`earnAttendance`). 아래 profiles/user_stats 접근은
/// 신원 보장과 레거시 읽기용이다.
///   profiles: 디바이스 신원 — `upsertProfile`로 최초 1회 보장.
///   user_stats: 도토리/스트릭 정본은 서버. iOS는 푸시하지 않고 `fetchUserStats`로 읽기만 한다.
/// 삭제는 `deleteUserData` 한 번 (profiles → user_stats FK ON DELETE CASCADE).
protocol RemoteStore {
    func upsertProfile(_ profile: ProfileDTO) async throws
    /// 로그인 계정(JWT)에 매칭되는 profile 행 1개 조회. 신규 사용자면 nil.
    /// `displayName` 등 사용자 식별 정보 로딩에 사용. 서버는 JWT(user_id)로만 스코프한다.
    func fetchProfile() async throws -> ProfileDTO?
    func fetchUserStats() async throws -> UserStatsDTO?
    func deleteUserData() async throws
    /// 정책 세션 저장 — 세션을 저장하고 서버가 계산한 적립/스트릭/오늘/홈을 함께 받는다.
    /// 도토리·스트릭·오늘완료 정본은 서버이므로 iOS는 응답값을 표시만 한다(재계산 금지).
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO
    /// 홈 상태 조회 — 서버가 계산한 도토리/스트릭/오늘 진행도.
    func fetchHome(deviceId: String) async throws -> HomeStateDTO
    /// 앱-열기 출석 적립 — iOS가 멱등키로 트리거, 서버가 일 1회 판정 + 적립.
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO
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
    func fetchProfile() async throws -> ProfileDTO? { nil }
    func fetchUserStats() async throws -> UserStatsDTO? { nil }
    func deleteUserData() async throws {}
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        CreateSessionResultDTO(
            chewingSession: session,
            chewingSessionAccepted: true,
            rewardEligible: false,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 0, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 0, event: "NONE", freezeInventory: 0),
            today: SessionTodayDTO(completed: false),
            userStats: .empty(deviceId: session.deviceId)
        )
    }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO { .empty(deviceId: deviceId) }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        AttendanceResultDTO(grantedPoints: 0, capped: false, idempotentReplay: false, userStats: .empty(deviceId: deviceId))
    }
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
    /// access 만료 후 refresh까지 실패한 상태. 로컬 세션을 종료하고 로그인 게이트로 내려야 한다.
    case authExpired
    /// 서버 표준 에러 봉투(`{code, message}`) 응답. message는 서버가 준 한국어 사유.
    case server(status: Int, code: Int, message: String)
    /// 응답 자체가 오지 않음 — 연결 실패/타임아웃(오프라인).
    case offline
    /// 2xx인데 본문 파싱 실패 또는 예기치 않은 형식("잘못 온" 응답).
    case malformed(String)
    /// 표준 봉투로 파싱되지 않은 비-2xx 응답(원시 body 보존).
    case http(status: Int, body: String)
    case invalidUploadResponse

    var description: String {
        switch self {
        case .authExpired: return "RemoteStoreError.authExpired"
        case .server(let s, let c, let m): return "RemoteStoreError.server(http=\(s), code=\(c)): \(m)"
        case .offline: return "RemoteStoreError.offline"
        case .malformed(let d): return "RemoteStoreError.malformed: \(d)"
        case .http(let s, let b): return "RemoteStoreError.http(\(s)): \(b)"
        case .invalidUploadResponse: return "RemoteStoreError.invalidUploadResponse"
        }
    }

    /// 사용자에게 보여줄 친화적 한국어 안내. 서버 원문(`server.message`)은 개발용이라 그대로
    /// 노출하지 않고(로그는 `description`에 남음), 사용자에겐 부드러운 카피로 통일한다.
    var userMessage: String {
        switch self {
        case .authExpired:
            return "다시 로그인해 주세요."
        case .offline:
            return "인터넷 연결을 확인해 주세요."
        case .server, .http, .malformed, .invalidUploadResponse:
            return "잠시 후 다시 시도해 주세요."
        }
    }

    /// 재시도가 의미 있는 오류인지. 네트워크/서버 일시 오류(offline·5xx·파싱 실패)는 true,
    /// 잘못된 요청(4xx)은 재시도해도 똑같이 실패하므로 false.
    var isRetriable: Bool {
        switch self {
        case .authExpired:
            return false
        case .offline, .malformed, .invalidUploadResponse:
            return true
        case .server(let status, _, _), .http(let status, _):
            return status >= 500
        }
    }
}

/// InsForge REST 백엔드 구현. PostgREST 스타일 DB + 3단계 Storage 업로드(strategy → upload → confirm).
final class InsForgeRemoteStore: RemoteStore {
    private static let sessionUploadTimeout: TimeInterval = 8

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

    func fetchProfile() async throws -> ProfileDTO? {
        let deviceId = DeviceIdentity.shared
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "GET",
            path: "/api/database/records/profiles?device_id=eq.\(escaped)&limit=1"
        )
        let data = try await sendGETExpectingSuccessWithRetry(req)
        let rows = try decoder.decode([ProfileDTO].self, from: data)
        return rows.first
    }

    func fetchUserStats() async throws -> UserStatsDTO? {
        let deviceId = DeviceIdentity.shared
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "GET",
            path: "/api/database/records/user_stats?device_id=eq.\(escaped)&limit=1"
        )
        let data = try await sendGETExpectingSuccessWithRetry(req)
        let rows = try decoder.decode([UserStatsDTO].self, from: data)
        return rows.first
    }

    /// profiles 삭제 → FK ON DELETE CASCADE로 user_stats도 함께 제거.
    func deleteUserData() async throws {
        let deviceId = DeviceIdentity.shared
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "DELETE",
            path: "/api/database/records/profiles?device_id=eq.\(escaped)"
        )
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - chewing_session

    private func insertSession(_ session: ChewingSessionDTO) async throws {
        var req = try jsonRequest(method: "POST", path: "/api/database/records/chewing_session")
        req.httpBody = try encoder.encode([session])
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - 서버 권위 응답 (레거시 비지원)
    //
    // InsForge엔 적립/스트릭/오늘완료 정책 엔진이 없다. 세션은 그대로 INSERT하되 리워드는
    // 중립(0)으로 돌려주고, 홈은 user_stats에 저장된 도토리/스트릭만 반영한다. thin-client
    // 보상 UX는 Spring 백엔드에서만 동작한다(`-useInsForge`는 데이터 접근용 레거시 경로).

    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        try await insertSession(session)
        let stats = try? await fetchUserStats()
        return CreateSessionResultDTO(
            chewingSession: session,
            chewingSessionAccepted: true,
            rewardEligible: false,
            ineligibleReason: "LEGACY_BACKEND",
            reward: SessionRewardDTO(grantedPoints: 0, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: stats?.streak ?? 0, event: "NONE", freezeInventory: 0),
            today: SessionTodayDTO(completed: false),
            userStats: Self.legacyHome(deviceId: session.deviceId, stats: stats)
        )
    }

    // fetch 실패(오프라인 등)는 throw로 전파한다. 0짜리 홈을 "성공"으로 돌려주면 applyHome이
    // 마지막 성공 캐시를 0으로 덮어쓰고 영속하기 때문(keep-last-good 계약 위반). 신규 디바이스의
    // "행 없음"(nil)만 0 홈으로 변환한다.

    func fetchHome(deviceId: String) async throws -> HomeStateDTO {
        let stats = try await fetchUserStats()
        return Self.legacyHome(deviceId: deviceId, stats: stats)
    }

    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        let stats = try await fetchUserStats()
        return AttendanceResultDTO(
            grantedPoints: 0,
            capped: false,
            idempotentReplay: true,
            userStats: Self.legacyHome(deviceId: deviceId, stats: stats)
        )
    }

    /// 저장된 user_stats(있으면)의 도토리/스트릭만 반영한 레거시 홈. 오늘 진행도는 미계산.
    private static func legacyHome(deviceId: String, stats: UserStatsDTO?) -> HomeStateDTO {
        HomeStateDTO(
            deviceId: deviceId,
            displayName: nil,
            points: stats?.points ?? 0,
            streak: stats?.streak ?? 0,
            freezeInventory: 0,
            todayRealChewCount: 0,
            dailyGoal: 0,
            todayProgress: 0,
            todayCompleted: false
        )
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
        let data = try await sendGETExpectingSuccessWithRetry(req)
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
        req.timeoutInterval = Self.sessionUploadTimeout
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
        req.timeoutInterval = Self.sessionUploadTimeout
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
        req.timeoutInterval = Self.sessionUploadTimeout
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

    /// idempotent GET 전용 retry — InsForge 호스트가 IPv6 AAAA record 없어 iOS의 IPv6
    /// 우선 시도가 NoSuchRecord throw로 끝나는 cold-start race를 회피. 첫 시도 실패 시
    /// 1초 대기 후 1회 재시도하면 NSURLSession이 A record로 fallback해 보통 성공한다.
    /// POST/DELETE에는 사용 금지 — 재시도가 중복 부작용을 만들 수 있다.
    private func sendGETExpectingSuccessWithRetry(_ req: URLRequest) async throws -> Data {
        do {
            return try await sendExpectingSuccess(req)
        } catch {
            try? await Task.sleep(for: .seconds(1))
            return try await sendExpectingSuccess(req)
        }
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
