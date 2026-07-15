import Foundation

protocol AuthSessionManaging {
    func logout() async
    /// `/auth/me` 조회 — userId + displayName + onboardingCompleted + alertVolume(서버 원격 알림음 볼륨). 오프라인 등 실패 시 throw.
    func me() async throws -> (userId: String, displayName: String?, onboardingCompleted: Bool, alertVolume: Double?)
}

struct NoopAuthSessionManager: AuthSessionManaging {
    func logout() async {
        TokenManager.clear()
    }
    func me() async throws -> (userId: String, displayName: String?, onboardingCompleted: Bool, alertVolume: Double?) {
        (userId: "", displayName: nil, onboardingCompleted: false, alertVolume: nil)
    }
}

/// Spring `/auth/*` 클라이언트 — 소셜 로그인 토큰 교환 + 갱신/로그아웃. (ODO-47 OAuth)
/// 발급된 access/refresh는 TokenManager(Keychain)에 저장한다.
/// 서버 응답은 `{code, message, result}` wrapping(SpringRemoteStore와 동일).
final class SpringAuthClient: AuthSessionManaging {
    private let config: SpringConfig
    private let session: URLSession
    private let tokenStore: any AuthTokenStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// 동시 401에서 refresh가 중복 실행되는 것을 막는 single-flight 코디네이터.
    private let refreshCoordinator = RefreshCoordinator()

    init(
        config: SpringConfig,
        session: URLSession = .shared,
        tokenStore: any AuthTokenStorage = KeychainAuthTokenStorage()
    ) {
        self.config = config
        self.session = session
        self.tokenStore = tokenStore
    }

    private struct LoginRequest: Encodable {
        let provider: String
        let idToken: String
        let deviceId: String?
        let name: String?
    }
    private struct RefreshRequest: Encodable { let refreshToken: String }
    private struct LogoutRequest: Encodable { let refreshToken: String }
    private struct UserDTO: Decodable { let id: String; let displayName: String?; let onboardingCompleted: Bool?; let alertVolume: Double? }
    private struct TokenResult: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let user: UserDTO?
    }
    private struct BaseResponse<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let result: T?
    }
    private struct EmptyResult: Decodable {}

    /// 소셜 로그인 → 서버 JWT 발급 + 저장. provider: "apple"|"google"|"kakao".
    /// deviceId 동봉으로 기존 익명 데이터를 계정에 연결, name은 Apple 최초 로그인 표시명(선택).
    @discardableResult
    func login(provider: String, idToken: String, deviceId: String?, name: String?) async throws -> LoginResult {
        let body = LoginRequest(provider: provider, idToken: idToken, deviceId: deviceId, name: name)
        let token = try await post("/auth/login", body: body, as: TokenResult.self)
        guard let user = token.user, !user.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteStoreError.malformed("missing login user id")
        }
        tokenStore.save(access: token.accessToken, refresh: token.refreshToken)
        return LoginResult(userId: user.id, displayName: user.displayName, onboardingCompleted: user.onboardingCompleted ?? false)
    }

    /// access 만료 시 refresh로 재발급. 동시 401이 여러 개 와도 single-flight로 묶어
    /// 한 번만 회전하고 나머지는 그 결과를 함께 기다린다(회전된 토큰이 서로를 무효화하는 레이스 차단).
    /// 성공하면 새 토큰 저장 후 true. refresh가 명확히 거부(만료/폐기)되면 토큰 비우고 false.
    func refresh() async -> Bool {
        await refreshCoordinator.run { [weak self] in
            await self?.performRefresh() ?? false
        }
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken = tokenStore.refreshToken else { return false }
        do {
            let token = try await post("/auth/refresh", body: RefreshRequest(refreshToken: refreshToken), as: TokenResult.self)
            tokenStore.save(access: token.accessToken, refresh: token.refreshToken)
            return true
        } catch RemoteStoreError.offline {
            // 일시적 네트워크 실패는 세션을 비우지 않는다 — 다음 요청에서 다시 시도할 수 있다.
            return false
        } catch {
            // refresh가 거부됨(만료/폐기 등) → 세션 종료.
            tokenStore.clear()
            return false
        }
    }

    /// `/auth/me` 조회 — 현재 로그인 계정의 displayName + onboardingCompleted + alertVolume 반환.
    /// 콜드 스타트에서 onboardingCompleted 정본을 가져올 때 사용한다.
    /// 실패(오프라인·401 등)는 throw로 전파 — 호출처가 silent fallback 처리.
    func me() async throws -> (userId: String, displayName: String?, onboardingCompleted: Bool, alertVolume: Double?) {
        var base = config.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        var req = URLRequest(url: URL(string: base + "/auth/me")!)
        req.httpMethod = "GET"
        if let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw RemoteStoreError.offline
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.malformed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let env = try? decoder.decode(BaseResponse<EmptyResult>.self, from: data) {
                throw RemoteStoreError.server(status: http.statusCode, code: env.code, message: env.message)
            }
            throw RemoteStoreError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let user = try? decoder.decode(BaseResponse<UserDTO>.self, from: data).result else {
            throw RemoteStoreError.malformed("empty result")
        }
        return (userId: user.id, displayName: user.displayName, onboardingCompleted: user.onboardingCompleted ?? false, alertVolume: user.alertVolume)
    }

    /// 서버 refresh 폐기 + 로컬 토큰 제거. 네트워크 실패해도 로컬은 비운다.
    func logout() async {
        if let refreshToken = tokenStore.refreshToken {
            _ = try? await post("/auth/logout", body: LogoutRequest(refreshToken: refreshToken), as: EmptyResult.self)
        }
        tokenStore.clear()
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        var base = config.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw RemoteStoreError.offline
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.malformed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let env = try? decoder.decode(BaseResponse<EmptyResult>.self, from: data) {
                throw RemoteStoreError.server(status: http.statusCode, code: env.code, message: env.message)
            }
            throw RemoteStoreError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == EmptyResult.self {
            return EmptyResult() as! T // logout 등 result 없는 성공
        }
        // try?가 Optional을 flatten하므로 result는 T. decode 실패/result 누락이면 nil → malformed.
        guard let result = try? decoder.decode(BaseResponse<T>.self, from: data).result else {
            throw RemoteStoreError.malformed("empty result")
        }
        return result
    }
}

/// refresh를 single-flight로 직렬화한다. 진행 중인 refresh가 있으면 새로 시작하지 않고
/// 그 결과를 함께 기다린다 — 동시 401들이 같은 옛 refresh 토큰으로 중복 회전해
/// 서로를 무효화(→ 강제 로그아웃)하는 레이스를 막는다.
private actor RefreshCoordinator {
    private var inFlight: Task<Bool, Never>?

    func run(_ operation: @escaping () async -> Bool) async -> Bool {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await operation() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
