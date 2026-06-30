import XCTest
@testable import ChewChewIOS

/// MealPushCoordinator의 서버 전환·로그아웃·미로그인·서버 동기화 경로 테스트(ODO-56, ODO-103).
/// RemoteStore는 스파이로, 로그인 여부는 클로저 주입으로, UserDefaults는 격리 suite 주입으로 대체해
/// 키체인/알림권한/전역 UserDefaults 없이 결정적으로 검증한다.
/// (서명 없는 시뮬레이터 테스트는 Keychain이 막혀 TokenManager가 동작하지 않으므로 주입이 필수.)
@MainActor
final class MealPushCoordinatorTests: XCTestCase {

    /// push/fetch 호출을 기록하고 나머지 RemoteStore 메서드는 NoopRemoteStore에 위임하는 스파이.
    final class SpyRemoteStore: RemoteStore {
        private let base = NoopRemoteStore()
        var registerCalls: [(token: String, environment: String)] = []
        var upsertCount = 0
        var deactivateCalls: [String] = []
        var registerError: Error?
        var upsertError: Error?
        var fetchResult: MealReminderSettings?
        var fetchError: Error?
        var fetchCallCount = 0

        func registerPushToken(_ token: String, environment: String) async throws {
            registerCalls.append((token, environment))
            if let registerError { throw registerError }
        }
        func upsertMealNotifications(_ settings: MealReminderSettings, timeZone: String) async throws {
            upsertCount += 1
            if let upsertError { throw upsertError }
        }
        func deactivatePushToken(_ token: String) async throws {
            deactivateCalls.append(token)
        }
        func fetchMealNotifications() async throws -> MealReminderSettings? {
            fetchCallCount += 1
            if let fetchError { throw fetchError }
            return fetchResult
        }

        // 미사용 경로 — Noop에 위임.
        func upsertProfile(_ profile: ProfileDTO) async throws { try await base.upsertProfile(profile) }
        func fetchProfile() async throws -> ProfileDTO? { try await base.fetchProfile() }
        func fetchUserStats() async throws -> UserStatsDTO? { try await base.fetchUserStats() }
        func deleteUserData() async throws { try await base.deleteUserData() }
        func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
            try await base.createChewingSession(session)
        }
        func fetchHome(deviceId: String) async throws -> HomeStateDTO { try await base.fetchHome(deviceId: deviceId) }
        func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
            try await base.earnAttendance(deviceId: deviceId, idempotencyKey: idempotencyKey)
        }
        func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] {
            try await base.fetchChewingSessions(deviceId: deviceId, since: since, until: until)
        }
        func deleteChewingSession(id: UUID, deviceId: String) async throws {
            try await base.deleteChewingSession(id: id, deviceId: deviceId)
        }
        func deleteAllChewingSessions(deviceId: String) async throws { try await base.deleteAllChewingSessions(deviceId: deviceId) }
        func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String {
            try await base.uploadIMUCSV(sessionId: sessionId, deviceId: deviceId, csvData: csvData)
        }
    }

    /// @Sendable 클로저에서 변경 가능한 플래그 캡처용(테스트 한정).
    final class CallFlag: @unchecked Sendable {
        var value = false
    }

    /// [0xab,0xcd,0x01,0x02] → "abcd0102"
    private let fakeToken = Data([0xAB, 0xCD, 0x01, 0x02])

    /// 테스트별 격리된 UserDefaults suite. 전역 .standard를 오염시키지 않는다.
    private var suiteNames: [String] = []
    private func makeDefaults() -> UserDefaults {
        let suite = "test.mealpush.\(UUID().uuidString)"
        suiteNames.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        for suite in suiteNames {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        suiteNames = []
        super.tearDown()
    }

    private func armed(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: MealPushCoordinator.deliveryArmedKey)
    }

    // MARK: - didRegister

    func testDidRegister_whenLoggedIn_registersTokenAndArmsDelivery_withoutPushingSettings() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        await coordinator.didRegister(deviceToken: fakeToken)

        XCTAssertEqual(spy.registerCalls.map(\.token), ["abcd0102"])
        XCTAssertEqual(spy.registerCalls.first?.environment, "sandbox")   // DEBUG 빌드
        XCTAssertEqual(spy.upsertCount, 0, "등록 시점에 로컬 설정을 서버로 올리면 안 된다(계정 덮어쓰기 버그)")
        XCTAssertTrue(armed(defaults), "등록 성공 시 서버 발송 가능(armed)으로 영속돼야 한다")
    }

    func testDidRegister_whenLoggedOut_doesNotRegister() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { false }, defaults: defaults)

        await coordinator.didRegister(deviceToken: fakeToken)

        XCTAssertTrue(spy.registerCalls.isEmpty)
        XCTAssertEqual(spy.upsertCount, 0)
        XCTAssertFalse(armed(defaults))
    }

    func testDidRegister_authExpired_triggersAuthExpiredHandler() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        spy.registerError = RemoteStoreError.authExpired
        let expired = CallFlag()
        let coordinator = MealPushCoordinator(
            remoteStore: spy, isLoggedIn: { true }, onAuthExpired: { expired.value = true }, defaults: defaults)

        await coordinator.didRegister(deviceToken: fakeToken)

        XCTAssertTrue(expired.value, "authExpired는 세션 만료 핸들러로 연결돼야 한다")
        XCTAssertFalse(armed(defaults))
    }

    func testDidRegister_registerFailure_doesNotArmOrRetainToken() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        spy.registerError = RemoteStoreError.offline
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        await coordinator.didRegister(deviceToken: fakeToken)
        // 등록 실패 → armed 미설정 + 토큰 미보유 → 로그아웃해도 deactivate 호출 없음.
        XCTAssertFalse(armed(defaults), "백엔드 등록 실패 시 서버 발송 신호를 세우면 안 된다")
        await coordinator.handleLogout()
        XCTAssertTrue(spy.deactivateCalls.isEmpty)
    }

    func testDidRegister_whenAlreadyArmed_backendFailureKeepsArmed() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: MealPushCoordinator.deliveryArmedKey)   // 이전 세션에 등록돼 armed
        let spy = SpyRemoteStore()
        spy.registerError = RemoteStoreError.offline
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        await coordinator.didRegister(deviceToken: fakeToken)

        XCTAssertTrue(armed(defaults), "백엔드 등록 실패 시 기존 armed(이전 세션 서버 토큰)를 유지해야 한다 — 로컬을 새로 켜지 않음")
        await coordinator.handleLogout()
        XCTAssertTrue(spy.deactivateCalls.isEmpty, "이번 세션 토큰 미보유 → deactivate 대상 없음")
    }

    // MARK: - logout

    func testHandleLogout_deactivatesRegisteredTokenAndDisarms() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)
        await coordinator.didRegister(deviceToken: fakeToken)   // 토큰 등록 + arm 선행
        XCTAssertTrue(armed(defaults))

        await coordinator.handleLogout()

        XCTAssertEqual(spy.deactivateCalls, ["abcd0102"])
        XCTAssertFalse(armed(defaults), "로그아웃 시 서버 발송 신호를 내려야 다음 계정에 안 샌다")
    }

    func testClearRegistration_disarms() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)
        await coordinator.didRegister(deviceToken: fakeToken)
        XCTAssertTrue(armed(defaults))

        await coordinator.clearRegistration()

        XCTAssertFalse(armed(defaults))
    }

    // MARK: - apply (설정 저장 결과 보고)

    func testApply_upsertSuccess_returnsSaved() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        let outcome = await coordinator.apply(.default)

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(spy.upsertCount, 1, "설정은 서버에 PUT돼야 한다")
    }

    func testApply_upsertOffline_returnsSaveFailedWithUserMessage() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        spy.upsertError = RemoteStoreError.offline
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        let outcome = await coordinator.apply(.default)

        XCTAssertEqual(outcome, .saveFailed(reason: "인터넷 연결을 확인해 주세요."),
                       "저장 실패는 사용자 친화 사유와 함께 보고돼 설정 화면이 실패 다이얼로그를 띄운다")
    }

    func testApply_upsertAuthExpired_returnsSessionExpiredAndTriggersHandler() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        spy.upsertError = RemoteStoreError.authExpired
        let expired = CallFlag()
        let coordinator = MealPushCoordinator(
            remoteStore: spy, isLoggedIn: { true }, onAuthExpired: { expired.value = true }, defaults: defaults)

        let outcome = await coordinator.apply(.default)

        XCTAssertEqual(outcome, .sessionExpired)
        XCTAssertTrue(expired.value)
    }

    func testApply_loggedOut_returnsSkippedWithoutUpsert() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { false }, defaults: defaults)

        let outcome = await coordinator.apply(.default)

        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(spy.upsertCount, 0)
    }

    // MARK: - syncFromServer (서버 단일 진실원천)

    func testSyncFromServer_savesFetchedSettingsToLocalCache() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        var fetched = MealReminderSettings.default
        fetched.lunch = MealSlot(enabled: true, hour: 13, minute: 45)
        spy.fetchResult = fetched
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        await coordinator.syncFromServer()

        XCTAssertEqual(spy.fetchCallCount, 1)
        XCTAssertEqual(MealReminderSettings.load(from: defaults), fetched, "서버값으로 로컬 캐시를 갱신해야 한다")
    }

    func testSyncFromServer_serverHasNoSchedule_resetsLocalToDefault() async {
        let defaults = makeDefaults()
        // 이전 계정 잔류값을 미리 심어둔다.
        var stale = MealReminderSettings.default
        stale.dinner = MealSlot(enabled: true, hour: 20, minute: 15)
        stale.save(to: defaults)

        let spy = SpyRemoteStore()
        spy.fetchResult = nil   // 404 = 이 계정은 서버에 설정 없음
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        await coordinator.syncFromServer()

        XCTAssertEqual(MealReminderSettings.load(from: defaults), .default,
                       "서버 미설정(404)이면 이전 계정 값이 남지 않게 기본값으로 비워야 한다")
    }

    func testSyncFromServer_serverUnreachable_keepsLocalCacheAndDoesNotThrow() async {
        let defaults = makeDefaults()
        var cached = MealReminderSettings.default
        cached.breakfast = MealSlot(enabled: true, hour: 7, minute: 30)
        cached.save(to: defaults)

        let spy = SpyRemoteStore()
        spy.fetchError = RemoteStoreError.offline
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true }, defaults: defaults)

        await coordinator.syncFromServer()

        XCTAssertEqual(MealReminderSettings.load(from: defaults), cached,
                       "서버 미도달이면 로컬 캐시를 덮어쓰지 않는다(끼니 시각 미확보)")
    }

    func testSyncFromServer_authExpired_triggersHandlerAndDoesNotTouchCache() async {
        let defaults = makeDefaults()
        var cached = MealReminderSettings.default
        cached.lunch = MealSlot(enabled: true, hour: 12, minute: 0)
        cached.save(to: defaults)

        let spy = SpyRemoteStore()
        spy.fetchError = RemoteStoreError.authExpired
        let expired = CallFlag()
        let coordinator = MealPushCoordinator(
            remoteStore: spy, isLoggedIn: { true }, onAuthExpired: { expired.value = true }, defaults: defaults)

        await coordinator.syncFromServer()

        XCTAssertTrue(expired.value)
        XCTAssertEqual(MealReminderSettings.load(from: defaults), cached)
    }

    func testSyncFromServer_loggedOut_doesNotFetch() async {
        let defaults = makeDefaults()
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { false }, defaults: defaults)

        await coordinator.syncFromServer()

        XCTAssertEqual(spy.fetchCallCount, 0)
    }

    // MARK: - MealReminderSettings 로컬 캐시 clear

    func testMealReminderSettings_clear_removesCachedValue() {
        let defaults = makeDefaults()
        var custom = MealReminderSettings.default
        custom.lunch = MealSlot(enabled: true, hour: 11, minute: 11)
        custom.save(to: defaults)
        XCTAssertEqual(MealReminderSettings.load(from: defaults), custom)

        MealReminderSettings.clear(from: defaults)

        XCTAssertEqual(MealReminderSettings.load(from: defaults), .default,
                       "clear 후에는 기본값으로 되돌아가야 한다")
    }
}
