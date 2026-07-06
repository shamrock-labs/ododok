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
    private let onLoginCompleted: (LoginResult, String) -> Void
    private let onLogoutCompleted: () -> Void
    private let onSessionExpired: () -> Void

    init(
        repository: AuthRepository,
        isLoggedIn: Bool = false,
        hasCompletedOnboarding: Bool = false,
        onLoginCompleted: @escaping (LoginResult, String) -> Void = { _, _ in },
        onLogoutCompleted: @escaping () -> Void = {},
        onSessionExpired: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.isLoggedIn = isLoggedIn
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onLoginCompleted = onLoginCompleted
        self.onLogoutCompleted = onLogoutCompleted
        self.onSessionExpired = onSessionExpired
    }

    func signIn(with provider: SocialLoginProvider) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
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
        } catch {
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
}
