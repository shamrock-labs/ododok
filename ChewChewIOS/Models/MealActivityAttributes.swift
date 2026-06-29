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
        /// 통화가 아직 진행 중인지. `isPausedByCall == true`일 때만 의미 있다.
        /// true=통화 중(버튼 없이 "멈춤"만 표시), false=통화 종료(계속하기·그만하기 노출).
        var callActive: Bool = false
    }

    var startedAt: Date
}
#endif
