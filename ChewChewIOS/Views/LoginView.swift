import SwiftUI

/// 소셜 로그인 화면. Apple/Google/Kakao 중 하나로 로그인 → 서버 JWT 발급 → onLoggedIn().
/// 온보딩(이름 입력) 앞에 게이트로 표시한다.
struct LoginView: View {
    /// 로그인 + 서버 토큰 발급 성공 시 호출. 호출처(AppState/ContentView)가 다음 단계로 진행.
    var onLoggedIn: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?

    private let authClient = SpringAuthClient(config: .current)

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("오도독")
                .font(.largeTitle).bold()
            Text("로그인하고 시작하기")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            loginButton("Apple로 계속하기") { AppleLoginProvider() }
            loginButton("Google로 계속하기") { GoogleLoginProvider() }
            loginButton("카카오로 계속하기") { KakaoLoginProvider() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
        .disabled(isLoading)
        .overlay {
            if isLoading { ProgressView() }
        }
    }

    private func loginButton(_ title: String, provider: @escaping () -> SocialLoginProvider) -> some View {
        Button(title) {
            Task { await signIn(with: provider()) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    private func signIn(with provider: SocialLoginProvider) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let credential = try await provider.login()
            try await authClient.login(
                provider: credential.provider,
                idToken: credential.idToken,
                deviceId: DeviceIdentity.shared,
                name: credential.name
            )
            onLoggedIn()
        } catch SocialLoginError.cancelled {
            // 사용자가 취소 — 에러 메시지 표시하지 않는다.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
