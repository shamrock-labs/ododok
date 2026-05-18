import Foundation
import Security

/// 익명 디바이스 식별자. 앱 첫 실행 시 UUID를 생성해 Keychain에 영구 저장한다.
/// 앱 삭제·재설치로 사라질 수 있는 UserDefaults와 달리 Keychain은 (시스템 정책상)
/// 재설치 후에도 살아남는 경우가 있어 익명 식별자 안정성이 더 높다.
///
/// InsForge `user_progress` / `chewing_session`의 `device_id` 컬럼과 1:1 매칭.
enum DeviceIdentity {
    private static let service = "com.sungho.chewchewios"
    private static let account = "deviceId"

    /// 동기 API. 앱 lifecycle 어디에서 호출해도 항상 같은 UUID 문자열을 돌려준다.
    static let shared: String = {
        if let existing = readFromKeychain() {
            return existing
        }
        let new = UUID().uuidString
        writeToKeychain(new)
        return new
    }()

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    @discardableResult
    private static func writeToKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let attributes: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String:        data
        ]
        // 이미 존재하면 update, 없으면 add — 어느 쪽이든 errSecSuccess 일치
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String:        kSecClassGenericPassword,
                kSecAttrService as String:  service,
                kSecAttrAccount as String:  account
            ]
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(updateQuery as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
