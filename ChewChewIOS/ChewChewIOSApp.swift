import SwiftUI
import UserNotifications

@main
struct ChewChewIOSApp: App {
    @State private var appState = AppState(
        remoteStore: ChewChewIOSApp.makeRemoteStore()
    )
    @Environment(\.scenePhase) private var scenePhase

    @UIApplicationDelegateAdaptor private var notifDelegate: NotificationDelegate

    /// 테스트(유닛/UI) 실행 중에는 실제 InsForge 백엔드 대신 `NoopRemoteStore`를 주입한다.
    /// `AppState.init`이 곧바로 원격 fetch/upsert를 트리거하므로, 이 분기가 없으면 테스트
    /// 런마다 새 `device_id`로 profiles/user_stats row가 실 DB에 쌓인다(누적 오염).
    ///   - 유닛 테스트: 앱이 TEST_HOST라 `XCTestConfigurationFilePath` env가 세팅됨.
    ///   - UI 테스트: 앱이 별도 프로세스로 launch되므로 위 env가 없음 → `-useNoopRemote` arg로 감지.
    private static func makeRemoteStore() -> RemoteStore {
        let pi = ProcessInfo.processInfo
        let underTest = pi.environment["XCTestConfigurationFilePath"] != nil
            || pi.arguments.contains("-useNoopRemote")
        if underTest { return NoopRemoteStore() }
        // ODO-53 연결 테스트: `-useSpringBackend` arg일 때 Spring staging 백엔드로 전환.
        // 기본은 InsForge 유지 — arg를 빼면 즉시 원복된다.
        if pi.arguments.contains("-useSpringBackend") {
            return SpringRemoteStore(config: .stagingDefault)
        }
        return InsForgeRemoteStore(config: .default)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.light)
                .onAppear {
                    handleLaunchArguments()
                    // 알림 탭 딥링크 수신을 위해 delegate에 appState 연결.
                    notifDelegate.appState = appState
                }
                .onOpenURL { url in
                    handleOpenURL(url)
                }
                .task {
                    // 홈 진행도/마스코트 mood가 첫 진입부터 정확히 보이도록 오늘 세션을 미리 적재.
                    await appState.fetchTodaySessions()
                    // 권한이 이미 부여돼 있으면 저장된 끼니 알림을 재스케줄.
                    // 재부팅·재설치·앱 강제종료 후에도 pending request가 그대로 유지되지만,
                    // identifier 충돌 없이 원자적으로 다시 add — 안전한 idempotent 호출.
                    let status = await MealNotificationService.authorizationStatus()
                    guard status == .authorized || status == .provisional else { return }
                    await MealNotificationService.reschedule(.load())
                }
        }
        // `initial: true` — 콜드 스타트 시 첫 .active 도달도 콜백으로 받기 위함.
        // 기본 onChange는 변경 시에만 호출돼, 앱 launch 직후 phase가 .active로
        // 세팅되는 순간을 놓쳐 일일 출석 보너스 트리거가 누락됐다.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            appState.sceneDidChange(toForeground: newPhase == .active)
        }
    }

    /// `chewchew://` 딥링크 처리. onOpenURL 및 NotificationDelegate에서 공통 호출.
    @MainActor
    func handleOpenURL(_ url: URL) {
        guard url.scheme == "chewchew" else { return }
        switch url.host {
        case "start":
            appState.requestStartHighlight()
        case "resume":
            appState.resumeMeasurement()
        case "stop":
            appState.stopMeasurementFromNotification()
        default:
            break
        }
    }

    /// 시뮬레이터 진단용 launch argument.
    /// - `-autoStartEating`: 앱 진입 즉시 식사 시작.
    /// - `-autoStopAfter <seconds>`: 자동 시작 후 N초 뒤 식사 종료 (→ snapshot persist).
    /// - `-equipShowcase`: 모자/안경/액세서리 1개씩 미리 구매·장착 (꾸미기 검증용).
    /// - `-resetState`: XCUITest용 — UserDefaults/RewardLedger/AppState 전체 초기화.
    /// - `-skipOnboarding`: XCUITest용 — displayName="테스터" + 온보딩 완료 처리로 onboarding sheet 우회.
    /// - `-useNoopRemote`: XCUITest용 — 실 백엔드 대신 NoopRemoteStore 주입(`makeRemoteStore`에서 처리).
    /// - `-highlightStart`: XCUITest용 — 앱 진입 즉시 startButtonHighlighted=true (강조 UI 검증).
    /// 운영 코드에는 영향 없음.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-resetState") {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            RewardLedger.resetAll()
            appState.reset()
        }

        if args.contains("-skipOnboarding") {
            UserDefaults.standard.set("테스터", forKey: "ChewChewIOS.AppState.displayName")
            appState.displayName = "테스터"
            appState.hasCompletedOnboarding = true
            appState.didLoadProfile = true
        }

        if args.contains("-highlightStart") {
            appState.startButtonHighlighted = true
        }

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
