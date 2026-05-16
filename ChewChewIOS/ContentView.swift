import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = Tab.initial

    enum Tab: String, CaseIterable {
        case home, track, shop

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
            case .shop:  "상점"
            }
        }

        var systemImage: String {
            switch self {
            case .home:  "house.fill"
            case .track: "waveform.path.ecg"
            case .shop:  "bag.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            ScrollView(showsIndicators: false) { HomeView() }
                .background(LinearGradient.appBackground.ignoresSafeArea())
                .tabItem {
                    Image(systemName: Tab.home.systemImage)
                    Text(Tab.home.label)
                }
                .tag(Tab.home)

            ScrollView(showsIndicators: false) { TrackingView() }
                .background(LinearGradient.appBackground.ignoresSafeArea())
                .tabItem {
                    Image(systemName: Tab.track.systemImage)
                    Text(Tab.track.label)
                }
                .tag(Tab.track)

            ScrollView(showsIndicators: false) { ShopView() }
                .background(LinearGradient.appBackground.ignoresSafeArea())
                .tabItem {
                    Image(systemName: Tab.shop.systemImage)
                    Text(Tab.shop.label)
                }
                .tag(Tab.shop)
        }
        .tint(Color.acorn600)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
