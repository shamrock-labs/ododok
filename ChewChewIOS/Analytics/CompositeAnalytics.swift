import Foundation

/// 여러 분석 provider로 동시 fan-out하는 어댑터.
///
/// 이벤트를 한 번 `track`하면 등록된 모든 provider로 전송된다. Amplitude·Firebase 이중 전송을
/// 이벤트 계측 중복 없이 처리하는 핵심 — 새 도구는 provider 하나 추가로 끝난다(호출부 무변경).
final class CompositeAnalytics: AnalyticsService {
    private let providers: [AnalyticsService]

    init(_ providers: [AnalyticsService]) {
        self.providers = providers
    }

    func track(_ event: AnalyticsEvent) {
        providers.forEach { $0.track(event) }
    }

    func setUserId(_ userId: String?) {
        providers.forEach { $0.setUserId(userId) }
    }

    func setUserProperty(_ key: String, _ value: Any) {
        providers.forEach { $0.setUserProperty(key, value) }
    }
}
