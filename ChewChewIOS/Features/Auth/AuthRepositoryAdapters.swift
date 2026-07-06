import Foundation

extension SpringAuthClient: AuthRepository {
    func login(provider: String, idToken: String, name: String?) async throws -> LoginResult {
        try await login(
            provider: provider,
            idToken: idToken,
            deviceId: DeviceIdentity.shared,
            name: name
        )
    }
}

extension NoopAuthSessionManager: AuthRepository {
    func login(provider: String, idToken: String, name: String?) async throws -> LoginResult {
        LoginResult(userId: "", displayName: name, onboardingCompleted: false)
    }
}

struct AuthSessionManagerRepositoryAdapter: AuthRepository {
    private let sessionManager: AuthSessionManaging

    init(sessionManager: AuthSessionManaging) {
        self.sessionManager = sessionManager
    }

    func login(provider: String, idToken: String, name: String?) async throws -> LoginResult {
        LoginResult(userId: "", displayName: name, onboardingCompleted: false)
    }

    func logout() async {
        await sessionManager.logout()
    }
}
