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
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .tint(Color.acorn600)
        // 성공 케이스는 SessionResultSheet 카드로 표시(PRD #3) — alert는 실패 시에만.
        .alert("저장 실패", isPresented: failureAlertBinding) {
            Button("다시 시도") { state.retryLastSessionUpload() }
            Button("취소", role: .cancel) { state.dismissSessionUploadStatus() }
        } message: {
            Text("이번 식사의 IMU 데이터를 서버에 올리지 못했어요.\n다시 시도하지 않으면 이 세션 데이터는 사라집니다.")
        }
        .sheet(isPresented: resultSheetBinding) {
            if let dto = state.lastCompletedSession {
                SessionResultSheet(dto: dto, onClose: closeResultSheet)
            }
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingNameView(onComplete: {})
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

    /// 식사 종료 → INSERT 성공 시 AppState가 `lastCompletedSession`을 set → 이 binding이
    /// true → sheet 표시. 사용자가 닫으면 `closeResultSheet`가 lastCompletedSession을
    /// nil로 되돌리고 성공 status도 함께 정리.
    private var resultSheetBinding: Binding<Bool> {
        Binding(
            get: { state.lastCompletedSession != nil },
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

    /// 첫 실행 onboarding sheet binding — DB fetch 한 번 끝났고 displayName이 nil일 때만
    /// 표시. `didLoadProfile` 가드로 reinstall cold-start의 sheet 깜빡임 방지.
    /// OnboardingNameView의 `interactiveDismissDisabled`로 사용자 강제 dismiss 차단.
    /// 저장 시 displayName이 갱신되면 binding이 false가 되어 자동 dismiss.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { state.didLoadProfile && state.displayName == nil },
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
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
