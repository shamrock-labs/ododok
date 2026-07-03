import AuthenticationServices
import UIKit

/// Sign in with Apple(네이티브). SDK 없이 AuthenticationServices로 id_token을 받는다.
/// 표시명은 온보딩 닉네임으로 받는다.
@MainActor
final class AppleLoginProvider: NSObject, SocialLoginProvider {
    private var continuation: CheckedContinuation<SocialCredential, Error>?

    func login() async throws -> SocialCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
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
