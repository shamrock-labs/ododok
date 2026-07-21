import GoogleSignIn
import UIKit

/// Google 로그인. client id는 Info.plist `GIDClientID`(Secrets.xcconfig)에서 SDK가 자동 사용한다.
@MainActor
final class GoogleLoginProvider: SocialLoginProvider {
    let method = "google"

    func login() async throws -> SocialCredential {
        guard let presenter = Self.topViewController() else {
            throw SocialLoginError.failed("화면을 찾지 못했어요.")
        }
        let result: GIDSignInResult
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { signInResult, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let signInResult {
                        continuation.resume(returning: signInResult)
                    } else {
                        continuation.resume(throwing: SocialLoginError.missingIdToken)
                    }
                }
            }
        } catch let error as GIDSignInError where error.code == .canceled {
            throw SocialLoginError.cancelled
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw SocialLoginError.missingIdToken
        }
        return SocialCredential(provider: method, idToken: idToken, name: result.user.profile?.name)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
