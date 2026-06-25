import SwiftUI
import UserNotifications
import GoogleSignIn
import KakaoSDKAuth
import KakaoSDKCommon

@main
struct ChewChewIOSApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @UIApplicationDelegateAdaptor private var notifDelegate: NotificationDelegate

    init() {
        // 크래시·에러 모니터링을 최우선 부팅 — 이후 의존성 초기화 단계의 실패까지 포착하기 위해 init 맨 앞.
        SentryService.start()
        #if DEBUG
        // Sentry 수집 검증용 의도적 크래시(launch arg `-crashTest <type>`). 인자 없으면 no-op.
        CrashTester.crashIfRequested()
        #endif
        let dependencies = ChewChewIOSApp.makeDependencies()
        _appState = State(initialValue: AppState(
            remoteStore: dependencies.remoteStore,
            authSessionManager: dependencies.authSessionManager,
            analytics: ChewChewIOSApp.makeAnalytics()
        ))
        // Kakao SDK 초기화(네이티브 앱키는 Info.plist 경유 Secrets.xcconfig). placeholder면 건너뜀.
        if let kakaoKey = Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String,
           !kakaoKey.isEmpty, !kakaoKey.contains("REPLACE") {
            KakaoSDK.initSDK(appKey: kakaoKey)
        }
    }

    /// 테스트(유닛/UI) 실행 중에는 실제 백엔드 대신 `NoopRemoteStore`를 주입한다.
    /// `AppState.init`이 곧바로 원격 fetch를 트리거하므로, 이 분기가 없으면 테스트
    /// 런마다 새 `device_id`로 서버에 row가 쌓인다(누적 오염).
    ///   - 유닛 테스트: 앱이 TEST_HOST라 `XCTestConfigurationFilePath` env가 세팅됨.
    ///   - UI 테스트: 앱이 별도 프로세스로 launch되므로 위 env가 없음 → `-useNoopRemote` arg로 감지.
    ///
    /// ODO-54 전면 전환: 기본 백엔드는 Spring(staging)이다. 레거시 InsForge는 `-useInsForge`
    /// 오버라이드로만 사용한다. 환경(바라보는 백엔드 URL) 분리는 config 주입 영역으로 별도.
    private static func makeDependencies() -> (remoteStore: RemoteStore, authSessionManager: AuthSessionManaging) {
        let pi = ProcessInfo.processInfo
        let underTest = pi.environment["XCTestConfigurationFilePath"] != nil
            || pi.arguments.contains("-useNoopRemote")
        if underTest { return (NoopRemoteStore(), NoopAuthSessionManager()) }
        // 레거시 InsForge는 명시적 오버라이드일 때만 — 기본은 Spring.
        if pi.arguments.contains("-useInsForge") {
            return (InsForgeRemoteStore(config: .default), NoopAuthSessionManager())
        }
        let springConfig = SpringConfig.current
        return (SpringRemoteStore(config: springConfig), SpringAuthClient(config: springConfig))
    }

    /// 제품·리텐션 분석 부트스트랩(ODO-79). Amplitude로 fan-out하는 CompositeAnalytics를 만든다.
    /// 테스트 런·API Key 미설정(기여자 빌드)에서는 NoopAnalytics로 안전하게 비활성.
    /// 향후 Firebase provider는 이 배열에 한 줄 추가로 합류한다(호출부 무변경).
    private static func makeAnalytics() -> AnalyticsService {
        let pi = ProcessInfo.processInfo
        let underTest = pi.environment["XCTestConfigurationFilePath"] != nil
            || pi.arguments.contains("-useNoopRemote")
        guard !underTest else { return NoopAnalytics() }

        var providers: [AnalyticsService] = []
        // Amplitude(EU) — 실사용 가능한 키일 때만. 빈값·미확장 `$(...)`·placeholder는 거부해
        // garbage 키로 SDK가 초기화되며 이벤트가 조용히 유실되는 오설정을 막는다.
        if let key = Bundle.main.object(forInfoDictionaryKey: "AmplitudeAPIKey") as? String,
           ChewChewIOSApp.isUsableSecret(key) {
            providers.append(AmplitudeProvider(apiKey: key))
        }
        // Firebase Analytics — GoogleService-Info.plist이 번들에 있을 때만(plist는 gitignore).
        if let firebase = FirebaseProvider.makeIfAvailable() {
            providers.append(firebase)
        }
        // 모든 이벤트에 environment를 첨부해 dev/prod 데이터 오염을 막는다(Sentry environment와 일관).
        // Debug=staging 빌드, Release=운영. Amplitude·Firebase 대시보드에서 이 속성으로 필터한다.
        #if DEBUG
        let environment = "debug"
        #else
        let environment = "production"
        #endif
        return providers.isEmpty
            ? NoopAnalytics()
            : CompositeAnalytics(providers, baseProperties: ["environment": environment])
    }

    /// config 주입 시크릿이 실사용 가능한 값인지 검증한다.
    /// 거부: 빈값·공백·미설정 build setting의 미확장 리터럴(`$(...)`)·placeholder(REPLACE).
    /// xcconfig 키가 아예 없을 때 Xcode가 `$(NAME)`을 빈 문자열이 아닌 리터럴로 남기는 경로까지 닫는다.
    static func isUsableSecret(_ raw: String) -> Bool {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !v.isEmpty && !v.contains("REPLACE") && !v.contains("$(")
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
                    // 소셜 로그인 콜백 우선 처리(Google / Kakao), 아니면 기존 chewchew 딥링크.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if AuthApi.isKakaoTalkLoginUrl(url) { _ = AuthController.handleOpenUrl(url: url); return }
                    handleOpenURL(url)
                }
                .task {
                    // 홈 진행도/마스코트 mood가 첫 진입부터 정확히 보이도록 오늘 세션을 미리 적재.
                    await appState.fetchTodaySessions()
                    // 끼니 알림(ODO-56): 서버 단독 + 오프라인 보조 정책으로 적용한다.
                    // 로그인·권한·APNs 토큰 등록 상태에 따라 서버(APNs) 또는 로컬 알림으로 갈린다.
                    await appState.mealPushCoordinator.apply(.load())
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
        // 카카오 공유 메시지의 "초대 수락하기" 버튼은 앱을 kakao{앱키}://kakaolink?code=... 로 연다
        // (iosExecutionParams). chewchew:// 외에 이 카카오 실행 스킴도 초대 수락으로 라우팅한다.
        if url.scheme?.hasPrefix("kakao") == true, url.host == "kakaolink" {
            if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
               !code.isEmpty {
                appState.receiveInviteCode(code)
            }
            return
        }
        guard url.scheme == "chewchew" else { return }
        switch url.host {
        case "start":
            appState.requestStartHighlight()
        case "resume":
            appState.resumeMeasurement()
        case "stop":
            appState.stopMeasurementFromNotification()
        case "invite":
            // 외부 공유 링크(chewchew://invite?code=...) 수신 → 자동 수락.
            if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
               !code.isEmpty {
                appState.receiveInviteCode(code)
            }
        default:
            break
        }
    }

    /// 시뮬레이터 진단용 launch argument.
    /// - `-autoStartEating`: 앱 진입 즉시 식사 시작.
    /// - `-autoStopAfter <seconds>`: 자동 시작 후 N초 뒤 식사 종료 (→ snapshot persist).
    /// - `-equipShowcase`: 모자/안경/액세서리 1개씩 미리 구매·장착 (꾸미기 검증용).
    /// - `-resetState`: XCUITest용 — UserDefaults/AppState 전체 초기화.
    /// - `-skipOnboarding`: XCUITest용 — displayName="테스터" + 온보딩 완료 처리로 onboarding sheet 우회.
    /// - `-useNoopRemote`: XCUITest용 — 실 백엔드 대신 NoopRemoteStore 주입(`makeRemoteStore`에서 처리).
    /// - `-highlightStart`: XCUITest용 — 앱 진입 즉시 startButtonHighlighted=true (강조 UI 검증).
    /// 운영 코드에는 영향 없음.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-resetState") {
            if let bundleID = Bundle.main.bundleIdentifier {
                // 번들 전체 UserDefaults 도메인을 비우므로 적립 캐시 키도 함께 사라진다.
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            appState.reset()
        }

        if args.contains("-skipOnboarding") {
            UserDefaults.standard.set("테스터", forKey: "ChewChewIOS.AppState.displayName")
            appState.displayName = "테스터"
            appState.hasCompletedOnboarding = true
            appState.didLoadProfile = true
        }

        // XCUITest용 — 로그인 상태를 강제해 LoginView를 우회하고 mainTabs로 진입(Keychain 토큰 유무에 비의존).
        if args.contains("-forceLogin") {
            appState.isLoggedIn = true
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
