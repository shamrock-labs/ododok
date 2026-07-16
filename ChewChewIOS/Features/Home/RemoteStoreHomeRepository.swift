import Foundation

struct RemoteStoreHomeRepository: HomeRepository {
    private let remoteStore: RemoteStore

    init(remoteStore: RemoteStore) {
        self.remoteStore = remoteStore
    }

    func fetchHome() async throws -> HomeStateDTO {
        try await remoteStore.fetchHome(deviceId: DeviceIdentity.shared)
    }

    func earnAttendance(now: Date) async throws -> AttendanceResultDTO {
        try await earnAttendance(now: now, decision: nil, expectedMissedDays: nil)
    }

    func fetchAttendanceStatus() async throws -> AttendanceStatusDTO {
        try await remoteStore.fetchAttendanceStatus()
    }

    func earnAttendance(
        now: Date,
        decision: FreezeDecisionDTO?,
        expectedMissedDays: Int?
    ) async throws -> AttendanceResultDTO {
        let deviceId = DeviceIdentity.shared
        return try await remoteStore.earnAttendance(
            deviceId: deviceId,
            idempotencyKey: AttendanceKey.make(deviceId: deviceId, now: now),
            decision: decision,
            expectedMissedDays: expectedMissedDays
        )
    }

    func fetchRewardHistory() async throws -> [RewardHistoryDTO] {
        try await remoteStore.fetchRewardHistory()
    }

    func fetchStreakDetail(month: String?) async throws -> StreakDetailDTO {
        try await remoteStore.fetchStreakDetail(month: month)
    }
}
