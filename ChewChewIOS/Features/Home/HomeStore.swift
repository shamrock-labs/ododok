import Foundation
import Observation

@Observable
@MainActor
final class HomeStore {
    enum RewardHistoryLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var serverHome: HomeStateDTO?
    private(set) var points: Int
    private(set) var streak: Int
    private(set) var freezeInventory: Int
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var pendingRewardGrant: RewardGrant?
    private(set) var rewardHistory: [RewardHistoryDTO] = []
    private(set) var rewardHistoryLoadState: RewardHistoryLoadState = .idle

    private let repository: HomeRepository
    private let serverReportTodayChewCount: @MainActor () -> Int
    private let onHomeApplied: @MainActor (HomeStateDTO) -> Void
    private let onRemoteError: @MainActor (Error) -> Void
    private let onRewardEarned: @MainActor (Int, String) -> Void
    private let onStreakEvent: @MainActor (String, Int) -> Void
    private var loadGeneration: Int = 0
    private var rewardHistoryGeneration: Int = 0

    init(
        repository: HomeRepository,
        initialHome: HomeStateDTO? = nil,
        initialPoints: Int = 0,
        initialStreak: Int = 0,
        initialFreezeInventory: Int = 0,
        serverReportTodayChewCount: @escaping @MainActor () -> Int = { 0 },
        onHomeApplied: @escaping @MainActor (HomeStateDTO) -> Void = { _ in },
        onRemoteError: @escaping @MainActor (Error) -> Void = { _ in },
        onRewardEarned: @escaping @MainActor (Int, String) -> Void = { _, _ in },
        onStreakEvent: @escaping @MainActor (String, Int) -> Void = { _, _ in }
    ) {
        self.repository = repository
        self.serverHome = initialHome
        self.points = initialHome?.points ?? initialPoints
        self.streak = initialHome?.streak ?? initialStreak
        self.freezeInventory = initialHome?.freezeInventory ?? initialFreezeInventory
        self.serverReportTodayChewCount = serverReportTodayChewCount
        self.onHomeApplied = onHomeApplied
        self.onRemoteError = onRemoteError
        self.onRewardEarned = onRewardEarned
        self.onStreakEvent = onStreakEvent
    }

    var currentStreak: Int {
        serverHome?.streak ?? streak
    }

    var todayRealChewCount: Int {
        if let serverHome, serverHome.dailyGoal > 0 { return serverHome.todayRealChewCount }
        return serverReportTodayChewCount()
    }

    var todayProgress: Double {
        if let serverHome, serverHome.dailyGoal > 0 {
            return Self.clampedProgress(serverHome.todayProgress)
        }
        return Self.clampedProgress(Double(todayRealChewCount) / Double(Constants.dailyGoal))
    }

    var status: MoodStatus {
        MoodStatus.from(count: todayRealChewCount)
    }

    func refresh(shouldApply: (@MainActor () -> Bool)? = nil) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        do {
            let home = try await repository.fetchHome()
            guard generation == loadGeneration else { return }
            guard shouldApply?() ?? true else {
                isLoading = false
                return
            }
            applyAndNotify(home)
            errorMessage = nil
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            onRemoteError(error)
            errorMessage = "홈 정보를 불러오지 못했어요."
            isLoading = false
        }
    }

    func applyExternal(_ home: HomeStateDTO) {
        loadGeneration += 1
        apply(home)
        errorMessage = nil
        isLoading = false
    }

    func syncLocalCache(points: Int, streak: Int, freezeInventory: Int) {
        self.points = points
        self.streak = streak
        self.freezeInventory = freezeInventory
        if var serverHome {
            serverHome.points = points
            serverHome.streak = streak
            serverHome.freezeInventory = freezeInventory
            self.serverHome = serverHome
        }
    }

    func applySessionReward(from result: CreateSessionResultDTO) {
        if let streakGrant = rewardGrant(for: result.streak) {
            pendingRewardGrant = streakGrant
            onStreakEvent(streakGrant.kind.analyticsType, streakGrant.amount)
        } else if result.reward.grantedPoints > 0 && !result.reward.idempotentReplay {
            // SessionResultSheet가 먼저 떠 있는 상태 — ContentView overlay는
            // sheet 닫힌 후(`lastCompletedSession == nil`)에만 그려져, 다이얼로그가
            // sheet에 가려지지 않고 순차로 등장한다.
            pendingRewardGrant = RewardGrant(amount: result.reward.grantedPoints, kind: .sessionComplete)
        }

        // 적립 도토리 트래킹은 다이얼로그 우선순위와 분리한다 — 스트릭 마일스톤과 세션 적립이
        // 동시에 발생해도 reward_earned가 누락되지 않도록(과소집계 방지). streak_event와는 별도 이벤트.
        if result.reward.grantedPoints > 0 && !result.reward.idempotentReplay {
            onRewardEarned(result.reward.grantedPoints, "session_complete")
        }
    }

    func grantDailyAttendanceIfNeeded(now: Date = Date()) async {
        loadGeneration += 1
        do {
            let result = try await repository.earnAttendance(now: now)
            loadGeneration += 1
            applyAndNotify(result.userStats)
            if result.grantedPoints > 0 && !result.idempotentReplay {
                pendingRewardGrant = RewardGrant(amount: result.grantedPoints, kind: .attendance)
                onRewardEarned(result.grantedPoints, "attendance")
            }
        } catch {
            onRemoteError(error)
        }
    }

    func fetchRewardHistory() async {
        rewardHistoryGeneration += 1
        let generation = rewardHistoryGeneration
        rewardHistoryLoadState = .loading
        do {
            let history = try await repository.fetchRewardHistory()
            guard generation == rewardHistoryGeneration else { return }
            rewardHistory = history
            rewardHistoryLoadState = .loaded
        } catch {
            guard generation == rewardHistoryGeneration else { return }
            onRemoteError(error)
            rewardHistoryLoadState = .failed
        }
    }

    func dismissPendingRewardGrant() {
        pendingRewardGrant = nil
    }

    func reset() {
        loadGeneration += 1
        rewardHistoryGeneration += 1
        serverHome = nil
        points = 0
        streak = 0
        freezeInventory = 0
        errorMessage = nil
        isLoading = false
        pendingRewardGrant = nil
        rewardHistory = []
        rewardHistoryLoadState = .idle
    }

    private func apply(_ home: HomeStateDTO) {
        serverHome = home
        points = home.points
        streak = home.streak
        freezeInventory = home.freezeInventory
    }

    private func applyAndNotify(_ home: HomeStateDTO) {
        apply(home)
        onHomeApplied(home)
    }

    private func rewardGrant(for streak: SessionStreakDTO) -> RewardGrant? {
        switch streak.event {
        case "MILESTONE":
            RewardGrant(amount: 1, kind: .streakMilestone(streakCount: streak.current))
        case "SAVED_BY_FREEZE":
            RewardGrant(amount: streak.freezeInventory, kind: .streakSaved)
        case "RESET":
            RewardGrant(amount: 0, kind: .streakReset)
        case "FIRST_DAY":
            RewardGrant(amount: 0, kind: .streakFirstDay)
        default:
            nil
        }
    }

    private static func clampedProgress(_ progress: Double) -> Double {
        min(1.0, max(0.0, progress))
    }
}
