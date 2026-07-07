import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = Tab.initial
    @State private var presentedGlobalToast: AppToastMessage?

    enum Tab: String, CaseIterable {
        case home, track, friends, shop

        static var initial: Tab {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-startTab"),
               i + 1 < args.count,
               let tab = Tab(rawValue: args[i + 1]) {
                return tab
            }
            return .home
        }

        var label: String {
            switch self {
            case .home:  "홈"
            case .track: "기록"
            case .friends: "친구"
            case .shop:  "상점"
            }
        }

        var systemImage: String {
            switch self {
            case .home:  "house"
            case .track: "waveform"
            case .friends: "person.2"
            case .shop:  "bag"
            }
        }
    }

    var body: some View {
        Group {
            if state.isLoggedIn {
                mainTabs
            } else {
                LoginView(store: state.auth)
            }
        }
        // 로그인 직후 프로필 로딩/온보딩 진입 전엔 홈을 크림+스피너로 덮어 홈 깜빡임을 차단한다.
        // 홈(mainTabs)은 그대로 렌더돼 온보딩 시트가 그 위로 정상 표시되고, 이 커버는 시각적으로만 가린다.
        // (홈을 replace하면 시트가 뜰 base가 사라져 신규 유저가 스피너에 갇히는 회귀가 있어, overlay로 덮기만 한다.)
        .overlay {
            if state.isLoggedIn && !(state.didLoadProfile && state.hasCompletedOnboarding) {
                ZStack {
                    Color.pageBackground.ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.tintInteractive)
                }
            }
        }
        .appToast($presentedGlobalToast)
        .onChange(of: state.globalToast) { _, toast in
            presentedGlobalToast = toast.map { AppToastMessage($0, kind: .info) }
        }
        .onChange(of: state.friendsTabRequestID) { _, requestID in
            guard requestID > 0 else { return }
            tab = .friends
        }
    }

    private var mainTabs: some View {
        TabView(selection: $tab) {
            tabPage {
                HomeView()
            }
                .tabItem {
                    Image(systemName: Tab.home.systemImage)
                    Text(Tab.home.label)
                }
                .tag(Tab.home)

            tabPage {
                TrackingView()
            }
                .tabItem {
                    Image(systemName: Tab.track.systemImage)
                    Text(Tab.track.label)
                }
                .tag(Tab.track)

            tabPage {
                FriendsView()
            }
                .tabItem {
                    Image(systemName: Tab.friends.systemImage)
                    Text(Tab.friends.label)
                }
                .tag(Tab.friends)

            tabPage {
                ShopView()
            }
                .tabItem {
                    Image(systemName: Tab.shop.systemImage)
                    Text(Tab.shop.label)
                }
                .tag(Tab.shop)
        }
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .tint(Color.acorn600)
        // 성공 케이스는 SessionResultSheet 카드로 표시(PRD #3) — 실패 다이얼로그는 AppDialog로 통일.
        .appDialog(
            isPresented: failureAlertBinding,
            title: "업로드에 실패했어요",
            message: uploadFailureMessage,
            primary: .init("다시 시도") { state.retryLastSessionUpload() },
            secondary: .init("취소", role: .cancel) { state.dismissSessionUploadStatus() }
        )
        .appDialog(
            isPresented: shortSessionBinding,
            title: "측정이 너무 짧아요",
            message: "1분 미만은 분석할 수 없어요. 더 씹을까요?",
            primary: .init("더 측정") {},
            secondary: .init("그만두기", role: .destructive) { state.discardCurrentSession() }
        )
        .sheet(isPresented: resultSheetBinding) {
            SessionResultSheet(
                dto: state.lastCompletedSession,
                isAnalyzing: state.sessionUploadStatus == .uploading,
                onClose: closeResultSheet
            )
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingFlowView()
        }
        // RewardDialogView는 overlay라 SessionResultSheet에 가려진다. sheet가 떠 있는 동안엔
        // 그리지 않고 대기 — sheet 닫히는 순간 자연스럽게 등장하고 그때부터 2.5s 자동 dismiss
        // 타이머가 시작되어, 세션 종료 보상 다이얼로그가 가려진 채 사라지는 회귀를 차단.
        .overlay(alignment: .center) {
            if state.lastCompletedSession == nil, let grant = state.home.pendingRewardGrant {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    RewardDialogView(grant: grant) {
                        state.home.dismissPendingRewardGrant()
                    }
                    .padding(.horizontal, 32)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(10)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.home.pendingRewardGrant)
            }
        }
        .overlay(alignment: .center) {
            if state.showAirPodsConnectionPrompt {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    AirPodsPromptDialogView {
                        state.dismissAirPodsConnectionPrompt()
                    }
                    .padding(.horizontal, AppSpacing.overlayH)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(10)
            }
        }
        .overlay(alignment: .center) {
            if let countdownValue = state.startCountdownValue {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    StartCountdownView(value: countdownValue)
                }
                .transition(.opacity)
                .zIndex(11)
            }
        }
        .animation(
            .spring(response: AppMotion.springFastResponse, dampingFraction: AppMotion.springDampingFraction),
            value: state.showAirPodsConnectionPrompt
        )
        .animation(.easeInOut(duration: AppMotion.durationStateChange), value: state.startCountdownValue)
    }

    private var shortSessionBinding: Binding<Bool> {
        Binding(
            get: { state.showShortSessionConfirm },
            set: { newValue in if !newValue { state.showShortSessionConfirm = false } }
        )
    }

    /// 업로드 실패 다이얼로그 본문 — 친화적 사유(서버/오프라인 카피) + 데이터 손실 경고.
    private var uploadFailureMessage: String {
        let reason = state.sessionUploadErrorMessage ?? "잠시 후 다시 시도해 주세요."
        return "\(reason)\n지금 닫으면 이번 기록이 사라져요."
    }

    private var failureAlertBinding: Binding<Bool> {
        Binding(
            get: { state.sessionUploadStatus == .failure },
            set: { presented in
                if !presented && state.sessionUploadStatus == .failure {
                    state.dismissSessionUploadStatus()
                }
            }
        )
    }

    /// 식사 종료 직후엔 `sessionUploadStatus == .uploading`만으로 sheet를 띄워
    /// "분석 중" 화면을 먼저 보여주고, INSERT 성공 → `lastCompletedSession` set
    /// 이후엔 같은 sheet 안에서 `ReportCardView`로 전환된다. 사용자가 닫으면
    /// `closeResultSheet`가 lastCompletedSession을 nil로 되돌리고 성공 status도
    /// 함께 정리.
    private var resultSheetBinding: Binding<Bool> {
        Binding(
            get: {
                state.lastCompletedSession != nil
                    || state.sessionUploadStatus == .uploading
            },
            set: { presented in
                if !presented { closeResultSheet() }
            }
        )
    }

    private func closeResultSheet() {
        state.lastCompletedSession = nil
        if state.sessionUploadStatus == .success {
            state.dismissSessionUploadStatus()
        }
    }

    /// 첫 실행 onboarding sheet binding — DB fetch 한 번 끝났고(`didLoadProfile`) 온보딩을
    /// 아직 안 마쳤을 때만 표시. `didLoadProfile` 가드로 reinstall cold-start의 sheet 깜빡임 방지.
    /// 닉네임 입력 + 사용법 튜토리얼은 `OnboardingFlowView`가 한 sheet 안에서 잇고,
    /// `interactiveDismissDisabled`로 강제 dismiss를 막는다. 튜토리얼 완료/건너뛰기로
    /// `hasCompletedOnboarding`이 true가 되면 binding이 false가 되어 자동 dismiss.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            // isLoggedIn 가드: 온보딩 중 "다른 계정으로 로그인"으로 로그아웃하면 sheet도 즉시 닫힌다.
            get: { state.isLoggedIn && state.didLoadProfile && !state.hasCompletedOnboarding },
            set: { _ in }
        )
    }

    private func tabPage<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                content()
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            // 스크롤 시 콘텐츠가 status bar 영역까지 비쳐 보이는 것을 막기 위해
            // 상단에 앱 배경과 같은 inset을 두어 자연스러운 헤더 buffer를 만든다.
            .safeAreaInset(edge: .top, spacing: 0) {
                LinearGradient.appBackground
                    .frame(height: 12)
                    .background(LinearGradient.appBackground.ignoresSafeArea(edges: .top))
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
