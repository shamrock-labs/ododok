import Foundation
import Observation

@Observable
@MainActor
final class FriendsStore {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var inviteCode: String?
    private(set) var inviteDeepLink: String?
    private(set) var rankings: [FriendRankingDTO] = []
    private(set) var loadState: LoadState = .loading
    private(set) var pendingInviteCode: String?

    private let repository: FriendRepository
    private let isLoggedIn: () -> Bool
    private let currentDisplayName: () -> String?
    private let onToast: (String) -> Void
    private let onAuthExpired: () -> Void
    private let onInviteReceived: (Bool) -> Void
    private let onInviteAccepted: () -> Void
    private let onPendingInviteCodeChanged: (String?) -> Void
    private let retryDelay: Duration

    init(
        repository: FriendRepository,
        isLoggedIn: @escaping () -> Bool,
        currentDisplayName: @escaping () -> String?,
        initialPendingInviteCode: String? = nil,
        retryDelay: Duration = .seconds(1),
        onToast: @escaping (String) -> Void = { _ in },
        onAuthExpired: @escaping () -> Void = {},
        onInviteReceived: @escaping (Bool) -> Void = { _ in },
        onInviteAccepted: @escaping () -> Void = {},
        onPendingInviteCodeChanged: @escaping (String?) -> Void = { _ in }
    ) {
        self.repository = repository
        self.isLoggedIn = isLoggedIn
        self.currentDisplayName = currentDisplayName
        self.pendingInviteCode = initialPendingInviteCode
        self.retryDelay = retryDelay
        self.onToast = onToast
        self.onAuthExpired = onAuthExpired
        self.onInviteReceived = onInviteReceived
        self.onInviteAccepted = onInviteAccepted
        self.onPendingInviteCodeChanged = onPendingInviteCodeChanged
    }

    func load() async {
        await refresh()
    }

    func refresh() async {
        if inviteCode == nil {
            loadState = .loading
        }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let invite = try await repository.fetchInviteCode()
                inviteCode = invite.code
                inviteDeepLink = invite.deepLink
                rankings = try await repository.fetchRanking()
                loadState = .loaded
                return
            } catch {
                if case RemoteStoreError.authExpired = error {
                    onAuthExpired()
                    loadState = .failed
                    return
                }
                if attempt < maxAttempts {
                    try? await Task.sleep(for: retryDelay)
                } else {
                    loadState = .failed
                }
            }
        }
    }

    @discardableResult
    func acceptInvite(code: String) async -> Bool {
        do {
            let result = try await repository.acceptInvite(code: code)
            await refresh()
            onToast(result.bonusGranted ? "친구가 됐어요! 도토리 100개 받았어요" : "이미 친구예요")
            onInviteAccepted()
            return true
        } catch {
            if case RemoteStoreError.authExpired = error {
                onAuthExpired()
            }
            onToast(Self.acceptErrorMessage(error))
            return false
        }
    }

    func receiveInviteCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let loggedIn = isLoggedIn()
        onInviteReceived(loggedIn)
        if loggedIn {
            Task { await acceptInvite(code: trimmed) }
        } else {
            setPendingInviteCode(trimmed)
            onToast("로그인하면 친구가 돼요")
        }
    }

    func consumePendingInviteIfNeeded() async {
        guard let code = pendingInviteCode else { return }
        if await acceptInvite(code: code) {
            setPendingInviteCode(nil)
        }
    }

    func setPendingInviteCode(_ code: String?) {
        pendingInviteCode = code
        onPendingInviteCodeChanged(code)
    }

    func displayName(for row: FriendRankingDTO) -> String {
        if row.me {
            return currentDisplayName() ?? row.name ?? "나"
        }
        return row.name ?? "친구"
    }

    private static func acceptErrorMessage(_ error: Error) -> String {
        if case let RemoteStoreError.server(_, code, _) = error {
            switch code {
            case 4012: return "본인 초대 코드는 수락할 수 없어요"
            case 4011: return "유효하지 않은 초대 코드예요"
            default: break
            }
        }
        if case RemoteStoreError.offline = error { return "네트워크 연결을 확인해 주세요" }
        if case RemoteStoreError.authExpired = error { return "다시 로그인한 뒤 시도해 주세요" }
        return "친구 맺기에 실패했어요"
    }
}
