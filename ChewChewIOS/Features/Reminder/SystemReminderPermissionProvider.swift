import Foundation
import UserNotifications

struct SystemReminderPermissionProvider: ReminderPermissionProviding {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await MealNotificationService.authorizationStatus()
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await MealNotificationService.requestAuthorizationIfNeeded()
    }
}
