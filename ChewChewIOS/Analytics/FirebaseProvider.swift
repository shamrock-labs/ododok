import Foundation
import FirebaseCore
import FirebaseAnalytics

/// Firebase Analytics(GA4) 어댑터.
///
/// 구성 파일 `GoogleService-Info.plist`은 키를 포함해 .gitignore된다(기여자·CI 빌드엔 없을 수 있음).
/// 따라서 plist가 번들에 있고, 그 plist의 번들 ID가 실제 앱 번들 ID와 일치할 때만
/// Firebase를 초기화하고 provider를 반환한다(부재·불일치 시 안전 비활성).
final class FirebaseProvider: AnalyticsService {
    /// 번들에 GoogleService-Info.plist이 있고 그 BUNDLE_ID가 실제 앱과 일치하면
    /// Firebase를 구성하고 provider를, 아니면 nil을 반환한다.
    /// FirebaseApp.configure()는 1회만 호출한다(중복 호출은 런타임 경고).
    static func makeIfAvailable() -> FirebaseProvider? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return nil
        }
        // plist의 BUNDLE_ID가 실제 앱 번들 ID와 일치할 때만 활성화한다(fail-safe).
        // 콘솔에 잘못 등록된 앱(예: 이전 개인 계정 번들 ID)으로 이벤트가 흘러가
        // 엉뚱한 GA4 스트림을 채우는 오설정을 막는다 — isUsableSecret·Sentry 가드와 같은 철학.
        // plist를 못 읽거나 BUNDLE_ID가 없으면(손상·키 부재) 일치 검증이 불가하므로 비활성한다.
        // 올바른 앱 번들 ID로 발급한 plist로 교체하면 자동으로 다시 활성화된다.
        let plistBundleID = NSDictionary(contentsOfFile: path)?["BUNDLE_ID"] as? String
        guard plistBundleID == Bundle.main.bundleIdentifier else {
            #if DEBUG
            print("[Firebase] GoogleService-Info.plist BUNDLE_ID(\(plistBundleID ?? "nil")) ≠ 앱 번들 ID(\(Bundle.main.bundleIdentifier ?? "nil")) — Analytics 비활성. 콘솔에서 앱 번들 ID로 등록한 plist로 교체하세요.")
            #endif
            return nil
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return FirebaseProvider()
    }

    func track(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.properties)
    }

    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
    }

    func setUserProperty(_ key: String, _ value: Any) {
        Analytics.setUserProperty(String(describing: value), forName: key)
    }
}
