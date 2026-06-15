import Foundation

protocol AuthSessionManaging {
    func logout() async
}

struct NoopAuthSessionManager: AuthSessionManaging {
    func logout() async {
        TokenManager.clear()
    }
}

/// Spring `/auth/*` 클라이언트 — 소셜 로그인 토큰 교환 + 갱신/로그아웃. (ODO-47 OAuth)
/// 발급된 access/refresh는 TokenManager(Keychain)에 저장한다.
/// 서버 응답은 `{code, message, result}` wrapping(SpringRemoteStore와 동일).
final class SpringAuthClient: AuthSessionManaging {
    private let config: SpringConfig
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(config: SpringConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    struct LoginResult {
        let userId: String
        let displayName: String?
    }

    private struct LoginRequest: Encodable {
        let provider: String
        let idToken: String
        let deviceId: String?
        let name: String?
    }
    private struct RefreshRequest: Encodable { let refreshToken: String }
    private struct LogoutRequest: Encodable { let refreshToken: String }
    private struct UserDTO: Decodable { let id: String; let displayName: String? }
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
        TokenManager.save(access: token.accessToken, refresh: token.refreshToken)
        return LoginResult(userId: token.user?.id ?? "", displayName: token.user?.displayName)
    }

    /// access 만료 시 refresh로 재발급. 성공하면 새 토큰 저장 후 true,
    /// 실패(refresh 만료/폐기)면 토큰 비우고 false — 호출처는 재로그인 유도.
    func refresh() async -> Bool {
        guard let refreshToken = TokenManager.refreshToken else { return false }
        do {
            let token = try await post("/auth/refresh", body: RefreshRequest(refreshToken: refreshToken), as: TokenResult.self)
            TokenManager.save(access: token.accessToken, refresh: token.refreshToken)
            return true
        } catch {
            TokenManager.clear()
            return false
        }
    }

    /// 서버 refresh 폐기 + 로컬 토큰 제거. 네트워크 실패해도 로컬은 비운다.
    func logout() async {
        if let refreshToken = TokenManager.refreshToken {
            _ = try? await post("/auth/logout", body: LogoutRequest(refreshToken: refreshToken), as: EmptyResult.self)
        }
        TokenManager.clear()
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
