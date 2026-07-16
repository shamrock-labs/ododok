import XCTest
@testable import ChewChewIOS

/// `deleteUserData`가 실제로 한 번 호출되는지 추적하는 테스트용 Spy.
final class SpyRemoteStore: RemoteStore {
    private(set) var deleteUserDataCallCount = 0
    private(set) var deleteUserDataAccessToken: String?
    private(set) var deleteUserDataRefreshToken: String?
    private(set) var acceptedInviteCodes: [String] = []
    var deleteUserDataError: Error?
    var fetchHomeError: Error?
    var acceptFriendInviteError: Error?
    var home: HomeStateDTO?

    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile() async throws -> ProfileDTO? { nil }
    func fetchUserStats() async throws -> UserStatsDTO? { nil }
    func deleteUserData() async throws {
        deleteUserDataCallCount += 1
        if let deleteUserDataError { throw deleteUserDataError }
    }
    func deleteUserData(accessToken: String?) async throws {
        deleteUserDataAccessToken = accessToken
        try await deleteUserData()
    }
    func deleteUserData(accessToken: String?, refreshToken: String?) async throws {
        deleteUserDataAccessToken = accessToken
        deleteUserDataRefreshToken = refreshToken
        try await deleteUserData()
    }
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        CreateSessionResultDTO(
            chewingSession: session,
            mealReport: MealReportDTO(status: .unreportable, reason: .analysisMissing),
            chewingSessionAccepted: true,
            rewardEligible: false,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 0, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 0, event: "NONE", freezeInventory: 0),
            today: SessionTodayDTO(completed: false),
            userStats: .empty(deviceId: session.deviceId)
        )
    }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO {
        if let fetchHomeError { throw fetchHomeError }
        return home ?? .empty(deviceId: deviceId)
    }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        AttendanceResultDTO(grantedPoints: 0, capped: false, idempotentReplay: false, userStats: .empty(deviceId: deviceId))
    }
    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String { "" }
    func acceptFriendInvite(code: String) async throws -> FriendAcceptResultDTO {
        acceptedInviteCodes.append(code)
        if let acceptFriendInviteError { throw acceptFriendInviteError }
        return FriendAcceptResultDTO(accepted: true, bonusGranted: true)
    }
}

final class SpyAuthSessionManager: AuthSessionManaging {
    // swiftlint:disable:next large_tuple
    typealias AuthMeResult = (userId: String, displayName: String?, onboardingCompleted: Bool, alertVolume: Double?)

    private(set) var logoutCallCount = 0
    /// me() 가 반환할 값. nil이면 throw(오프라인 시뮬레이션).
    var meResult: AuthMeResult?

    func logout() async {
        logoutCallCount += 1
        TokenManager.clear()
    }
    func me() async throws -> AuthMeResult {
        guard let result = meResult else { throw RemoteStoreError.offline }
        return result
    }
}

private final class FakeAuthTokenStorage: AuthTokenStorage {
    var accessToken: String?
    var refreshToken: String?

    var isLoggedIn: Bool {
        accessToken != nil
    }

    init(accessToken: String? = nil, refreshToken: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func save(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
    }
}

private final class UserFlowSpyAnalytics: AnalyticsService {
    private(set) var trackedEvents: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        trackedEvents.append(event)
    }

    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}

@MainActor
final class EraseAllUserDataTests: XCTestCase {
    private let pendingInviteKey = "ChewChewIOS.AppState.pendingInviteCode"

    override func setUp() {
        super.setUp()
        TokenManager.clear()
        UserDefaults.standard.removeObject(forKey: pendingInviteKey)
        UserDefaults.standard.removeObject(forKey: "ChewChewIOS.AppState.analyticsUserId")
    }

    override func tearDown() {
        TokenManager.clear()
        UserDefaults.standard.removeObject(forKey: pendingInviteKey)
        UserDefaults.standard.removeObject(forKey: "ChewChewIOS.AppState.analyticsUserId")
        super.tearDown()
    }

    private func waitFor(_ predicate: @autoclosure () -> Bool) async {
        for _ in 0..<50 where !predicate() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testEraseAllUserData_callsDeleteUserDataOnce() async throws {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)

        try await state.eraseAllUserData()

        XCTAssertEqual(spy.deleteUserDataCallCount, 1, "eraseAllUserData 호출 시 deleteUserData가 정확히 1회 호출되어야 한다")
    }

    func testEraseAllUserData_resetsPointsToZero() async throws {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)
        state.points = 500

        try await state.eraseAllUserData()

        XCTAssertEqual(state.points, 0, "삭제 후 points는 0이어야 한다")
    }

    func testEraseAllUserData_resetsTodaySessionsToEmpty() async throws {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)
        state.mealResults.todaySessions = [
            ChewingSessionDTO(
                id: UUID(),
                deviceId: "test-device",
                startedAt: Date(),
                endedAt: Date(),
                durationSec: 60,
                sensorLocation: "left",
                sampleCount: 10,
                sampleRateHz: 50,
                storagePath: "path",
                appVersion: nil,
                chewingSeconds: nil,
                restSeconds: nil,
                chewingFraction: nil,
                estimatedTotalChews: nil,
                modelVersion: nil
            )
        ]

        try await state.eraseAllUserData()

        XCTAssertTrue(state.mealResults.todaySessions.isEmpty, "삭제 후 todaySessions는 빈 배열이어야 한다")
    }

    func testEraseAllUserDataClearsPendingRuntimeState() async throws {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)
        state.mealSession.pendingMealStartRequest = true
        state.mealResults.sessionUploadStatus = .failure
        state.mealResults.sessionUploadErrorMessage = "offline"
        state.receiveInviteCode("FRIEND-123")

        try await state.eraseAllUserData()

        XCTAssertFalse(state.mealSession.pendingMealStartRequest)
        XCTAssertEqual(state.mealResults.sessionUploadStatus, .idle)
        XCTAssertNil(state.mealResults.sessionUploadErrorMessage)
        XCTAssertNil(state.friends.pendingInviteCode)
    }

    func testEraseAllUserData_resetsStreakToZero() async throws {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)
        state.streak = 7

        try await state.eraseAllUserData()

        XCTAssertEqual(state.streak, 0, "삭제 후 streak은 0이어야 한다")
    }

    func testEraseAllUserDataReturnsToLoginGate() async throws {
        TokenManager.save(access: "access-token", refresh: "refresh-token")
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)
        state.isLoggedIn = true

        XCTAssertTrue(state.isLoggedIn)

        try await state.eraseAllUserData()

        XCTAssertFalse(state.isLoggedIn, "계정 삭제 후 ContentView가 로그인 게이트로 돌아가야 스피너 오버레이에 갇히지 않는다")
    }

    func testEraseAllUserDataTracksAccountDeletedBeforeClearingSession() async throws {
        let analytics = UserFlowSpyAnalytics()
        let state = AppState(remoteStore: SpyRemoteStore(), analytics: analytics, startStartupTasks: false)

        try await state.eraseAllUserData()

        let event = analytics.trackedEvents.first
        XCTAssertEqual(event?.name, "account_deleted")
        XCTAssertEqual(event?.properties["source"] as? String, "settings")
    }

    func testEraseAllUserDataClearsTokensAfterServerSuccessAndUsesTokenSnapshotForDelete() async throws {
        let tokens = FakeAuthTokenStorage(accessToken: "access-token", refreshToken: "refresh-token")
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, authTokenStorage: tokens, startStartupTasks: false)

        try await state.eraseAllUserData()

        XCTAssertNil(tokens.accessToken)
        XCTAssertNil(tokens.refreshToken)

        let restoredState = AppState(
            remoteStore: NoopRemoteStore(),
            authTokenStorage: tokens,
            startStartupTasks: false
        )
        XCTAssertFalse(
            restoredState.isLoggedIn,
            "계정 삭제 직후 재실행되어도 Keychain 토큰으로 로그인 상태가 복원되면 안 된다"
        )

        await waitFor(spy.deleteUserDataAccessToken != nil)
        XCTAssertEqual(
            spy.deleteUserDataAccessToken,
            "access-token",
            "서버 삭제 요청은 Keychain이 아니라 삭제 시점 token snapshot으로 인증해야 한다"
        )
        XCTAssertEqual(
            spy.deleteUserDataRefreshToken,
            "refresh-token",
            "삭제 요청 중 access token 만료 시에도 Keychain 없이 refresh snapshot으로 재시도해야 한다"
        )
    }

    func testEraseAllUserDataPreservesLocalSessionWhenServerDeleteFails() async {
        let tokens = FakeAuthTokenStorage(accessToken: "access-token", refreshToken: "refresh-token")
        let spy = SpyRemoteStore()
        spy.deleteUserDataError = RemoteStoreError.offline
        let analytics = UserFlowSpyAnalytics()
        let state = AppState(
            remoteStore: spy,
            analytics: analytics,
            authTokenStorage: tokens,
            startStartupTasks: false
        )
        state.isLoggedIn = true
        state.displayName = "기존계정"
        state.hasCompletedOnboarding = true
        state.points = 42
        state.streak = 3

        do {
            try await state.eraseAllUserData()
            XCTFail("서버 삭제 실패가 호출자에게 전달되어야 한다")
        } catch RemoteStoreError.offline {
            // expected
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }

        XCTAssertEqual(spy.deleteUserDataCallCount, 1)
        XCTAssertEqual(tokens.accessToken, "access-token")
        XCTAssertEqual(tokens.refreshToken, "refresh-token")
        XCTAssertTrue(state.isLoggedIn)
        XCTAssertEqual(state.displayName, "기존계정")
        XCTAssertTrue(state.hasCompletedOnboarding)
        XCTAssertEqual(state.points, 42)
        XCTAssertEqual(state.streak, 3)
        XCTAssertFalse(
            analytics.trackedEvents.contains { $0.name == "account_deleted" },
            "서버가 거부한 탈퇴를 완료 이벤트로 기록하면 안 된다"
        )
    }

    func testLogoutClearsLocalAccountCacheWithoutDeletingRemoteData() {
        TokenManager.save(access: "access-token", refresh: "refresh-token")
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy, startStartupTasks: false)

        state.displayName = "이전계정"
        state.hasCompletedOnboarding = true
        state.points = 42
        state.streak = 3
        state.freezeInventory = 2
        state.owned = ["hat-basic"]
        state.persistSnapshot()

        state.logout()

        XCTAssertFalse(state.isLoggedIn)
        XCTAssertNil(TokenManager.accessToken)
        XCTAssertNil(state.displayName)
        XCTAssertFalse(state.hasCompletedOnboarding)
        XCTAssertEqual(state.points, 0)
        XCTAssertEqual(state.streak, 0)
        XCTAssertEqual(state.freezeInventory, 0)
        XCTAssertTrue(state.owned.isEmpty)
        XCTAssertEqual(spy.deleteUserDataCallCount, 0, "로그아웃은 원격 데이터를 삭제하면 안 된다")
    }

    func testLogoutTracksLogoutBeforeClearingSession() {
        let analytics = UserFlowSpyAnalytics()
        let state = AppState(remoteStore: SpyRemoteStore(), analytics: analytics, startStartupTasks: false)

        state.logout()

        let event = analytics.trackedEvents.first
        XCTAssertEqual(event?.name, "logout")
        XCTAssertEqual(event?.properties["source"] as? String, "settings")
    }

    func testLogoutFromServerRevokesRefreshThenClearsLocalSession() async {
        TokenManager.save(access: "access-token", refresh: "refresh-token")
        let remote = SpyRemoteStore()
        let auth = SpyAuthSessionManager()
        let state = AppState(remoteStore: remote, authSessionManager: auth, startStartupTasks: false)
        state.displayName = "이전계정"
        state.hasCompletedOnboarding = true
        state.points = 42

        await state.logoutFromServer()

        XCTAssertEqual(auth.logoutCallCount, 1)
        XCTAssertFalse(state.isLoggedIn)
        XCTAssertNil(TokenManager.accessToken)
        XCTAssertNil(state.displayName)
        XCTAssertFalse(state.hasCompletedOnboarding)
        XCTAssertEqual(state.points, 0)
        XCTAssertEqual(remote.deleteUserDataCallCount, 0)
    }

    func testAuthExpiredDuringHomeRefreshReturnsToLoginGate() async {
        TokenManager.save(access: "access-token", refresh: "refresh-token")
        let remote = SpyRemoteStore()
        remote.fetchHomeError = RemoteStoreError.authExpired
        let state = AppState(remoteStore: remote, startStartupTasks: false)
        state.displayName = "이전계정"
        state.hasCompletedOnboarding = true

        await state.refreshFromServerHome()

        XCTAssertFalse(state.isLoggedIn)
        XCTAssertNil(TokenManager.accessToken)
        XCTAssertNil(state.displayName)
        XCTAssertFalse(state.hasCompletedOnboarding)
    }

    func testAuthExpiredDuringHomeRefreshDoesNotTrackLogout() async {
        TokenManager.save(access: "access-token", refresh: "refresh-token")
        let remote = SpyRemoteStore()
        remote.fetchHomeError = RemoteStoreError.authExpired
        let analytics = UserFlowSpyAnalytics()
        let state = AppState(remoteStore: remote, analytics: analytics, startStartupTasks: false)

        await state.refreshFromServerHome()

        XCTAssertFalse(analytics.trackedEvents.contains { $0.name == "logout" })
    }

    func testPendingInviteCodeRemainsWhenAcceptFailsAfterLogin() async {
        let remote = SpyRemoteStore()
        remote.acceptFriendInviteError = RemoteStoreError.offline
        let state = AppState(remoteStore: remote, startStartupTasks: false)
        state.isLoggedIn = false
        state.receiveInviteCode("FRIEND-123")

        state.completeLogin(userId: "server-user-123", onboardingCompleted: true, method: "kakao")

        await waitFor(!remote.acceptedInviteCodes.isEmpty)
        XCTAssertEqual(remote.acceptedInviteCodes, ["FRIEND-123"])
        XCTAssertEqual(state.friends.pendingInviteCode, "FRIEND-123")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: pendingInviteKey),
            "FRIEND-123"
        )
    }

    func testInviteAcceptRefreshesHomePointsImmediately() async {
        let remote = SpyRemoteStore()
        remote.home = HomeStateDTO(
            deviceId: DeviceIdentity.shared,
            displayName: nil,
            points: 100,
            streak: 0,
            freezeInventory: 0,
            todayRealChewCount: 0,
            dailyGoal: 400,
            todayProgress: 0,
            todayCompleted: false
        )
        let state = AppState(remoteStore: remote)
        state.isLoggedIn = true
        state.points = 0

        state.receiveInviteCode("FRIEND-123")

        await waitFor(state.points == 100)
        XCTAssertEqual(remote.acceptedInviteCodes, ["FRIEND-123"])
        XCTAssertEqual(state.points, 100)
        XCTAssertEqual(state.friendsTabRequestID, 1)
    }
}
