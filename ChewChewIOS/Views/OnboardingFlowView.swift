import SwiftUI

/// 첫 실행 온보딩 sheet의 루트. 닉네임 입력 → 사용법 튜토리얼 두 단계를 한 sheet 안에서
/// 잇는다. 단계는 `state.displayName`으로 파생 — 닉네임이 없으면 입력 단계, 채워지면 튜토리얼.
/// 튜토리얼 뒤에는 맞춤 감지 기준을 지금 설정할지 선택한다. 나중에 하기를 선택하거나
/// 맞춤 측정을 완료하면 `completeOnboarding()`이 sheet을 닫는다.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var state
    @State private var isCalibrationPromptPresented = false
    @State private var isPersonalizationPresented = false

    var body: some View {
        Group {
            if state.displayName == nil {
                OnboardingNameView(onComplete: {})
            } else {
                OnboardingTutorialView {
                    isCalibrationPromptPresented = true
                }
            }
        }
        .animation(.easeInOut(duration: AppMotion.durationPageChange), value: state.displayName)
        .appDialog(
            isPresented: $isCalibrationPromptPresented,
            title: "내 씹기 신호에 맞춰볼까요?",
            message: "짧게 씹어보면 다음 식사부터 내 움직임에 맞는 기준으로 감지해요.",
            supportingText: "설정 > 맞춤 감지 기준에서 언제든지 할 수 있어요.",
            primary: .init("지금 바로 하기") {
                presentPersonalizationAfterDialogDismissal()
            },
            secondary: .init("다음에 할게요", role: .cancel) {
                state.completeOnboarding()
            }
        )
        .fullScreenCover(
            isPresented: $isPersonalizationPresented,
            onDismiss: restoreCalibrationPromptIfNeeded
        ) {
            MeasurementPersonalizationFlow(
                remoteStore: state.remoteStore
            ) { _ in
                state.completeOnboarding()
            }
        }
    }

    private func presentPersonalizationAfterDialogDismissal() {
        Task { @MainActor in
            await Task.yield()
            isPersonalizationPresented = true
        }
    }

    private func restoreCalibrationPromptIfNeeded() {
        guard !state.hasCompletedOnboarding else { return }
        isCalibrationPromptPresented = true
    }
}
