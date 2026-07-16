import Foundation

struct RemoteStoreFriendRepository: FriendRepository {
    private let remoteStore: RemoteStore
    private let debugProfileIsActive: () -> Bool

    init(remoteStore: RemoteStore, debugProfileIsActive: @escaping () -> Bool = { false }) {
        self.remoteStore = remoteStore
        self.debugProfileIsActive = debugProfileIsActive
    }

    func fetchInviteCode() async throws -> FriendInviteCodeDTO {
        #if DEBUG
        if debugProfileIsActive() { return DebugFriendFixture.invite }
        #endif
        return try await remoteStore.fetchFriendInviteCode()
    }

    func fetchRanking() async throws -> [FriendRankingDTO] {
        #if DEBUG
        if debugProfileIsActive() { return DebugFriendFixture.rankings }
        #endif
        return try await remoteStore.fetchFriendRanking()
    }

    func acceptInvite(code: String) async throws -> FriendAcceptResultDTO {
        try await remoteStore.acceptFriendInvite(code: code)
    }
}

#if DEBUG
enum DebugFriendFixture {
    static let invite = FriendInviteCodeDTO(
        code: "DARAMI2026",
        deepLink: "chewchew://invite?code=DARAMI2026"
    )

    static let rankings: [FriendRankingDTO] = [
        .init(userId: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)), name: "다람이", points: 486, me: true),
        .init(userId: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)), name: "보리", points: 412, me: false),
        .init(userId: UUID(uuid: (3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)), name: "모카", points: 328, me: false),
    ]
}
#endif
