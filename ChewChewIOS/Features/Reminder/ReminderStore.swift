import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class ReminderStore {
    enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)

        var isSaving: Bool {
            self == .saving
        }
    }

    var draft: MealReminderDraft
    private(set) var lastSaved: MealReminderSettings
    private(set) var permissionStatus: UNAuthorizationStatus
    private(set) var saveState: SaveState = .idle

    var hasUnsavedChanges: Bool {
        draft.hasUnsavedChanges
    }

    private let coordinator: ReminderApplying
    private let permissionProvider: ReminderPermissionProviding
    private let settingsStore: ReminderSettingsStoring
    private let calendar: Calendar

    init(
        coordinator: ReminderApplying,
        permissionProvider: ReminderPermissionProviding,
        settingsStore: ReminderSettingsStoring,
        calendar: Calendar = .current,
        initialSettings: MealReminderSettings = .default,
        initialPermissionStatus: UNAuthorizationStatus = .notDetermined
    ) {
        self.coordinator = coordinator
        self.permissionProvider = permissionProvider
        self.settingsStore = settingsStore
        self.calendar = calendar
        self.draft = MealReminderDraft(settings: initialSettings, lastSaved: initialSettings)
        self.lastSaved = initialSettings
        self.permissionStatus = initialPermissionStatus
    }

    func load() async {
        let loaded = settingsStore.load()
        lastSaved = loaded
        draft = MealReminderDraft(settings: loaded, lastSaved: loaded)
        await refreshPermissionStatus()
    }

    func refreshPermissionStatus() async {
        permissionStatus = await permissionProvider.authorizationStatus()
    }

    func toggleSlot(_ slot: ReminderSlot, isEnabled: Bool) async {
        if isEnabled {
            guard permissionStatus != .denied else { return }
            let granted = await requestPermissionIfNeeded()
            if granted {
                setSlot(slot) { $0.enabled = true }
            }
        } else {
            setSlot(slot) { $0.enabled = false }
        }
    }

    func updateTime(_ slot: ReminderSlot, to date: Date) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        setSlot(slot) { mealSlot in
            mealSlot.hour = components.hour ?? mealSlot.hour
            mealSlot.minute = components.minute ?? mealSlot.minute
        }
    }

    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let granted = await permissionProvider.requestAuthorizationIfNeeded()
        permissionStatus = await permissionProvider.authorizationStatus()
        return granted
    }

    @discardableResult
    func saveAndFinish() async -> Bool {
        guard !saveState.isSaving else { return false }
        saveState = .saving
        let settings = draft.settings
        let outcome = await coordinator.apply(settings)

        switch outcome {
        case .saved, .skipped:
            settingsStore.save(settings)
            lastSaved = settings
            draft.lastSaved = settings
            saveState = .idle
            return true
        case .saveFailed(let reason):
            saveState = .failed(reason)
            return false
        case .sessionExpired:
            saveState = .idle
            return false
        }
    }

    func revertEdit() {
        guard draft.settings != lastSaved else { return }
        draft.settings = lastSaved
        settingsStore.save(lastSaved)
        saveState = .idle
    }

    func discardChanges() {
        draft.settings = lastSaved
        saveState = .idle
    }

    func slot(_ slot: ReminderSlot) -> MealSlot {
        switch slot {
        case .breakfast: draft.settings.breakfast
        case .lunch: draft.settings.lunch
        case .dinner: draft.settings.dinner
        case .extra1: draft.settings.extra1
        case .extra2: draft.settings.extra2
        }
    }

    func date(for slot: ReminderSlot) -> Date {
        var components = DateComponents()
        let mealSlot = self.slot(slot)
        components.hour = mealSlot.hour
        components.minute = mealSlot.minute
        return calendar.date(from: components) ?? Date()
    }

    private func setSlot(_ slot: ReminderSlot, update: (inout MealSlot) -> Void) {
        switch slot {
        case .breakfast:
            update(&draft.settings.breakfast)
        case .lunch:
            update(&draft.settings.lunch)
        case .dinner:
            update(&draft.settings.dinner)
        case .extra1:
            update(&draft.settings.extra1)
        case .extra2:
            update(&draft.settings.extra2)
        }
    }
}

enum ReminderSlot: CaseIterable {
    case breakfast
    case lunch
    case dinner
    case extra1
    case extra2
}
