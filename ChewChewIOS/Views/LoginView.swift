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

/// 소셜 로그인 화면. Apple/Google/Kakao 중 하나로 로그인 → 서버 JWT 발급 → onLoggedIn().
/// 일반적인 앱의 소셜 로그인 UI(브랜드 컬러 풀폭 버튼)를 따른다. 온보딩 앞 게이트로 표시.
struct LoginView: View {
    /// 로그인 + 서버 토큰 발급 성공 시 호출. Bool = 서버가 판정한 onboardingCompleted,
    /// String = 로그인 method(apple/google/kakao, 분석 계측용).
    /// 호출처(AppState/ContentView)가 이 값으로 온보딩 표시 여부를 정한다.
    var onLoggedIn: (Bool, String) -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?

    private let authClient = SpringAuthClient(config: .current)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("오도독")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Color.acorn600)
                Text("잘 씹는 습관을 만드는 가장 쉬운 방법")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            VStack(spacing: 12) {
                ForEach(LoginProviderOption.allCases, id: \.self) { option in
                    socialButton(option)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            Text("로그인하면 서비스 이용약관 및 개인정보처리방침에 동의하게 돼요.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground.ignoresSafeArea())
        .disabled(isLoading)
        .overlay {
            if isLoading {
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
            Task { await signIn(with: option.makeProvider()) }
        } label: {
            ZStack {
                Text(option.title).font(.system(size: 16, weight: .semibold))
                HStack {
                    brandIcon(option).frame(width: 22, height: 22)
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(option.foreground)
            .background(option.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(option.border ?? .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 브랜드 로고. 공식 멀티컬러 G / 카카오 말풍선 심볼은 에셋 추가 시 교체 권장(지금은 근사).
    @ViewBuilder
    private func brandIcon(_ option: LoginProviderOption) -> some View {
        switch option {
        case .apple:
            Image(systemName: "apple.logo").font(.system(size: 18))
        case .google:
            Text("G")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.googleBlue)
        case .kakao:
            Image(systemName: "message.fill").font(.system(size: 15))
        }
    }

    private func signIn(with provider: SocialLoginProvider) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let credential = try await provider.login()
            let result = try await authClient.login(
                provider: credential.provider,
                idToken: credential.idToken,
                deviceId: DeviceIdentity.shared,
                name: credential.name
            )
            onLoggedIn(result.onboardingCompleted, credential.provider)
        } catch SocialLoginError.cancelled {
            // 사용자가 취소 — 에러 메시지 표시하지 않는다.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
