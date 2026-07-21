import KakaoSDKAuth
import KakaoSDKCommon
import KakaoSDKUser

/// Kakao 로그인. 카카오톡 설치 시 앱 로그인, 아니면 계정(웹) 로그인.
/// id_token은 Kakao 앱에 OIDC가 켜져 있어야 내려온다(콘솔에서 OpenID Connect 활성화 필요).
@MainActor
final class KakaoLoginProvider: SocialLoginProvider {
    let method = "kakao"

    func login() async throws -> SocialCredential {
        let oauthToken: OAuthToken = try await withCheckedThrowingContinuation { continuation in
            let handler: (OAuthToken?, Error?) -> Void = { token, error in
                if let error {
                    if let sdkError = error as? SdkError,
                       sdkError.getClientError().reason == .Cancelled {
                        continuation.resume(throwing: SocialLoginError.cancelled)
                        return
                    }
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: SocialLoginError.missingIdToken)
                }
            }
            if UserApi.isKakaoTalkLoginAvailable() {
                UserApi.shared.loginWithKakaoTalk(completion: handler)
            } else {
                UserApi.shared.loginWithKakaoAccount(completion: handler)
            }
        }
        guard let idToken = oauthToken.idToken else {
            // OIDC 미활성 → idToken 없음. Kakao 콘솔에서 OpenID Connect를 켜야 한다.
            throw SocialLoginError.missingIdToken
        }
        return SocialCredential(provider: method, idToken: idToken, name: nil)
    }
}
