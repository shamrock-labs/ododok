@testable import ChewChewIOS

final class InMemoryAuthTokenStore: AuthTokenStorage {
    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    var isLoggedIn: Bool { accessToken != nil }

    init(accessToken: String? = nil, refreshToken: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func save(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
    }
}
