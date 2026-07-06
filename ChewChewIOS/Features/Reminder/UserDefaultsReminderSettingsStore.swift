import Foundation

struct UserDefaultsReminderSettingsStore: ReminderSettingsStoring {
    func load() -> MealReminderSettings {
        MealReminderSettings.load()
    }

    func save(_ settings: MealReminderSettings) {
        settings.save()
    }
}
