import XCTest
import UserNotifications
@testable import ChewChewIOS

@MainActor
final class ReminderStoreTests: XCTestCase {
    func testLoadReadsStoredSettingsAndPermission() async {
        let stored = settings(breakfastEnabled: true)
        let store = makeStore(storedSettings: stored, permissionStatus: .authorized)

        await store.load()

        XCTAssertEqual(store.draft.settings, stored)
        XCTAssertEqual(store.lastSaved, stored)
        XCTAssertEqual(store.permissionStatus, .authorized)
    }

    func testRequestPermissionAllowedUpdatesStatus() async {
        let permission = FakeReminderPermissionProvider(status: .notDetermined, requestResult: true, statusAfterRequest: .authorized)
        let analytics = ReminderAnalyticsSpy()
        let store = makeStore(permission: permission, analytics: analytics)

        let granted = await store.requestPermissionIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertEqual(store.permissionStatus, .authorized)
        XCTAssertEqual(analytics.events.map(\.name), ["permission_result"])
        XCTAssertEqual(analytics.events.first?.properties["type"] as? String, "notification")
        XCTAssertEqual(analytics.events.first?.properties["status"] as? String, "authorized")
        XCTAssertEqual(analytics.events.first?.properties["source"] as? String, "reminder_settings")
    }

    func testRequestPermissionDeniedKeepsSlotOff() async {
        let permission = FakeReminderPermissionProvider(status: .denied, requestResult: false, statusAfterRequest: .denied)
        let store = makeStore(permission: permission)

        await store.toggleSlot(.breakfast, isEnabled: true)

        XCTAssertFalse(store.draft.settings.breakfast.enabled)
        XCTAssertEqual(store.permissionStatus, .denied)
    }

    func testToggleOnAndOffMutatesDraftOnly() async {
        let settings = settings(breakfastEnabled: false)
        let localStore = FakeReminderSettingsStore(settings: settings)
        let store = makeStore(storedSettings: settings, localStore: localStore, permissionStatus: .authorized)
        await store.load()

        await store.toggleSlot(.breakfast, isEnabled: true)
        await store.toggleSlot(.breakfast, isEnabled: false)

        XCTAssertFalse(store.draft.settings.breakfast.enabled)
        XCTAssertEqual(localStore.savedSettings.count, 0)
    }

    func testTimeChangeMutatesDraftOnlyUntilSave() {
        let localStore = FakeReminderSettingsStore(settings: .default)
        let store = makeStore(localStore: localStore)

        store.updateTime(.lunch, to: fixedDate(hour: 14, minute: 20))

        XCTAssertEqual(store.draft.settings.lunch.hour, 14)
        XCTAssertEqual(store.draft.settings.lunch.minute, 20)
        XCTAssertEqual(localStore.savedSettings.count, 0)
    }

    func testSaveSuccessUpdatesLastSavedAndLocalStore() async {
        let localStore = FakeReminderSettingsStore(settings: .default)
        let coordinator = FakeReminderApplying(outcome: .saved)
        let store = makeStore(coordinator: coordinator, localStore: localStore, permissionStatus: .authorized)

        await store.toggleSlot(.dinner, isEnabled: true)
        let didFinish = await store.saveAndFinish()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(store.lastSaved, store.draft.settings)
        XCTAssertEqual(localStore.savedSettings.last, store.draft.settings)
        XCTAssertEqual(coordinator.appliedSettings.last, store.draft.settings)
    }

    func testUnsavedChangesRequireDismissConfirmation() async {
        let store = makeStore(permissionStatus: .authorized)

        await store.toggleSlot(.breakfast, isEnabled: true)

        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.draft.dismissDecision, .confirmDiscard)
    }

    func testSaveFailureKeepsDraftAndLastSaved() async {
        let initial = settings(breakfastEnabled: false)
        let coordinator = FakeReminderApplying(outcome: .saveFailed(reason: "오프라인"))
        let store = makeStore(storedSettings: initial, coordinator: coordinator, permissionStatus: .authorized)
        await store.load()

        await store.toggleSlot(.breakfast, isEnabled: true)
        let edited = store.draft.settings
        let didFinish = await store.saveAndFinish()

        XCTAssertFalse(didFinish)
        XCTAssertEqual(store.draft.settings, edited)
        XCTAssertEqual(store.lastSaved, initial)
        XCTAssertEqual(store.saveState, .failed("오프라인"))
    }

    func testSessionExpiredDoesNotSaveLocalSettings() async {
        let localStore = FakeReminderSettingsStore(settings: .default)
        let coordinator = FakeReminderApplying(outcome: .sessionExpired)
        let store = makeStore(coordinator: coordinator, localStore: localStore, permissionStatus: .authorized)

        await store.toggleSlot(.breakfast, isEnabled: true)
        let didFinish = await store.saveAndFinish()

        XCTAssertFalse(didFinish)
        XCTAssertEqual(localStore.savedSettings.count, 0)
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    private func makeStore(
        storedSettings: MealReminderSettings = .default,
        coordinator: FakeReminderApplying = FakeReminderApplying(),
        permission: FakeReminderPermissionProvider? = nil,
        localStore: FakeReminderSettingsStore? = nil,
        analytics: AnalyticsService = NoopAnalytics(),
        permissionStatus: UNAuthorizationStatus = .notDetermined
    ) -> ReminderStore {
        let permissionProvider = permission ?? FakeReminderPermissionProvider(status: permissionStatus)
        let settingsStore = localStore ?? FakeReminderSettingsStore(settings: storedSettings)
        return ReminderStore(
            coordinator: coordinator,
            permissionProvider: permissionProvider,
            settingsStore: settingsStore,
            analytics: analytics,
            calendar: testCalendar,
            initialSettings: storedSettings,
            initialPermissionStatus: permissionStatus
        )
    }

    private func settings(breakfastEnabled: Bool) -> MealReminderSettings {
        var settings = MealReminderSettings.default
        settings.breakfast.enabled = breakfastEnabled
        return settings
    }

    private func fixedDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return testCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}

private final class ReminderAnalyticsSpy: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}

private final class FakeReminderApplying: ReminderApplying {
    private let outcome: MealSettingsSaveOutcome
    private(set) var appliedSettings: [MealReminderSettings] = []

    init(outcome: MealSettingsSaveOutcome = .saved) {
        self.outcome = outcome
    }

    func apply(_ settings: MealReminderSettings) async -> MealSettingsSaveOutcome {
        appliedSettings.append(settings)
        return outcome
    }
}

private final class FakeReminderPermissionProvider: ReminderPermissionProviding {
    private var status: UNAuthorizationStatus
    private let requestResult: Bool
    private let statusAfterRequest: UNAuthorizationStatus

    init(
        status: UNAuthorizationStatus,
        requestResult: Bool = true,
        statusAfterRequest: UNAuthorizationStatus? = nil
    ) {
        self.status = status
        self.requestResult = requestResult
        self.statusAfterRequest = statusAfterRequest ?? status
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        status = statusAfterRequest
        return requestResult
    }
}

private final class FakeReminderSettingsStore: ReminderSettingsStoring {
    private let settings: MealReminderSettings
    private(set) var savedSettings: [MealReminderSettings] = []

    init(settings: MealReminderSettings) {
        self.settings = settings
    }

    func load() -> MealReminderSettings {
        settings
    }

    func save(_ settings: MealReminderSettings) {
        savedSettings.append(settings)
    }
}
