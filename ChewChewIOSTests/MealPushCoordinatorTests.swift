import XCTest
@testable import ChewChewIOS

/// MealPushCoordinator의 서버 전환·로그아웃·미로그인 경로 테스트(ODO-56).
/// RemoteStore는 스파이로, 로그인 여부는 클로저 주입으로 대체해 키체인/알림권한 없이 결정적으로 검증한다.
/// (서명 없는 시뮬레이터 테스트는 Keychain이 막혀 TokenManager가 동작하지 않으므로 주입이 필수.)
@MainActor
final class MealPushCoordinatorTests: XCTestCase {

    /// push 호출만 기록하고 나머지 RemoteStore 메서드는 NoopRemoteStore에 위임하는 스파이.
    final class SpyRemoteStore: RemoteStore {
        private let base = NoopRemoteStore()
        var registerCalls: [(token: String, environment: String)] = []
        var upsertCount = 0
        var deactivateCalls: [String] = []
        var registerError: Error?

        func registerPushToken(_ token: String, environment: String) async throws {
            registerCalls.append((token, environment))
            if let registerError { throw registerError }
        }
        func upsertMealNotifications(_ settings: MealReminderSettings, timeZone: String) async throws {
            upsertCount += 1
        }
        func deactivatePushToken(_ token: String) async throws {
            deactivateCalls.append(token)
        }
        func fetchMealNotifications() async throws -> MealReminderSettings? { nil }

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

    /// [0xab,0xcd,0x01,0x02] → "abcd0102"
    private let fakeToken = Data([0xAB, 0xCD, 0x01, 0x02])

    func testDidRegister_whenLoggedIn_registersTokenAndSyncsSettings() async {
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true })

        await coordinator.didRegister(deviceToken: fakeToken)

        XCTAssertEqual(spy.registerCalls.map(\.token), ["abcd0102"])
        XCTAssertEqual(spy.registerCalls.first?.environment, "sandbox")   // DEBUG 빌드
        XCTAssertGreaterThanOrEqual(spy.upsertCount, 1)
    }

    func testDidRegister_whenLoggedOut_doesNotRegister() async {
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { false })

        await coordinator.didRegister(deviceToken: fakeToken)

        XCTAssertTrue(spy.registerCalls.isEmpty)
        XCTAssertEqual(spy.upsertCount, 0)
    }

    func testHandleLogout_deactivatesRegisteredToken() async {
        let spy = SpyRemoteStore()
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true })
        await coordinator.didRegister(deviceToken: fakeToken)   // 토큰 등록 선행

        await coordinator.handleLogout()

        XCTAssertEqual(spy.deactivateCalls, ["abcd0102"])
    }

    func testDidRegister_registerFailure_doesNotRetainToken() async {
        let spy = SpyRemoteStore()
        spy.registerError = RemoteStoreError.offline
        let coordinator = MealPushCoordinator(remoteStore: spy, isLoggedIn: { true })

        await coordinator.didRegister(deviceToken: fakeToken)
        // 등록 실패 → 토큰 미보유 → 로그아웃해도 deactivate 호출 없음.
        await coordinator.handleLogout()

        XCTAssertTrue(spy.deactivateCalls.isEmpty)
    }
}
