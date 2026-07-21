import Foundation
import AmplitudeSwift

/// Amplitude(US 리전) 어댑터. API Key와 인스턴스명은 빌드 구성별로 Info.plist를 통해 주입한다.
final class AmplitudeProvider: AnalyticsService {
    private let amplitude: Amplitude

    init(apiKey: String, instanceName: String) {
        // Dev/Prod 프로젝트는 모두 US 데이터 리전에 있다. 인스턴스명도 분리해
        // 프로젝트 전환 시 기기에 남은 이벤트 큐와 device_id가 섞이지 않게 한다.
        amplitude = Amplitude(configuration: Configuration(
            apiKey: apiKey,
            instanceName: instanceName,
            serverZone: .US,
            // 앱 설치/업데이트/열기(생명주기)를 자동 수집. screenViews는 SwiftUI에서 불안정해 끈다
            // (화면별 수동 screen_view는 후속 패스).
            autocapture: [.sessions, .appLifecycles]
        ))
    }

    func track(_ event: AnalyticsEvent) {
        amplitude.track(eventType: event.name, eventProperties: event.properties)
    }

    func setUserId(_ userId: String?) {
        amplitude.setUserId(userId: userId)
    }

    func setUserProperty(_ key: String, _ value: Any) {
        amplitude.identify(identify: Identify().set(property: key, value: value))
    }
}
