import SwiftUI

/// 온보딩 튜토리얼 카드 한 장의 데이터. 비주얼은 `OnboardingTutorialView`가 id로 라우팅해
/// 실제 앱 컴포넌트(파형·다람이 등) 애니메이션으로 그린다.
struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let message: String

    /// 사용법 4단계. 표시 순서대로. 본문은 문장 단위로 줄바꿈한다(문장 중간 강제 줄바꿈 금지).
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "AirPods를 연결해요",
            message: "씹을 때 생기는 턱 움직임을 AirPods가 읽어요."
        ),
        OnboardingStep(
            id: 1,
            title: "식사 전에 측정을 시작해보세요",
            message: "시작을 누르고 평소처럼 드세요.\n종료를 누르면 기록이 저장돼요."
        ),
        OnboardingStep(
            id: 2,
            title: "꼭꼭 씹어서 도토리를 모아보세요",
            message: "오래 씹을수록 다람쥐가 자라요."
        ),
        OnboardingStep(
            id: 3,
            title: "매일 기록을 이어가요",
            message: "출석한 날이 쌓이고, 오래 모을수록 보너스를 받아요."
        ),
    ]
}
