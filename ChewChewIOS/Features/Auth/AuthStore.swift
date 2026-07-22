import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var isLoggedIn: Bool
    private(set) var hasCompletedOnboarding: Bool

    private let repository: AuthRepository
    private let analytics: AnalyticsService
    private let onLoginCompleted: (LoginResult, String) -> Void
    private let onLogoutCompleted: () -> Void
    private let onSessionExpired: () -> Void

    init(
        repository: AuthRepository,
        isLoggedIn: Bool = false,
        hasCompletedOnboarding: Bool = false,
        analytics: AnalyticsService = NoopAnalytics(),
        onLoginCompleted: @escaping (LoginResult, String) -> Void = { _, _ in },
        onLogoutCompleted: @escaping () -> Void = {},
        onSessionExpired: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.analytics = analytics
        self.isLoggedIn = isLoggedIn
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onLoginCompleted = onLoginCompleted
        self.onLogoutCompleted = onLogoutCompleted
        self.onSessionExpired = onSessionExpired
    }

    func signIn(with provider: SocialLoginProvider) async {
        guard !isLoading else { return }
        let method = provider.method
        isLoading = true
        errorMessage = nil
        analytics.track(.loginStarted(method: method))
        defer { isLoading = false }

        do {
            let credential = try await provider.login()
            let result = try await repository.login(
                provider: credential.provider,
                idToken: credential.idToken,
                name: credential.name
            )
            isLoggedIn = true
            hasCompletedOnboarding = result.onboardingCompleted
            onLoginCompleted(result, credential.provider)
        } catch SocialLoginError.cancelled {
            // 사용자가 취소 — 에러 메시지 표시하지 않는다.
            analytics.track(.loginCancelled(method: method))
        } catch {
            analytics.track(.loginFailed(method: method, reason: Self.loginFailureReason(error)))
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    func logout() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await repository.logout()
        clearSessionState()
        onLogoutCompleted()
    }

    func expireSession() {
        clearSessionState()
        onSessionExpired()
    }

    func markLoggedIn(onboardingCompleted: Bool) {
        isLoggedIn = true
        hasCompletedOnboarding = onboardingCompleted
        errorMessage = nil
    }

    func markLoggedOut() {
        clearSessionState()
    }

    func updateOnboardingCompleted(_ completed: Bool) {
        hasCompletedOnboarding = completed
    }

    private func clearSessionState() {
        isLoggedIn = false
        hasCompletedOnboarding = false
        errorMessage = nil
    }

    private static func loginFailureReason(_ error: Error) -> LoginFailureReason {
        if let socialError = error as? SocialLoginError {
            switch socialError {
            case .cancelled:
                return .unknown
            case .missingIdToken:
                return .missingIdToken
            case .failed:
                return .provider
            }
        }
        guard let remoteError = error as? RemoteStoreError else { return .unknown }
        switch remoteError {
        case .offline:
            return .offline
        case .malformed, .invalidUploadResponse:
            return .malformedResponse
        case .authExpired, .server, .http:
            return .server
        }
    }
}
