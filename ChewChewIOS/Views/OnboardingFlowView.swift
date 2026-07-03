import SwiftUI

/// 첫 실행 온보딩 sheet의 루트. 닉네임 입력 → 사용법 튜토리얼 두 단계를 한 sheet 안에서
/// 잇는다. 단계는 `state.displayName`으로 파생 — 닉네임이 없으면 입력 단계, 채워지면 튜토리얼.
/// 튜토리얼 완료/건너뛰기 시 `completeOnboarding()`이 `hasCompletedOnboarding`을 set해
/// ContentView의 onboardingBinding이 false가 되며 sheet이 닫힌다.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.displayName == nil {
                OnboardingNameView(onComplete: {})
            } else {
                OnboardingTutorialView {
                    state.completeOnboarding()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.displayName)
    }
}
