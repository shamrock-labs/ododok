import Foundation

struct LoginResult: Equatable {
    let userId: String
    let displayName: String?
    let onboardingCompleted: Bool
}

protocol AuthRepository {
    func login(provider: String, idToken: String, name: String?) async throws -> LoginResult
    func logout() async
}
