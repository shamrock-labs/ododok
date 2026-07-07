import Foundation

struct RemoteStoreHomeRepository: HomeRepository {
    private let remoteStore: RemoteStore

    init(remoteStore: RemoteStore) {
        self.remoteStore = remoteStore
    }

    func fetchHome() async throws -> HomeStateDTO {
        try await remoteStore.fetchHome(deviceId: DeviceIdentity.shared)
    }
}
