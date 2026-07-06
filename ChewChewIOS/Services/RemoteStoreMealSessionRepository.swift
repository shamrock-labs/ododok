import Foundation

struct RemoteStoreMealSessionRepository: MealSessionRepository {
    private let remoteStore: RemoteStore

    init(remoteStore: RemoteStore) {
        self.remoteStore = remoteStore
    }

    func fetchSessions(since: Date, until: Date?) async throws -> [MealSessionRecord] {
        let sessions = try await remoteStore.fetchChewingSessions(
            deviceId: DeviceIdentity.shared,
            since: since,
            until: until
        )
        return sessions.compactMap(MealSessionRecordMapper.map)
    }

    func fetchOldestSessionStartedAt() async throws -> Date? {
        let sessions = try await remoteStore.fetchChewingSessions(
            deviceId: DeviceIdentity.shared,
            since: .distantPast,
            until: nil
        )
        return sessions
            .lazy
            .filter(MealSessionRecordMapper.isReportable)
            .map(\.startedAt)
            .min()
    }

    func deleteSession(id: UUID) async throws {
        try await remoteStore.deleteChewingSession(id: id, deviceId: DeviceIdentity.shared)
    }

    func deleteAllSessions() async throws {
        try await remoteStore.deleteAllChewingSessions(deviceId: DeviceIdentity.shared)
    }
}
