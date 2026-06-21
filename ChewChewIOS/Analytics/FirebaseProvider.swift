import Foundation
import FirebaseCore
import FirebaseAnalytics

/// Firebase Analytics(GA4) 어댑터.
///
/// 구성 파일 `GoogleService-Info.plist`은 키를 포함해 .gitignore된다(기여자·CI 빌드엔 없을 수 있음).
/// 따라서 plist가 번들에 있을 때만 Firebase를 초기화하고 provider를 반환한다(부재 시 안전 비활성).
final class FirebaseProvider: AnalyticsService {
    /// 번들에 GoogleService-Info.plist이 있으면 Firebase를 구성하고 provider를, 없으면 nil을 반환한다.
    /// FirebaseApp.configure()는 1회만 호출한다(중복 호출은 런타임 경고).
    static func makeIfAvailable() -> FirebaseProvider? {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
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
