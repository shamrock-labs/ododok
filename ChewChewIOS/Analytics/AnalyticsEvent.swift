import Foundation

/// 제품·리텐션 분석 이벤트 정의.
///
/// `track(_:)` 한 번 호출이 등록된 모든 provider(Amplitude·후속 Firebase)로 동시에 나간다.
/// 이름·속성 스키마를 이 한 곳에서 관리해 provider 간 드리프트·오타를 막는다(타입 안전 팩토리).
struct AnalyticsEvent {
    let name: String
    let properties: [String: Any]

    init(_ name: String, _ properties: [String: Any] = [:]) {
        self.name = name
        self.properties = properties
    }
}

// MARK: - 표준 이벤트 팩토리 (v1 트래킹 플랜)

extension AnalyticsEvent {
    /// 온보딩(이름 입력 + 튜토리얼)을 끝까지 마침. 활성화 깔때기의 핵심 전환점.
    static func onboardingCompleted() -> AnalyticsEvent {
        .init("onboarding_completed")
    }

    /// 식사 측정 세션 시작.
    static func mealSessionStarted() -> AnalyticsEvent {
        .init("meal_session_started")
    }

    /// 식사 측정 세션 종료 + 서버 저장 성공. 리텐션·참여도 분석의 주 이벤트.
    static func mealSessionCompleted(
        durationSec: Int,
        sampleCount: Int,
        chewingFraction: Double?,
        estimatedTotalChews: Int?,
        reportable: Bool
    ) -> AnalyticsEvent {
        var p: [String: Any] = [
            "duration_sec": durationSec,
            "sample_count": sampleCount,
            "reportable": reportable
        ]
        if let chewingFraction { p["chewing_fraction"] = chewingFraction }
        if let estimatedTotalChews { p["estimated_total_chews"] = estimatedTotalChews }
        return .init("meal_session_completed", p)
    }

    /// 도토리(포인트) 적립. 세션 종료 적립·출석 보너스 등 실제 포인트가 지급된 경우만.
    static func rewardEarned(amount: Int, kind: String) -> AnalyticsEvent {
        .init("reward_earned", ["amount": amount, "kind": kind])
    }

    /// 스트릭 상태 이벤트(마일스톤·방어·리셋·첫날). 포인트 지급과 무관한 스트릭 변화 추적.
    static func streakEvent(type: String, amount: Int) -> AnalyticsEvent {
        .init("streak_event", ["type": type, "amount": amount])
    }

    /// 친구 초대 코드 수신(딥링크/공유). 로그인 여부로 즉시 수락 vs 보류를 구분.
    static func friendInviteReceived(loggedIn: Bool) -> AnalyticsEvent {
        .init("friend_invite_received", ["logged_in": loggedIn])
    }

    /// 소셜 로그인 성공. method(apple/google/kakao) 분포·전환을 본다.
    /// 서버에 신규가입 플래그가 없어 signup은 별도 계측하지 않는다 — 가입 전환은 onboarding_completed로.
    static func login(method: String, onboardingCompleted: Bool) -> AnalyticsEvent {
        .init("login", ["method": method, "onboarding_completed": onboardingCompleted])
    }

    /// 측정 세션이 서버 저장 없이 종료됨. reason: user_discard(사용자 그만두기) | no_samples(IMU 0개).
    /// 저장 성공한 세션은 meal_session_completed, 저장 실패는 meal_session_failed로 별도 구분.
    static func mealSessionAborted(reason: String, durationSec: Int) -> AnalyticsEvent {
        .init("meal_session_aborted", ["reason": reason, "duration_sec": durationSec])
    }

    /// 측정은 끝났으나 서버 저장 실패. reason은 오류 분류(offline/server/http/malformed/...).
    /// 저장 실패 세션이 통계에서 증발하지 않도록(생존편향 방지) 기록한다.
    static func mealSessionFailed(reason: String) -> AnalyticsEvent {
        .init("meal_session_failed", ["reason": reason])
    }

    /// 권한 요청 결과. type=motion(AirPods 모션). granted로 거부율·활성화 이탈을 본다.
    static func permissionResult(type: String, granted: Bool) -> AnalyticsEvent {
        .init("permission_result", ["type": type, "granted": granted])
    }

    /// 상점 꾸미기 아이템 구매(포인트 소비). 적립(reward_earned)과 짝을 이뤄 포인트 경제를 본다.
    static func shopItemPurchased(itemId: String, itemType: String, price: Int) -> AnalyticsEvent {
        .init("shop_item_purchased", ["item_id": itemId, "item_type": itemType, "price": price])
    }

    /// 도토리팩 구매(포인트 소비).
    static func acornPackPurchased(packId: String, price: Int) -> AnalyticsEvent {
        .init("acorn_pack_purchased", ["pack_id": packId, "price": price])
    }
}
