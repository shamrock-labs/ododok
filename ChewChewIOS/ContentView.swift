import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = .home

    enum Tab: String, CaseIterable {
        case home, track, shop

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
            LinearGradient.appBackground
                .ignoresSafeArea()

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
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
