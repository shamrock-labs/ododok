import SwiftUI

/// 첫 실행 온보딩 sheet의 루트. 닉네임 입력 → 사용법 튜토리얼 두 단계를 한 sheet 안에서
/// 잇는다. 단계는 `state.displayName`으로 파생 — 닉네임이 없으면 입력 단계, 채워지면 튜토리얼.
/// 튜토리얼이 끝나면 상위 화면에 완료를 알리고, 홈 진입 이후의 후속 안내는 `ContentView`가 맡는다.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var state

    let onTutorialFinished: (
        OnboardingCompletionMethod,
        OnboardingNameMethod,
        OnboardingStepName
    ) -> Void

    @State private var nameMethod: OnboardingNameMethod = .existing
    @State private var didTrackStart = false

    var body: some View {
        Group {
            if state.displayName == nil {
                OnboardingNameView { method in
                    nameMethod = method
                }
            } else {
                OnboardingTutorialView { completionMethod, lastStep in
                    onTutorialFinished(completionMethod, nameMethod, lastStep)
                }
            }
        }
        .animation(.easeInOut(duration: AppMotion.durationPageChange), value: state.displayName)
        .onAppear {
            guard !didTrackStart else { return }
            didTrackStart = true
            state.analytics.track(.onboardingStarted())
        }
    }
}
