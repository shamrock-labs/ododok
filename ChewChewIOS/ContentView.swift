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
        .alert(alertTitle, isPresented: alertBinding) {
            if state.sessionUploadStatus == .failure {
                Button("다시 시도") { state.retryLastSessionUpload() }
                Button("취소", role: .cancel) { state.dismissSessionUploadStatus() }
            } else {
                Button("확인", role: .cancel) { state.dismissSessionUploadStatus() }
            }
        } message: {
            if state.sessionUploadStatus == .failure {
                Text("이번 식사의 IMU 데이터를 서버에 올리지 못했어요.\n다시 시도하지 않으면 이 세션 데이터는 사라집니다.")
            } else {
                Text("이번 식사 기록이 안전하게 저장됐어요.")
            }
        }
    }

    private var alertTitle: String {
        state.sessionUploadStatus == .failure ? "저장 실패" : "식사 기록 저장 완료"
    }

    /// `sessionUploadStatus`가 terminal(success/failure)일 때만 alert 표시.
    /// SwiftUI가 닫을 때(setter=false) 만약 아직 terminal이면 dismiss 처리.
    /// retry 버튼은 status를 .uploading으로 바꾼 뒤 닫히므로 dismiss가 호출되지 않는다.
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { state.sessionUploadStatus.isTerminal },
            set: { presented in
                if !presented && state.sessionUploadStatus.isTerminal {
                    state.dismissSessionUploadStatus()
                }
            }
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
