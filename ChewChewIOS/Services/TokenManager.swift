import Foundation
import Security

/// 서버(Spring) 발급 JWT(access/refresh)를 Keychain에 보관한다. (ODO-47 OAuth)
///
/// access는 무상태 단명 토큰이라 매 요청 Authorization 헤더에 싣고,
/// refresh는 만료된 access 재발급(`/auth/refresh`)에만 쓴다. 둘 다 Keychain에
/// 둬서 앱 재실행 후에도 로그인 세션이 유지된다(DeviceIdentity와 동일 정책).
enum TokenManager {
    private static let service = "com.sungho.ododok.auth"
    private static let accessAccount = "accessToken"
    private static let refreshAccount = "refreshToken"

    /// 로그인/리프레시 성공 시 두 토큰을 함께 저장한다.
    static func save(access: String, refresh: String) {
        write(account: accessAccount, value: access)
        write(account: refreshAccount, value: refresh)
    }

    /// access만 갱신(refresh 회전 없이 access만 재발급된 경우).
    static func updateAccess(_ access: String) {
        write(account: accessAccount, value: access)
    }

    static var accessToken: String? { read(account: accessAccount) }
    static var refreshToken: String? { read(account: refreshAccount) }

    /// 로그인 여부(로컬 판단). access 유효성/만료는 서버가 401로 알려주므로 여기선 존재만 본다.
    static var isLoggedIn: Bool { accessToken != nil }

    /// 로그아웃/탈퇴 시 토큰 제거.
    static func clear() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
    }

    // MARK: - Keychain helpers (DeviceIdentity와 동일 패턴)

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func write(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
