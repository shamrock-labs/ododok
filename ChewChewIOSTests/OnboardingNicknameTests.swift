import XCTest
@testable import ChewChewIOS

@MainActor
final class OnboardingNicknameTests: XCTestCase {
    private let displayNameKey = "ChewChewIOS.AppState.displayName"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        super.tearDown()
    }

    func testNormalizedDisplayName_limitsNameToEightCharacters() {
        XCTAssertEqual(AppState.normalizedDisplayName("가나다라마바사아자"), "가나다라마바사아")
    }

    func testNormalizedDisplayName_trimsWhitespaceBeforeLimitingLength() {
        XCTAssertEqual(AppState.normalizedDisplayName("  다람이 1234  "), "다람이 1234")
    }

    func testNormalizedDisplayName_rejectsWhitespaceOnlyName() {
        XCTAssertNil(AppState.normalizedDisplayName("   "))
    }

    func testGeneratedNickname_usesDaramPrefixAndFourDigits() {
        XCTAssertEqual(AppState.generatedNickname(number: 1234), "다람이 1234")
    }

    func testGeneratedNickname_padsSmallNumbers() {
        XCTAssertEqual(AppState.generatedNickname(number: 7), "다람이 0007")
    }

    func testSaveDisplayName_successCommitsNameAndTracksCompletedStep() async {
        let remoteStore = SpyRemoteStore()
        let analytics = OnboardingNameAnalyticsSpy()
        let state = AppState(
            remoteStore: remoteStore,
            analytics: analytics,
            startStartupTasks: false
        )

        let didSave = await state.saveDisplayName(" 다람이 ", nameMethod: .custom)

        XCTAssertTrue(didSave)
        XCTAssertEqual(state.displayName, "다람이")
        XCTAssertEqual(remoteStore.upsertedProfiles.first?.displayName, "다람이")
        XCTAssertEqual(analytics.trackedEvents.map(\.name), ["onboarding_step_completed"])
        XCTAssertEqual(analytics.trackedEvents.first?.properties["name_method"] as? String, "custom")
    }

    func testSaveDisplayName_failureKeepsNameUnsetAndTracksOnlyFailedStep() async {
        let remoteStore = SpyRemoteStore()
        remoteStore.upsertProfileError = RemoteStoreError.offline
        let analytics = OnboardingNameAnalyticsSpy()
        let state = AppState(
            remoteStore: remoteStore,
            analytics: analytics,
            startStartupTasks: false
        )

        let didSave = await state.saveDisplayName("다람이", nameMethod: .custom)

        XCTAssertFalse(didSave)
        XCTAssertNil(state.displayName)
        XCTAssertTrue(remoteStore.upsertedProfiles.isEmpty)
        XCTAssertEqual(analytics.trackedEvents.map(\.name), ["onboarding_step_failed"])
        XCTAssertEqual(analytics.trackedEvents.first?.properties["reason"] as? String, "offline")
    }

    func testSaveGeneratedDisplayName_tracksGeneratedCompletionMethod() async {
        let remoteStore = SpyRemoteStore()
        let analytics = OnboardingNameAnalyticsSpy()
        let state = AppState(
            remoteStore: remoteStore,
            analytics: analytics,
            startStartupTasks: false
        )

        let didSave = await state.saveGeneratedDisplayName()

        XCTAssertTrue(didSave)
        XCTAssertEqual(analytics.trackedEvents.map(\.name), ["onboarding_step_completed"])
        XCTAssertEqual(analytics.trackedEvents.first?.properties["name_method"] as? String, "generated")
    }
}

private final class OnboardingNameAnalyticsSpy: AnalyticsService {
    private(set) var trackedEvents: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        trackedEvents.append(event)
    }

    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}
