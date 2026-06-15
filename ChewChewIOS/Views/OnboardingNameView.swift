import SwiftUI

/// 앱 첫 실행 시 사용자 이름을 받는 onboarding sheet.
/// 저장 → `AppState.saveDisplayName` → in-memory + UserDefaults + `profiles.displayName` upsert.
/// 사용자 강제 dismiss는 막음(`interactiveDismissDisabled`) — 이름 등록을 진행 조건으로.
struct OnboardingNameView: View {
    @Environment(AppState.self) private var state
    let onComplete: () -> Void

    @State private var name: String = ""
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
                    .foregroundStyle(Color.ink800)
                Text("어떻게 불러드릴까요?")
                    .font(.appFont(.regular, size: 14))
                    .foregroundStyle(Color.ink600)
            }

            TextField("이름", text: $name)
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
                        canSubmit ? Color.acorn600 : Color.ink400.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(!canSubmit)
            .padding(.horizontal, 40)
            .accessibilityIdentifier("OnboardingSubmit")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream.ignoresSafeArea())
        // 좌상단: 잘못된 계정으로 로그인했을 때 빠져나가는 출구. 서버 refresh 토큰 폐기 후
        // 로컬 세션 종료 → isLoggedIn=false라 ContentView가 LoginView로 돌아간다.
        .overlay(alignment: .topLeading) {
            Button {
                Task { await state.logoutFromServer() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("다른 계정으로 로그인")
                }
                .font(.appFont(.semibold, size: 13))
                .foregroundStyle(Color.ink600)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .padding(.leading, 12)
            .padding(.top, 22)
            .accessibilityIdentifier("OnboardingSwitchAccount")
        }
        .interactiveDismissDisabled()
        .onAppear { isFocused = true }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let captured = name
        Task {
            await state.saveDisplayName(captured)
            onComplete()
        }
    }
}
