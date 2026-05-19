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

            Image(Mood.happy.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)

            VStack(spacing: 8) {
                Text("처음 오셨네요!")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Color.ink800)
                Text("어떻게 불러드릴까요?")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink600)
            }

            TextField("이름", text: $name)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { submit() }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                .neuoShadow(.sm)
                .padding(.horizontal, 40)

            Button { submit() } label: {
                Text("시작하기")
                    .font(.system(size: 16, weight: .heavy))
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.appBackground.ignoresSafeArea())
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
