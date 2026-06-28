import SwiftUI

/// 온보딩 튜토리얼 카드 한 장의 데이터. SF Symbol 또는 다람이 일러스트 중 하나를 표시.
/// asset가 채워져 있으면 다람이 일러스트가 우선되고, 아니면 SF Symbol(`icon`)이 표시된다.
struct OnboardingStep: Identifiable {
    let id: Int
    let icon: String
    let asset: String?
    let title: String
    let message: String

    /// 사용법 5단계. 표시 순서대로.
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            icon: "airpodspro",
            asset: nil,
            title: "AirPods를 연결해 주세요",
            message: "AirPods Pro · 3·4세대 · Max 안의 IMU 센서가\n턱 움직임을 읽어요. 다른 이어폰은 측정되지 않아요."
        ),
        OnboardingStep(
            id: 1,
            icon: "fork.knife",
            asset: "DaramEating",
            title: "식사 시작 버튼을 누르세요",
            message: "홈에서 '식사 시작'을 누르고 평소처럼 드세요.\n다 먹으면 '식사 종료' — 그동안의 씹기가 기록돼요."
        ),
        OnboardingStep(
            id: 2,
            icon: "mouth.fill",
            asset: "DaramPuffy",
            title: "꼭꼭 씹을수록 다람쥐가 자라요",
            message: "천천히 오래 씹으면 볼이 빵빵해지고\n도토리가 쌓여요. 하루 목표는 400회예요."
        ),
        OnboardingStep(
            id: 3,
            icon: "bag.fill",
            asset: "DaramDotori",
            title: "도토리로 다람쥐를 꾸며요",
            message: "모은 도토리로 상점에서 모자·안경·액세서리를\n사서 다람쥐에게 씌워요."
        ),
        OnboardingStep(
            id: 4,
            icon: "flame.fill",
            asset: "DaramHeart",
            title: "매일 들러 연속 출석을 쌓아요",
            message: "7·30·100일엔 프리즈🛡️ 보너스가 있어요.\n끼니 알림을 켜두면 잊지 않고 챙길 수 있어요."
        ),
    ]
}
