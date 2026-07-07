import XCTest
@testable import ChewChewIOS

@MainActor
final class FriendsStoreTests: XCTestCase {
    func testLoadSuccessStoresInviteCodeAndRankings() async {
        let repository = FakeFriendRepository(
            invite: FriendInviteCodeDTO(code: "FRIEND-123", deepLink: "chewchew://invite?code=FRIEND-123"),
            rankings: [ranking(name: "다람", points: 120, me: true)]
        )
        let store = makeStore(repository: repository)

        await store.load()

        XCTAssertEqual(store.inviteCode, "FRIEND-123")
        XCTAssertEqual(store.inviteDeepLink, "chewchew://invite?code=FRIEND-123")
        XCTAssertEqual(store.rankings.count, 1)
        XCTAssertEqual(store.loadState, .loaded)
    }

    func testLoadEmptyRankingStillSucceeds() async {
        let repository = FakeFriendRepository(rankings: [])
        let store = makeStore(repository: repository)

        await store.load()

        XCTAssertTrue(store.rankings.isEmpty)
        XCTAssertEqual(store.loadState, .loaded)
    }

    func testLoadFailureSetsFailedAfterRetries() async {
        let repository = FakeFriendRepository(fetchInviteError: RemoteStoreError.offline)
        let store = makeStore(repository: repository)

        await store.load()

        XCTAssertNil(store.inviteCode)
        XCTAssertEqual(store.loadState, .failed)
        XCTAssertEqual(repository.fetchInviteCallCount, 3)
    }

    func testAuthExpiredDuringLoadCallsAuthExpiredHandler() async {
        let repository = FakeFriendRepository(fetchInviteError: RemoteStoreError.authExpired)
        var didExpire = false
        let store = makeStore(repository: repository, onAuthExpired: { didExpire = true })

        await store.load()

        XCTAssertTrue(didExpire)
        XCTAssertEqual(repository.fetchInviteCallCount, 1)
        XCTAssertEqual(store.loadState, .failed)
    }

    func testReceiveInviteWhenLoggedOutStoresPendingCodeAndShowsToast() {
        let repository = FakeFriendRepository()
        var persistedCode: String?
        var toasts: [String] = []
        var inviteReceivedLoggedIn: Bool?
        let store = makeStore(
            repository: repository,
            isLoggedIn: false,
            onToast: { toasts.append($0) },
            onInviteReceived: { inviteReceivedLoggedIn = $0 },
            onPendingInviteCodeChanged: { persistedCode = $0 }
        )

        store.receiveInviteCode(" FRIEND-123 ")

        XCTAssertEqual(store.pendingInviteCode, "FRIEND-123")
        XCTAssertEqual(persistedCode, "FRIEND-123")
        XCTAssertEqual(toasts, ["로그인하면 친구가 돼요"])
        XCTAssertEqual(inviteReceivedLoggedIn, false)
        XCTAssertTrue(repository.acceptedCodes.isEmpty)
    }

    func testConsumePendingInviteSuccessClearsPendingOnlyAfterAcceptSucceeds() async {
        let repository = FakeFriendRepository()
        var persistedCodes: [String?] = []
        let store = makeStore(
            repository: repository,
            initialPendingInviteCode: "FRIEND-123",
            onPendingInviteCodeChanged: { persistedCodes.append($0) }
        )

        await store.consumePendingInviteIfNeeded()

        XCTAssertEqual(repository.acceptedCodes, ["FRIEND-123"])
        XCTAssertNil(store.pendingInviteCode)
        XCTAssertEqual(persistedCodes, [nil])
    }

    func testConsumePendingInviteFailureKeepsPendingCode() async {
        let repository = FakeFriendRepository(acceptError: RemoteStoreError.offline)
        var persistedCodes: [String?] = []
        let store = makeStore(
            repository: repository,
            initialPendingInviteCode: "FRIEND-123",
            onPendingInviteCodeChanged: { persistedCodes.append($0) }
        )

        await store.consumePendingInviteIfNeeded()

        XCTAssertEqual(repository.acceptedCodes, ["FRIEND-123"])
        XCTAssertEqual(store.pendingInviteCode, "FRIEND-123")
        XCTAssertTrue(persistedCodes.isEmpty)
    }

    func testAcceptInviteSuccessRefreshesAndShowsSuccessToast() async {
        let repository = FakeFriendRepository(rankings: [ranking(name: "친구", points: 80)])
        var toasts: [String] = []
        var acceptedCallbackCount = 0
        let store = makeStore(
            repository: repository,
            onToast: { toasts.append($0) },
            onInviteAccepted: { acceptedCallbackCount += 1 }
        )

        let accepted = await store.acceptInvite(code: "FRIEND-123")

        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.acceptedCodes, ["FRIEND-123"])
        XCTAssertEqual(store.rankings.count, 1)
        XCTAssertEqual(toasts, ["친구가 됐어요! 도토리 100개 받았어요"])
        XCTAssertEqual(acceptedCallbackCount, 1)
    }

    func testAcceptInviteAlreadyFriendShowsExistingFriendToast() async {
        let repository = FakeFriendRepository(acceptResult: FriendAcceptResultDTO(accepted: true, bonusGranted: false))
        var toasts: [String] = []
        var acceptedCallbackCount = 0
        let store = makeStore(
            repository: repository,
            onToast: { toasts.append($0) },
            onInviteAccepted: { acceptedCallbackCount += 1 }
        )

        let accepted = await store.acceptInvite(code: "FRIEND-123")

        XCTAssertTrue(accepted)
        XCTAssertEqual(toasts, ["이미 친구예요"])
        XCTAssertEqual(acceptedCallbackCount, 1)
    }

    func testAcceptInviteFailureKeepsStateAndShowsMappedError() async {
        let repository = FakeFriendRepository(
            rankings: [ranking(name: "기존친구", points: 10)],
            acceptError: RemoteStoreError.server(status: 400, code: 4012, message: "self invite")
        )
        var toasts: [String] = []
        var acceptedCallbackCount = 0
        let store = makeStore(
            repository: repository,
            onToast: { toasts.append($0) },
            onInviteAccepted: { acceptedCallbackCount += 1 }
        )
        await store.load()

        let accepted = await store.acceptInvite(code: "SELF")

        XCTAssertFalse(accepted)
        XCTAssertEqual(store.rankings.map(\.name), ["기존친구"])
        XCTAssertEqual(toasts, ["본인 초대 코드는 수락할 수 없어요"])
        XCTAssertEqual(acceptedCallbackCount, 0)
    }

    func testDisplayNameUsesCurrentUserNameForMeRow() {
        let store = makeStore(currentDisplayName: "보형")

        XCTAssertEqual(store.displayName(for: Self.ranking(name: nil, points: 10, me: true)), "보형")
        XCTAssertEqual(store.displayName(for: Self.ranking(name: nil, points: 10, me: false)), "친구")
    }

    private func makeStore(
        repository: FakeFriendRepository = FakeFriendRepository(),
        isLoggedIn: Bool = true,
        currentDisplayName: String? = nil,
        initialPendingInviteCode: String? = nil,
        onToast: @escaping (String) -> Void = { _ in },
        onAuthExpired: @escaping () -> Void = {},
        onInviteReceived: @escaping (Bool) -> Void = { _ in },
        onInviteAccepted: @escaping () -> Void = {},
        onPendingInviteCodeChanged: @escaping (String?) -> Void = { _ in }
    ) -> FriendsStore {
        FriendsStore(
            repository: repository,
            isLoggedIn: { isLoggedIn },
            currentDisplayName: { currentDisplayName },
            initialPendingInviteCode: initialPendingInviteCode,
            retryDelay: .zero,
            onToast: onToast,
            onAuthExpired: onAuthExpired,
            onInviteReceived: onInviteReceived,
            onInviteAccepted: onInviteAccepted,
            onPendingInviteCodeChanged: onPendingInviteCodeChanged
        )
    }

    private static func ranking(name: String?, points: Int, me: Bool = false) -> FriendRankingDTO {
        FriendRankingDTO(userId: UUID(), name: name, points: points, me: me)
    }

    private func ranking(name: String?, points: Int, me: Bool = false) -> FriendRankingDTO {
        Self.ranking(name: name, points: points, me: me)
    }
}

private final class FakeFriendRepository: FriendRepository {
    private let invite: FriendInviteCodeDTO
    private let rankings: [FriendRankingDTO]
    private let acceptResult: FriendAcceptResultDTO
    private let fetchInviteError: Error?
    private let fetchRankingError: Error?
    private let acceptError: Error?

    private(set) var fetchInviteCallCount = 0
    private(set) var fetchRankingCallCount = 0
    private(set) var acceptedCodes: [String] = []

    init(
        invite: FriendInviteCodeDTO = FriendInviteCodeDTO(code: "FRIEND-123", deepLink: nil),
        rankings: [FriendRankingDTO] = [],
        acceptResult: FriendAcceptResultDTO = FriendAcceptResultDTO(accepted: true, bonusGranted: true),
        fetchInviteError: Error? = nil,
        fetchRankingError: Error? = nil,
        acceptError: Error? = nil
    ) {
        self.invite = invite
        self.rankings = rankings
        self.acceptResult = acceptResult
        self.fetchInviteError = fetchInviteError
        self.fetchRankingError = fetchRankingError
        self.acceptError = acceptError
    }

    func fetchInviteCode() async throws -> FriendInviteCodeDTO {
        fetchInviteCallCount += 1
        if let fetchInviteError { throw fetchInviteError }
        return invite
    }

    func fetchRanking() async throws -> [FriendRankingDTO] {
        fetchRankingCallCount += 1
        if let fetchRankingError { throw fetchRankingError }
        return rankings
    }

    func acceptInvite(code: String) async throws -> FriendAcceptResultDTO {
        acceptedCodes.append(code)
        if let acceptError { throw acceptError }
        return acceptResult
    }
}
