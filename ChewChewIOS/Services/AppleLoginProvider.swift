import AuthenticationServices
import UIKit

/// Sign in with Apple(네이티브). SDK 없이 AuthenticationServices로 id_token + 이름(최초 1회)을 받는다.
@MainActor
final class AppleLoginProvider: NSObject, SocialLoginProvider {
    private var continuation: CheckedContinuation<SocialCredential, Error>?

    func login() async throws -> SocialCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
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
        // Apple은 최초 인증에만 이름을 준다. 한국어 순서(성+이름)로 합친다.
        let parts = [credential.fullName?.familyName, credential.fullName?.givenName].compactMap { $0 }
        let name = parts.joined()
        finish(.success(SocialCredential(provider: "apple", idToken: idToken, name: name.isEmpty ? nil : name)))
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
