import Foundation

/// 여러 분석 provider로 동시 fan-out하는 어댑터.
///
/// 이벤트를 한 번 `track`하면 등록된 모든 provider로 전송된다. Amplitude·Firebase 이중 전송을
/// 이벤트 계측 중복 없이 처리하는 핵심 — 새 도구는 provider 하나 추가로 끝난다(호출부 무변경).
final class CompositeAnalytics: AnalyticsService {
    private let providers: [AnalyticsService]
    /// 모든 이벤트에 자동 첨부되는 공통 속성(예: environment=dev|prod).
    /// dev/prod 데이터가 한 분석 프로젝트에 섞여 숫자가 오염되는 것을 막는다 —
    /// 이벤트 정의(호출부) 무변경으로 fan-out 지점에서 한 번에 주입한다.
    private let baseProperties: [String: Any]

    init(_ providers: [AnalyticsService], baseProperties: [String: Any] = [:]) {
        self.providers = providers
        self.baseProperties = baseProperties
    }

    func track(_ event: AnalyticsEvent) {
        // 공통 속성 + 이벤트 고유 속성 병합(충돌 시 이벤트 속성 우선). 모든 provider에 동일 이벤트 전달.
        let outgoing = baseProperties.isEmpty
            ? event
            : AnalyticsEvent(event.name, baseProperties.merging(event.properties) { _, eventValue in eventValue })
        providers.forEach { $0.track(outgoing) }
    }

    func setUserId(_ userId: String?) {
        providers.forEach { $0.setUserId(userId) }
    }

    func setUserProperty(_ key: String, _ value: Any) {
        providers.forEach { $0.setUserProperty(key, value) }
    }
}
