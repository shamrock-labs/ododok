import UIKit
import UserNotifications

/// UNUserNotificationCenterDelegate + UIApplicationDelegate 겸용.
/// ChewChewIOSApp의 `@UIApplicationDelegateAdaptor`로 등록.
/// 알림 탭 시 userInfo의 deepLink를 처리해 AppState.requestStartHighlight()를 호출.
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// ChewChewIOSApp.body의 .task에서 appState가 준비된 뒤 주입.
    var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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
        let userInfo = response.notification.request.content.userInfo
        guard let deepLink = userInfo["deepLink"] as? String,
              deepLink == MealNotificationService.deepLinkStart,
              let url = URL(string: deepLink) else { return }
        Task { @MainActor in
            // onOpenURL 경로와 동일한 처리 — appState가 주입되기 전 탭은 무시.
            guard let state = appState else { return }
            _ = url // URL scheme 검증은 handleOpenURL 내부
            state.requestStartHighlight()
        }
    }
}
