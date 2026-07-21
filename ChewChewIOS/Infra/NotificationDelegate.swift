import UIKit
import UserNotifications

/// UNUserNotificationCenterDelegate + UIApplicationDelegate 겸용.
/// ChewChewIOSApp의 `@UIApplicationDelegateAdaptor`로 등록.
/// 알림 탭 시 userInfo의 deepLink를 처리해 AppState.requestStartHighlight()를 호출.
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // UIApplicationDelegate 조립 지점에서 SDK 인스턴스를 앱 수명 동안 유지한다.
    // 지역 변수로 만들면 앱 시작 이후의 UDL delegate 콜백을 안정적으로 받을 수 없다.
    private let appsFlyerService = AppsFlyerService()

    /// ChewChewIOSApp.body의 .task에서 appState가 준비된 뒤 주입.
    var appState: AppState? {
        didSet {
            flushPendingNotificationAction()
            flushPendingAppsFlyerDestination()
        }
    }

    /// appState 주입 전(콜드 스타트 직후) 도착한 알림 탭. 유실하지 않고 주입 시 처리한다.
    private var pendingNotificationAction: (action: String, deepLink: String?)?
    /// SwiftUI `.task`가 AppState를 주입하기 전에 도착한 OneLink 목적지.
    /// 마지막 목적지 하나를 보존하고 AppState 준비 직후 메인 액터에서 처리한다.
    private var pendingAppsFlyerDestination: AppsFlyerDeepLinkDestination?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 중단/재개 알림의 계속하기·그만하기 액션 버튼을 쓰려면 카테고리 등록이 선행돼야 한다.
        MealNotificationService.registerCategories()
        // AppsFlyer가 콜백을 전달하는 실행 문맥과 무관하게 앱 상태 변경은 MainActor에서 수행한다.
        // AppState가 아직 없으면 목적지는 pending 버퍼로 이동해 콜드스타트 중에도 유실되지 않는다.
        appsFlyerService.start(launchOptions: launchOptions) { [weak self] destination in
            Task { @MainActor in
                self?.handleAppsFlyerDestination(destination)
            }
        }
        return true
    }

    /// custom URL scheme으로 열린 링크를 AppsFlyer에 전달해 클릭 파라미터를 복원한다.
    /// 이후 UDL 결과는 `didResolveDeepLink`를 거쳐 허용된 앱 목적지로만 변환된다.
    func handleAppsFlyerOpenURL(_ url: URL) {
        appsFlyerService.handleOpenURL(url, options: [:])
    }

    /// iOS Universal Link로 앱이 열린 경우의 UIApplicationDelegate 진입점이다.
    /// 원본 NSUserActivity를 SDK에 넘겨 OneLink를 해석하고 어트리뷰션 흐름을 이어간다.
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        appsFlyerService.continueUserActivity(userActivity)
    }

    /// 스와이프 종료 등 정상 종료 경로에서 식사 Live Activity·중단 알림을 최선-노력으로 정리한다.
    /// (백그라운드 오디오로 실행 중일 때의 강제 종료에서 호출됨. suspend 상태 종료는 호출이
    /// 보장되지 않으므로 앱 시작 시 고아 정리(onAppear)가 백스톱으로 남는다.)
    func applicationWillTerminate(_ application: UIApplication) {
        MealNotificationService.cancelInterruptionPrompt()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await MealActivityController.endOrphanedActivities()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    /// APNs device token 수신 — 서버 식사 푸시 등록(ODO-56). 조정자가 서버 등록 + 로컬→서버 전환을 처리.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let coordinator = appState?.mealPushCoordinator
        Task { await coordinator?.didRegister(deviceToken: deviceToken) }
    }

    /// APNs 등록 실패 — 서버 발송 불가로 보고 로컬 알림을 유지한다.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        let coordinator = appState?.mealPushCoordinator
        Task { await coordinator?.didFailToRegister() }
    }

    /// 앱 foreground 상태에서 알림이 도착했을 때 banner 표시.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 사용자가 알림을 탭했을 때 deepLink 처리.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let action = response.actionIdentifier
        let deepLink = response.notification.request.content.userInfo["deepLink"] as? String
        Task { @MainActor in
            guard let state = appState else {
                // 콜드 스타트 직후 — 유실하지 않고 큐잉했다가 주입 시 처리한다.
                pendingNotificationAction = (action, deepLink)
                return
            }
            state.mealSession.handleNotificationAction(action, deepLink: deepLink)
        }
    }

    /// appState 주입 시점에 큐잉된 탭을 흘려보낸다.
    private func flushPendingNotificationAction() {
        guard appState != nil, let pending = pendingNotificationAction else { return }
        pendingNotificationAction = nil
        Task { @MainActor in
            appState?.mealSession.handleNotificationAction(pending.action, deepLink: pending.deepLink)
        }
    }

    @MainActor
    private func handleAppsFlyerDestination(_ destination: AppsFlyerDeepLinkDestination) {
        guard let appState else {
            pendingAppsFlyerDestination = destination
            return
        }
        switch destination {
        case .home:
            break
        case .start:
            appState.mealSession.requestStartHighlight()
        }
    }

    private func flushPendingAppsFlyerDestination() {
        guard appState != nil, let pendingAppsFlyerDestination else { return }
        self.pendingAppsFlyerDestination = nil
        Task { @MainActor in
            handleAppsFlyerDestination(pendingAppsFlyerDestination)
        }
    }
}
