import Foundation

/// 소셜 로그인 1회 결과 — 서버 `/auth/login`에 보낼 재료. (ODO-47)
struct SocialCredential {
    let provider: String   // "apple" | "google" | "kakao"
    let idToken: String    // 프로바이더 OIDC id_token
    let name: String?      // Apple 최초 로그인 표시명(있을 때만). 서버는 없으면 닉네임 생성.
}

enum SocialLoginError: LocalizedError {
    case cancelled
    case missingIdToken
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "로그인이 취소되었어요."
        case .missingIdToken: return "로그인 토큰을 받지 못했어요."
        case .failed(let message): return message
        }
    }
}

/// Apple/Google/Kakao 공통 진입점. 각 구현이 provider UI를 띄우고 id_token을 받아온다.
@MainActor
protocol SocialLoginProvider {
    var method: String { get }
    func login() async throws -> SocialCredential
}
