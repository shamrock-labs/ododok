import Foundation

struct RemoteStoreFriendRepository: FriendRepository {
    private let remoteStore: RemoteStore

    init(remoteStore: RemoteStore) {
        self.remoteStore = remoteStore
    }

    func fetchInviteCode() async throws -> FriendInviteCodeDTO {
        try await remoteStore.fetchFriendInviteCode()
    }

    func fetchRanking() async throws -> [FriendRankingDTO] {
        try await remoteStore.fetchFriendRanking()
    }

    func acceptInvite(code: String) async throws -> FriendAcceptResultDTO {
        try await remoteStore.acceptFriendInvite(code: code)
    }
}
