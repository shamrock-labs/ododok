import AuthenticationServices
import UIKit

/// Sign in with Apple(네이티브). SDK 없이 AuthenticationServices로 id_token을 받는다.
/// 실명(fullName)은 요청하지 않는다 — 개인정보 최소화(App Review 5.1.1). 표시명은 온보딩 닉네임으로 받는다.
@MainActor
final class AppleLoginProvider: NSObject, SocialLoginProvider {
    private var continuation: CheckedContinuation<SocialCredential, Error>?

    func login() async throws -> SocialCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleLoginProvider: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(SocialLoginError.missingIdToken))
            return
        }
        // 실명은 수집하지 않는다(5.1.1). 표시명은 서버가 닉네임을 생성하거나 온보딩에서 입력받는다.
        finish(.success(SocialCredential(provider: "apple", idToken: idToken, name: nil)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(.failure(SocialLoginError.cancelled))
        } else {
            finish(.failure(SocialLoginError.failed(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<SocialCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

extension AppleLoginProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
