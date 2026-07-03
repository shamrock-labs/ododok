import SwiftUI

/// 앱 첫 실행 시 표시용 닉네임을 정하는 온보딩 화면.
/// 직접 입력과 건너뛰기 모두 `AppState.saveDisplayName` 계열 경로로 저장한다.
struct OnboardingNameView: View {
    @Environment(AppState.self) private var state
    let onComplete: () -> Void

    @State private var name: String = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("DaramHi")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)

            VStack(spacing: 8) {
                Text("처음 오셨네요!")
                    .font(.appFont(.heavy, size: 22))
                    .foregroundStyle(Color.textPrimary)
                Text("앱에서 쓸 닉네임을 정해주세요")
                    .font(.appFont(.regular, size: 14))
                    .foregroundStyle(Color.textSecondary)
            }

            TextField("닉네임", text: $name)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { submit() }
                .font(.appFont(.semibold, size: 16))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                .neuoShadow(.sm)
                .padding(.horizontal, 40)
                .accessibilityIdentifier("OnboardingNameField")

            Button { submit() } label: {
                Text("시작하기")
                    .font(.appFont(.heavy, size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        canSubmit ? Color.tintInteractive : Color.textTertiary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(!canSubmit || isSaving)
            .padding(.horizontal, 40)
            .accessibilityIdentifier("OnboardingSubmit")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button {
                Task { await state.logoutFromServer() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("다른 계정으로 로그인")
                }
                .font(.appFont(.bold, size: 14))
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .padding(.leading, 12)
            .padding(.top, 22)
            .accessibilityIdentifier("OnboardingSwitchAccount")
        }
        .overlay(alignment: .topTrailing) {
            Button {
                skip()
            } label: {
                Text("건너뛰기")
                    .font(.appFont(.bold, size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
            }
            .disabled(isSaving)
            .padding(.trailing, 12)
            .padding(.top, 22)
            .accessibilityIdentifier("OnboardingNameSkip")
        }
        .interactiveDismissDisabled()
        .onAppear { isFocused = true }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit, !isSaving else { return }
        let captured = name
        isSaving = true
        Task { @MainActor in
            await state.saveDisplayName(captured)
            isSaving = false
            onComplete()
        }
    }

    private func skip() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            await state.saveGeneratedDisplayName()
            isSaving = false
            onComplete()
        }
    }
}
