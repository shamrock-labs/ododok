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
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                Group {
                    switch tab {
                    case .home:  HomeView()
                    case .track: TrackingView()
                    case .shop:  ShopView()
                    }
                }
                .padding(.bottom, 110)
            }

            TabBarView(selection: $tab)
        }
        .background(
            LinearGradient.appBackground.ignoresSafeArea()
        )
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
