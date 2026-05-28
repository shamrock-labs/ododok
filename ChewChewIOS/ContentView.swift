import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = Tab.initial

    enum Tab: String, CaseIterable {
        case home, track, friends, shop

        static var initial: Tab {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-startTab"),
               i + 1 < args.count,
               let t = Tab(rawValue: args[i + 1]) {
                return t
            }
            return .home
        }

        var label: String {
            switch self {
            case .home:  "홈"
            case .track: "트래킹"
            case .friends: "친구"
            case .shop:  "상점"
            }
        }

        var systemImage: String {
            switch self {
            case .home:  "house.fill"
            case .track: "waveform.path.ecg"
            case .friends: "person.2.fill"
            case .shop:  "bag.fill"
            }
        }
    }

    var body: some View {
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
        .background(Color.cream.ignoresSafeArea())
        .tint(Color.acorn600)
        // 성공 케이스는 SessionResultSheet 카드로 표시(PRD #3) — 실패 다이얼로그는 AppDialog로 통일.
        .appDialog(
            isPresented: failureAlertBinding,
            title: "저장 실패",
            message: "이번 식사의 IMU 데이터를 서버에 올리지 못했어요.\n다시 시도하지 않으면 이 세션 데이터는 사라집니다.",
            primary: .init("다시 시도") { state.retryLastSessionUpload() },
            secondary: .init("취소", role: .cancel) { state.dismissSessionUploadStatus() }
        )
        .appDialog(
            isPresented: airPodsPromptBinding,
            title: "AirPods를 연결해 주세요",
            message: "씹기 분석을 위해 AirPods Pro · AirPods 3/4세대 · AirPods Max 중 하나를 연결하고 착용한 뒤 다시 시도해 주세요.",
            primary: .init("확인") {}
        )
        .appDialog(
            isPresented: emptySessionBinding,
            title: "기록되지 않았어요",
            message: "이번 식사의 IMU 신호를 받지 못해 분석을 만들지 못했어요. AirPods 연결 상태를 확인해 주세요.",
            primary: .init("확인") {}
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
            if state.lastCompletedSession == nil, let grant = state.pendingRewardGrant {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    RewardDialogView(grant: grant) {
                        state.dismissPendingRewardGrant()
                    }
                    .padding(.horizontal, 32)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(10)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.pendingRewardGrant)
            }
        }
    }

    private var emptySessionBinding: Binding<Bool> {
        Binding(
            get: { state.showEmptySessionNotice },
            set: { newValue in if !newValue { state.showEmptySessionNotice = false } }
        )
    }

    private var airPodsPromptBinding: Binding<Bool> {
        Binding(
            get: { state.showAirPodsConnectionPrompt },
            set: { newValue in if !newValue { state.showAirPodsConnectionPrompt = false } }
        )
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
    /// 이름 입력 + 사용법 튜토리얼은 `OnboardingFlowView`가 한 sheet 안에서 잇고,
    /// `interactiveDismissDisabled`로 강제 dismiss를 막는다. 튜토리얼 완료/건너뛰기로
    /// `hasCompletedOnboarding`이 true가 되면 binding이 false가 되어 자동 dismiss.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { state.didLoadProfile && !state.hasCompletedOnboarding },
            set: { _ in }
        )
    }

    private func tabPage<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                content()
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(Color.cream.ignoresSafeArea())
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
