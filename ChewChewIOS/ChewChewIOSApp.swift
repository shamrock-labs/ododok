import SwiftUI

@main
struct ChewChewIOSApp: App {
    @State private var appState = AppState(
        remoteStore: InsForgeRemoteStore(config: .default)
    )
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.light)
                .onAppear(perform: handleLaunchArguments)
        }
        // `initial: true` — 콜드 스타트 시 첫 .active 도달도 콜백으로 받기 위함.
        // 기본 onChange는 변경 시에만 호출돼, 앱 launch 직후 phase가 .active로
        // 세팅되는 순간을 놓쳐 일일 출석 보너스 트리거가 누락됐다.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            appState.sceneDidChange(toForeground: newPhase == .active)
        }
    }

    /// 시뮬레이터 진단용 launch argument.
    /// - `-autoStartEating`: 앱 진입 즉시 식사 시작.
    /// - `-autoStopAfter <seconds>`: 자동 시작 후 N초 뒤 식사 종료 (→ snapshot persist).
    /// - `-equipShowcase`: 모자/안경/액세서리 1개씩 미리 구매·장착 (꾸미기 검증용).
    /// 운영 코드에는 영향 없음.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-equipShowcase") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.points = max(appState.points, 2500)
                let showcase = ["hat-crown", "gls-sun", "acc-bow"].compactMap(ShopItem.by(id:))
                for item in showcase {
                    _ = appState.buyItem(item)
                    appState.equip(item)
                }
            }
        }

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
