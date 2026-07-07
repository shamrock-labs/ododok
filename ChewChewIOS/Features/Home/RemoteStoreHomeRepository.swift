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
        let deviceId = DeviceIdentity.shared
        return try await remoteStore.earnAttendance(
            deviceId: deviceId,
            idempotencyKey: AttendanceKey.make(deviceId: deviceId, now: now)
        )
    }

    func fetchRewardHistory() async throws -> [RewardHistoryDTO] {
        try await remoteStore.fetchRewardHistory()
    }
}
