import Foundation
import AmplitudeSwift

/// Amplitude(EU 리전) 어댑터. API Key는 `Secrets.xcconfig` → Info.plist(`AmplitudeAPIKey`) 경유로 주입한다.
final class AmplitudeProvider: AnalyticsService {
    private let amplitude: Amplitude

    init(apiKey: String) {
        // 프로젝트가 EU 데이터 리전이므로 serverZone=.EU 필수.
        // US 기본으로 두면 이벤트가 EU 프로젝트에 도달하지 못하고 사라진다.
        amplitude = Amplitude(configuration: Configuration(
            apiKey: apiKey,
            serverZone: .EU
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
