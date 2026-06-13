import XCTest
@testable import ChewChewIOS

/// 서버 홈 응답을 고정값으로 돌려주는 테스트용 stub. `fetchHome`만 의미 있고 나머지는 중립.
/// `fetchHomeShouldThrow`로 "응답이 안 오는 경우"(offline)를 재현한다.
private final class StubHomeStore: RemoteStore {
    var home: HomeStateDTO
    var fetchHomeShouldThrow: Bool

    init(home: HomeStateDTO, fetchHomeShouldThrow: Bool = false) {
        self.home = home
        self.fetchHomeShouldThrow = fetchHomeShouldThrow
    }

    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile(deviceId: String) async throws -> ProfileDTO? { nil }
    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO? { nil }
    func deleteUserData(deviceId: String) async throws {}
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        CreateSessionResultDTO(
            chewingSession: session,
            chewingSessionAccepted: true,
            rewardEligible: false,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 0, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 0, event: "NONE", freezeInventory: 0),
            today: SessionTodayDTO(completed: false),
            userStats: home
        )
    }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO {
        if fetchHomeShouldThrow { throw RemoteStoreError.offline }
        return home
    }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        AttendanceResultDTO(grantedPoints: 0, capped: false, idempotentReplay: false, userStats: home)
    }
    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String { "" }
}

@MainActor
final class ServerHomeSyncTests: XCTestCase {
    private func makeHome(
        points: Int, streak: Int, freeze: Int, chew: Int, goal: Int, progress: Double
    ) -> HomeStateDTO {
        HomeStateDTO(
            deviceId: "dev",
            displayName: nil,
            points: points,
            streak: streak,
            freezeInventory: freeze,
            todayRealChewCount: chew,
            dailyGoal: goal,
            todayProgress: progress,
            todayCompleted: chew > 0
        )
    }

    /// 서버 홈 값이 그대로 in-memory 상태 + derived 프로퍼티로 흘러야 한다(정본 = 서버).
    func testRefreshFromServerHome_appliesServerValues() async {
        let home = makeHome(points: 123, streak: 5, freeze: 2, chew: 200, goal: 400, progress: 0.5)
        let state = AppState(remoteStore: StubHomeStore(home: home))

        await state.refreshFromServerHome()

        XCTAssertEqual(state.points, 123)
        XCTAssertEqual(state.currentStreak, 5)
        XCTAssertEqual(state.freezeInventory, 2)
        XCTAssertEqual(state.todayRealChewCount, 200)
        XCTAssertEqual(state.todayProgress, 0.5, accuracy: 0.0001)
    }

    /// 응답이 안 오는 경우(offline) — 마지막 성공 상태를 유지해야 한다(화면이 깨지지 않음).
    func testRefreshFromServerHome_failureKeepsLastGoodState() async {
        let store = StubHomeStore(home: makeHome(points: 50, streak: 3, freeze: 1, chew: 100, goal: 400, progress: 0.25))
        let state = AppState(remoteStore: store)
        await state.refreshFromServerHome()
        XCTAssertEqual(state.points, 50)

        store.fetchHomeShouldThrow = true
        await state.refreshFromServerHome()

        XCTAssertEqual(state.points, 50, "서버 실패 시 마지막 성공 상태를 유지해야 한다")
        XCTAssertEqual(state.currentStreak, 3)
    }
}
