import SwiftUI

enum LoginProviderOption: CaseIterable {
    case apple
    case google
    case kakao

    var title: String {
        switch self {
        case .apple: "Apple로 계속하기"
        case .google: "Google로 계속하기"
        case .kakao: "카카오로 계속하기"
        }
    }

    var background: Color {
        switch self {
        case .apple: .black
        case .google: .white
        case .kakao: .kakaoYellow
        }
    }

    var foreground: Color {
        switch self {
        case .apple: .white
        case .google: .googleText
        case .kakao: .black.opacity(0.85)
        }
    }

    var border: Color? {
        switch self {
        case .apple, .kakao: nil
        case .google: .googleBorder
        }
    }

    @MainActor
    func makeProvider() -> SocialLoginProvider {
        switch self {
        case .apple: AppleLoginProvider()
        case .google: GoogleLoginProvider()
        case .kakao: KakaoLoginProvider()
        }
    }
}

private enum Metrics {
    static let socialIcon = AppSize.iconXLarge
    static let brandIcon = AppSize.iconSmall
    static let kakaoIcon: CGFloat = 15
    static let buttonHeight: CGFloat = 52
}

/// 소셜 로그인 화면. Apple/Google/Kakao 중 하나로 로그인 → 서버 JWT 발급 → onLoggedIn().
/// 일반적인 앱의 소셜 로그인 UI(브랜드 컬러 풀폭 버튼)를 따른다. 온보딩 앞 게이트로 표시.
struct LoginView: View {
    var store: AuthStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("오도독")
                    .font(.appFont(.loginWordmark))
                    .foregroundStyle(Color.textActionStrong)
                Text("잘 씹는 습관을 만드는 가장 쉬운 방법")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()

            VStack(spacing: 12) {
                ForEach(LoginProviderOption.allCases, id: \.self) { option in
                    socialButton(option)
                }
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textDanger)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppSpacing.gap)
            }

            Text("로그인하면 서비스 이용약관 및 개인정보처리방침에 동의하게 돼요.")
                .font(.appFont(.semiboldLabel))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, AppSpacing.sectionGap)
        }
        .padding(.horizontal, AppSpacing.six)
        .padding(.bottom, AppSpacing.seven)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground.ignoresSafeArea())
        .disabled(store.isLoading)
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    ProgressView()
                }
            }
        }
    }

    // MARK: - 브랜드 버튼

    /// 일반 소셜 로그인 버튼 스타일(브랜드 배경색 + 좌측 로고 + 중앙 라벨, 풀폭 라운드).
    private func socialButton(_ option: LoginProviderOption) -> some View {
        return Button {
            Task { await store.signIn(with: option.makeProvider()) }
        } label: {
            ZStack {
                Text(option.title).font(.appFont(.dialogAction))
                HStack {
                    brandIcon(option).frame(width: Metrics.socialIcon, height: Metrics.socialIcon)
                    Spacer()
                }
            }
            .padding(.horizontal, AppSpacing.inputH)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .foregroundStyle(option.foreground)
            .background(option.background)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.three, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.three, style: .continuous)
                    .strokeBorder(option.border ?? .clear, lineWidth: AppSize.border)
            )
        }
        .buttonStyle(.plain)
    }

    /// 브랜드 로고. 공식 멀티컬러 G / 카카오 말풍선 심볼은 에셋 추가 시 교체 권장(지금은 근사).
    @ViewBuilder
    private func brandIcon(_ option: LoginProviderOption) -> some View {
        switch option {
        case .apple:
            Image(systemName: "apple.logo").font(.appFont(.regular, size: Metrics.brandIcon))
        case .google:
            Text("G")
                .font(.appFont(.bold, size: Metrics.brandIcon))
                .foregroundStyle(Color.googleBlue)
        case .kakao:
            Image(systemName: "message.fill").font(.appFont(.regular, size: Metrics.kakaoIcon))
        }
    }

}
