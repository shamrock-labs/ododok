#if os(iOS)
import ActivityKit
#endif
import Foundation

/// 식사 측정 Live Activity의 속성. 앱과 위젯 익스텐션 양 타겟이 공유한다.
/// - 정적: 세션 시작 시각(경과 시간 타이머용).
/// - 동적(ContentState): 전화로 멈췄는지 여부 — 라이브 현황을 "측정 중 ↔ 통화로 멈춤"으로 전환.
#if os(iOS)
struct MealActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPausedByCall: Bool
    }

    var startedAt: Date
}
#endif
