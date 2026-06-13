import XCTest
@testable import ChewChewIOS

/// `deleteUserData`가 실제로 한 번 호출되는지 추적하는 테스트용 Spy.
final class SpyRemoteStore: RemoteStore {
    private(set) var deleteUserDataCallCount = 0

    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile(deviceId: String) async throws -> ProfileDTO? { nil }
    func fetchUserStats(deviceId: String) async throws -> UserStatsDTO? { nil }
    func deleteUserData(deviceId: String) async throws { deleteUserDataCallCount += 1 }
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        CreateSessionResultDTO(
            chewingSession: session,
            chewingSessionAccepted: true,
            rewardEligible: false,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 0, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 0, event: "NONE", freezeInventory: 0),
            today: SessionTodayDTO(completed: false),
            userStats: .empty(deviceId: session.deviceId)
        )
    }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO { .empty(deviceId: deviceId) }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        AttendanceResultDTO(grantedPoints: 0, capped: false, idempotentReplay: false, userStats: .empty(deviceId: deviceId))
    }
    func fetchChewingSessions(deviceId: String, since: Date, until: Date?) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String { "" }
}

@MainActor
final class EraseAllUserDataTests: XCTestCase {
    func testEraseAllUserData_callsDeleteUserDataOnce() async {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy)

        // 초기 상태에서 직렬화 체인이 drain되도록 짧게 yield
        await Task.yield()

        await state.eraseAllUserData()

        // remoteSyncChain이 비동기로 실행되므로 Task 완료를 기다림
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(spy.deleteUserDataCallCount, 1, "eraseAllUserData 호출 시 deleteUserData가 정확히 1회 호출되어야 한다")
    }

    func testEraseAllUserData_resetsPointsToZero() async {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy)
        state.points = 500

        await state.eraseAllUserData()

        XCTAssertEqual(state.points, 0, "삭제 후 points는 0이어야 한다")
    }

    func testEraseAllUserData_resetsTodaySessionsToEmpty() async {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy)
        state.todaySessions = [
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

        await state.eraseAllUserData()

        XCTAssertTrue(state.todaySessions.isEmpty, "삭제 후 todaySessions는 빈 배열이어야 한다")
    }

    func testEraseAllUserData_resetsStreakToZero() async {
        let spy = SpyRemoteStore()
        let state = AppState(remoteStore: spy)
        state.streak = 7

        await state.eraseAllUserData()

        XCTAssertEqual(state.streak, 0, "삭제 후 streak은 0이어야 한다")
    }
}
