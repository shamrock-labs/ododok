import Foundation

protocol AuthTokenStorage {
    var accessToken: String? { get }
    var refreshToken: String? { get }
    var isLoggedIn: Bool { get }

    func clear()
}

struct KeychainAuthTokenStorage: AuthTokenStorage {
    var accessToken: String? {
        TokenManager.accessToken
    }

    var refreshToken: String? {
        TokenManager.refreshToken
    }

    var isLoggedIn: Bool {
        TokenManager.isLoggedIn
    }

    func clear() {
        TokenManager.clear()
    }
}
