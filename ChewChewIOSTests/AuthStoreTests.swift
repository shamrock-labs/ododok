import XCTest
@testable import ChewChewIOS

@MainActor
final class AuthStoreTests: XCTestCase {
    func testSignInOAuthSuccessAndServerSuccessLogsIn() async {
        let repository = FakeAuthRepository(result: LoginResult(userId: "u1", displayName: "보형", onboardingCompleted: true))
        let provider = FakeSocialLoginProvider(result: .success(.init(provider: "kakao", idToken: "id-token", name: "보형")))
        var completed: (LoginResult, String)?
        let store = AuthStore(repository: repository) { result, method in
            completed = (result, method)
        }

        await store.signIn(with: provider)

        XCTAssertTrue(store.isLoggedIn)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(repository.loginRequests.count, 1)
        XCTAssertEqual(completed?.1, "kakao")
    }

    func testSignInOAuthCancelledDoesNotShowErrorOrLogin() async {
        let repository = FakeAuthRepository()
        let provider = FakeSocialLoginProvider(result: .failure(SocialLoginError.cancelled))
        let store = AuthStore(repository: repository)

        await store.signIn(with: provider)

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(repository.loginRequests.isEmpty)
    }

    func testSignInOAuthFailureShowsError() async {
        let repository = FakeAuthRepository()
        let provider = FakeSocialLoginProvider(result: .failure(SocialLoginError.failed("OAuth 실패")))
        let store = AuthStore(repository: repository)

        await store.signIn(with: provider)

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertEqual(store.errorMessage, "OAuth 실패")
        XCTAssertTrue(repository.loginRequests.isEmpty)
    }

    func testSignInServerFailureKeepsLoggedOutAndDoesNotSaveToken() async {
        let repository = FakeAuthRepository(error: TestAuthError.server)
        let provider = FakeSocialLoginProvider(result: .success(.init(provider: "google", idToken: "id-token", name: nil)))
        let store = AuthStore(repository: repository)

        await store.signIn(with: provider)

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(repository.didSaveToken)
    }

    func testExpireSessionClearsLocalSessionAndCallsHandler() {
        var expired = false
        let store = AuthStore(
            repository: FakeAuthRepository(),
            isLoggedIn: true,
            didLoadProfile: true,
            hasCompletedOnboarding: true,
            onSessionExpired: { expired = true }
        )

        store.expireSession()

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertFalse(store.didLoadProfile)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertTrue(expired)
    }

    func testLogoutClearsSession() async {
        let repository = FakeAuthRepository()
        var loggedOut = false
        let store = AuthStore(
            repository: repository,
            isLoggedIn: true,
            didLoadProfile: true,
            hasCompletedOnboarding: true,
            onLogoutCompleted: { loggedOut = true }
        )

        await store.logout()

        XCTAssertTrue(repository.didLogout)
        XCTAssertFalse(store.isLoggedIn)
        XCTAssertFalse(store.didLoadProfile)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertTrue(loggedOut)
    }

    func testOnboardingCompletionReflectsLoginResult() async {
        let repository = FakeAuthRepository(result: LoginResult(userId: "u1", displayName: nil, onboardingCompleted: false))
        let provider = FakeSocialLoginProvider(result: .success(.init(provider: "apple", idToken: "id-token", name: nil)))
        let store = AuthStore(repository: repository, hasCompletedOnboarding: true)

        await store.signIn(with: provider)

        XCTAssertTrue(store.isLoggedIn)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }
}

private enum TestAuthError: LocalizedError {
    case server

    var errorDescription: String? {
        "서버 로그인 실패"
    }
}

@MainActor
private final class FakeSocialLoginProvider: SocialLoginProvider {
    private let result: Result<SocialCredential, Error>

    init(result: Result<SocialCredential, Error>) {
        self.result = result
    }

    func login() async throws -> SocialCredential {
        try result.get()
    }
}

private final class FakeAuthRepository: AuthRepository {
    struct LoginRequest: Equatable {
        let provider: String
        let idToken: String
        let name: String?
    }

    private let result: LoginResult
    private let error: Error?
    private(set) var loginRequests: [LoginRequest] = []
    private(set) var didLogout = false
    private(set) var didSaveToken = false

    init(
        result: LoginResult = LoginResult(userId: "u1", displayName: nil, onboardingCompleted: false),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func login(provider: String, idToken: String, name: String?) async throws -> LoginResult {
        loginRequests.append(LoginRequest(provider: provider, idToken: idToken, name: name))
        if let error { throw error }
        didSaveToken = true
        return result
    }

    func logout() async {
        didLogout = true
    }
}
