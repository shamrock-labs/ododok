#if os(iOS)
import ActivityKit
#endif
import Foundation

/// 식사 세션 동안 "식사 측정 중" Live Activity(잠금화면·다이내믹 아일랜드)를 띄우고 갱신한다.
/// 전화로 멈추면 `setPaused(true)`로 라이브 현황을 "통화로 멈춤 + 이어서 측정"으로 바꿔,
/// 통화 길이와 무관하게 끊은 뒤 그 자리에서 재개 버튼을 누를 수 있게 한다.
///
/// 사용자가 설정에서 Live Activity를 꺼두면(`areActivitiesEnabled == false`) 전체 노옵 —
/// 이 경우 중단/재개는 `MealNotificationService`의 표준 알림이 담당한다.
final class MealActivityController {

    #if os(iOS)
    private var activity: Activity<MealActivityAttributes>?
    #endif

    func start(startedAt: Date) {
        #if os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }
        let content = ActivityContent(
            state: MealActivityAttributes.ContentState(isPausedByCall: false, callActive: false),
            staleDate: nil
        )
        activity = try? Activity.request(
            attributes: MealActivityAttributes(startedAt: startedAt),
            content: content,
            pushType: nil
        )
        #endif
    }

    /// 전화로 멈춤(true) / 재개(false) 상태를 라이브 현황에 반영.
    /// 통화 감지 시 앱이 곧 suspend될 수 있어, 업데이트를 fire-and-forget Task로 던지면
    /// 반영 전에 멈춰 카드가 안 바뀐다. async로 만들어 호출부(onCallStarted)에서 await해 확실히 보낸다.
    func setPaused(_ paused: Bool, callActive: Bool = false) async {
        #if os(iOS)
        guard let activity else { return }
        let content = ActivityContent(
            state: MealActivityAttributes.ContentState(isPausedByCall: paused, callActive: callActive),
            staleDate: nil
        )
        await activity.update(content)
        #endif
    }

    func end() {
        #if os(iOS)
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }
}
