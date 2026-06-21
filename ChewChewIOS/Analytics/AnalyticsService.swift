import Foundation

/// 분석 전송 포트. 구현(Amplitude·Firebase·Composite·Noop)을 주입으로 갈아끼운다(포트&어댑터).
///
/// 화면·상태(AppState)는 이 프로토콜에만 의존하고, 어떤 분석 도구로 보내는지는 모른다.
/// 메트릭을 Amplitude·Firebase 두 곳으로 보내도 호출부는 `track(_:)` 한 번뿐 — fan-out은 CompositeAnalytics가 담당.
protocol AnalyticsService: AnyObject {
    func track(_ event: AnalyticsEvent)
    func setUserId(_ userId: String?)
    func setUserProperty(_ key: String, _ value: Any)
}

/// 무동작 구현 — 테스트 런, 또는 API Key 미설정(기여자 빌드) 시 주입한다.
final class NoopAnalytics: AnalyticsService {
    func track(_ event: AnalyticsEvent) {}
    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}
