import SwiftUI

/// 앱 첫 실행 시 표시용 닉네임을 정하는 온보딩 화면.
/// 직접 입력과 건너뛰기 모두 `AppState.saveDisplayName` 계열 경로로 저장한다.
struct OnboardingNameView: View {
    private static let maxNameLength = 8

    @Environment(AppState.self) private var state
    let onComplete: () -> Void

    @State private var name: String = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: AppSpacing.none) {
            Spacer(minLength: AppSpacing.ten)

            Image("RealDaram")
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.heroImage, height: Metrics.heroImage)
                .scaleEffect(AppArtwork.daramContentScale)
                .padding(.bottom, AppSpacing.six)

            VStack(spacing: 8) {
                Text("처음 오셨네요!")
                    .font(.appFont(.heavyTitleXLarge))
                    .foregroundStyle(Color.textDefault)
                Text("앱에서 쓸 닉네임을 정해주세요")
                    .font(.appFont(.regularLabel))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.bottom, AppSpacing.six)

            VStack(alignment: .trailing, spacing: AppSpacing.oneHalf) {
                AppTextField(placeholder: "닉네임", text: $name) {
                    submit()
                }
                .focused($isFocused)
                .accessibilityIdentifier("OnboardingNameField")
                .onChange(of: name) { _, newValue in
                    guard newValue.count > Self.maxNameLength else { return }
                    name = String(newValue.prefix(Self.maxNameLength))
                }

                Text("\(name.count) / \(Self.maxNameLength)")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
                    .accessibilityLabel("닉네임 글자 수")
                    .accessibilityValue("\(name.count)자, 최대 \(Self.maxNameLength)자")
                    .accessibilityIdentifier("OnboardingNameCount")
            }
            .padding(.horizontal, AppSpacing.overlayH)

            Spacer(minLength: Metrics.actionTopSpacing)

            AppTextActionButton(
                title: "시작하기",
                font: .heavyBodyLarge,
                background: AnyShapeStyle(canSubmit ? Color.tintInteractive : Color.textDisabled.opacity(0.62)),
                radius: AppRadius.element,
                verticalPadding: AppSpacing.inputV
            ) {
                submit()
            }
            .disabled(!canSubmit || isSaving)
            .padding(.horizontal, AppSpacing.overlayH)
            .padding(.bottom, AppSpacing.ten)
            .accessibilityIdentifier("OnboardingSubmit")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPage.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button {
                Task { await state.logoutFromServer() }
            } label: {
                HStack(spacing: AppSpacing.one) {
                    Image(systemName: "chevron.left")
                        .font(.appFont(.boldCallout))
                    Text("다른 계정으로 로그인")
                }
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textMuted)
                .padding(.vertical, AppSpacing.oneHalf)
                .padding(.horizontal, AppSpacing.inner)
            }
            .padding(.leading, AppSpacing.three)
            .padding(.top, AppSpacing.dialogH)
            .accessibilityIdentifier("OnboardingSwitchAccount")
        }
        .overlay(alignment: .topTrailing) {
            if !canSubmit {
                Button {
                    skip()
                } label: {
                    Text("건너뛰기")
                        .font(.appFont(.boldLabel))
                        .foregroundStyle(Color.textMuted)
                        .padding(.vertical, AppSpacing.oneHalf)
                        .padding(.horizontal, AppSpacing.inner)
                }
                .disabled(isSaving)
                .padding(.trailing, AppSpacing.three)
                .padding(.top, AppSpacing.dialogH)
                .accessibilityIdentifier("OnboardingNameSkip")
            }
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

private enum Metrics {
    static let heroImage = AppSize.visualXLarge
    static let actionTopSpacing: CGFloat = 48
}
