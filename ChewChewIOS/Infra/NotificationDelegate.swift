import UIKit
import UserNotifications

/// UNUserNotificationCenterDelegate + UIApplicationDelegate 겸용.
/// ChewChewIOSApp의 `@UIApplicationDelegateAdaptor`로 등록.
/// 알림 탭 시 userInfo의 deepLink를 처리해 AppState.requestStartHighlight()를 호출.
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// ChewChewIOSApp.body의 .task에서 appState가 준비된 뒤 주입.
    var appState: AppState? {
        didSet { flushPendingNotificationAction() }
    }

    /// appState 주입 전(콜드 스타트 직후) 도착한 알림 탭. 유실하지 않고 주입 시 처리한다.
    private var pendingNotificationAction: (action: String, deepLink: String?)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 중단/재개 알림의 계속하기·그만하기 액션 버튼을 쓰려면 카테고리 등록이 선행돼야 한다.
        MealNotificationService.registerCategories()
        return true
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
}
