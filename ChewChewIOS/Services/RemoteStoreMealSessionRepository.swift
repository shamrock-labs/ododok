import Foundation

struct RemoteStoreMealSessionRepository: MealSessionRepository {
    private let remoteStore: RemoteStore

    init(remoteStore: RemoteStore) {
        self.remoteStore = remoteStore
    }

    func fetchSessions(since: Date, until: Date?) async throws -> [ChewingSessionDTO] {
        try await remoteStore.fetchChewingSessions(
            deviceId: DeviceIdentity.shared,
            since: since,
            until: until
        )
    }

    func deleteSession(id: UUID) async throws {
        try await remoteStore.deleteChewingSession(id: id, deviceId: DeviceIdentity.shared)
    }

    func deleteAllSessions() async throws {
        try await remoteStore.deleteAllChewingSessions(deviceId: DeviceIdentity.shared)
    }
}
