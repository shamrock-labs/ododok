import SwiftUI

@main
struct ChewChewIOSApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.light)
                .onAppear(perform: handleLaunchArguments)
        }
        .onChange(of: scenePhase) { _, newPhase in
            appState.sceneDidChange(toForeground: newPhase == .active)
        }
    }

    /// 시뮬레이터 진단용 launch argument. `-autoStartEating` 로 켜면 앱 진입 즉시
    /// 식사 시작 → 트래킹 탭 캡처가 가능. 운영 코드에는 영향 없음.
    private func handleLaunchArguments() {
        if ProcessInfo.processInfo.arguments.contains("-autoStartEating") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                appState.startEating()
            }
        }
    }
}
