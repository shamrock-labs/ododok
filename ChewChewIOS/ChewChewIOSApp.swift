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

    /// 시뮬레이터 진단용 launch argument.
    /// - `-autoStartEating`: 앱 진입 즉시 식사 시작.
    /// - `-autoStopAfter <seconds>`: 자동 시작 후 N초 뒤 식사 종료 (→ snapshot persist).
    /// 운영 코드에는 영향 없음.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-autoStartEating") else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            appState.startEating()
        }

        if let idx = args.firstIndex(of: "-autoStopAfter"),
           idx + 1 < args.count,
           let seconds = Double(args[idx + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + seconds) {
                appState.stopEating()
            }
        }
    }
}
