import Foundation
import UserNotifications

protocol ReminderApplying {
    func apply(_ settings: MealReminderSettings) async -> MealSettingsSaveOutcome
}

protocol ReminderPermissionProviding {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorizationIfNeeded() async -> Bool
}

protocol ReminderSettingsStoring {
    func load() -> MealReminderSettings
    func save(_ settings: MealReminderSettings)
}

extension MealPushCoordinator: ReminderApplying {}
