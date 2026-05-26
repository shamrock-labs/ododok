import Foundation
import Security

/// 익명 디바이스 식별자. 앱 첫 실행 시 UUID를 생성해 Keychain에 영구 저장한다.
/// 앱 삭제·재설치로 사라질 수 있는 UserDefaults와 달리 Keychain은 (시스템 정책상)
/// 재설치 후에도 살아남는 경우가 있어 익명 식별자 안정성이 더 높다.
///
/// 그러나 iOS 시뮬레이터의 Keychain은 디바이스 Keychain보다 휘발성이 커서
/// Xcode 빌드 교체 같은 일상 작업에서도 item이 사라지는 케이스가 있다(Apple이
/// 명문화하지 않은 환경 동작). 그 경우 매 launch마다 새 UUID가 발급되어
/// "유저 자체가 새로 생긴" 듯한 회귀로 이어진다.
///
/// 대응: Keychain + UserDefaults에 동시에 저장하고, Keychain read가 실패해도
/// UserDefaults의 백업값에서 같은 UUID를 복구한다. 실기기에서 사용자가 앱을
/// manual 삭제하면 둘 다 사라지므로 그땐 어쩔 수 없이 새 UUID — 그건 iOS의
/// 의도된 동작.
///
/// InsForge `profiles` / `user_stats` / `chewing_session`의 `device_id` 컬럼과 1:1 매칭.
enum DeviceIdentity {
    private static let service = "com.sungho.chewchewios"
    private static let account = "deviceId"
    private static let userDefaultsKey = "ChewChewIOS.DeviceIdentity.deviceId"

    /// 동기 API. 앱 lifecycle 어디에서 호출해도 항상 같은 UUID 문자열을 돌려준다.
    /// 우선순위: Keychain > UserDefaults 백업 > 새 UUID 발급.
    static let shared: String = {
        // 1) Keychain에 살아있는 값이 있으면 그걸 사용. UserDefaults도 함께 갱신(write-through).
        if let existing = readFromKeychain() {
            writeUserDefaults(existing)
            return existing
        }
        // 2) Keychain이 휘발했지만 UserDefaults 백업이 있으면 그걸로 복구 + Keychain 재기록.
        if let backup = readUserDefaults() {
            writeToKeychain(backup)
            return backup
        }
        // 3) 둘 다 없으면 진짜 신규 디바이스 — 새 UUID 발급 + 둘 다에 저장.
        let new = UUID().uuidString
        writeToKeychain(new)
        writeUserDefaults(new)
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

    private static func readUserDefaults() -> String? {
        UserDefaults.standard.string(forKey: userDefaultsKey)
    }

    private static func writeUserDefaults(_ value: String) {
        UserDefaults.standard.set(value, forKey: userDefaultsKey)
    }
}
