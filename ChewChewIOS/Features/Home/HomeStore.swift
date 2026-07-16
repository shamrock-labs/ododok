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

    enum StreakDetailLoadState: Equatable {
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
    private(set) var pendingFreezeRecovery: AttendanceStatusDTO?
    private(set) var rewardHistory: [RewardHistoryDTO] = []
    private(set) var rewardHistoryLoadState: RewardHistoryLoadState = .idle
    private(set) var streakDetail: StreakDetailDTO?
    private(set) var streakDetailLoadState: StreakDetailLoadState = .idle

    private let repository: HomeRepository
    private let serverReportTodayChewCount: @MainActor () -> Int
    private let onHomeApplied: @MainActor (HomeStateDTO) -> Void
    private let onRemoteError: @MainActor (Error) -> Void
    private let onRewardEarned: @MainActor (Int, String) -> Void
    private let onStreakEvent: @MainActor (String, Int) -> Void
    private var loadGeneration: Int = 0
    private var rewardHistoryGeneration: Int = 0
    private var streakDetailGeneration: Int = 0
    private var attendanceOperationGeneration = 0
    private var activeAttendanceOperation: Int?

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
        if result.reward.grantedPoints > 0 && !result.reward.idempotentReplay {
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
        guard pendingFreezeRecovery == nil, let operation = beginAttendanceOperation() else { return }
        defer { finishAttendanceOperation(operation) }

        do {
            let status = try await repository.fetchAttendanceStatus()
            guard isCurrentAttendanceOperation(operation) else { return }
            switch status.status {
            case .notNeeded:
                _ = try await submitAttendance(
                    now: now,
                    decision: nil,
                    expectedMissedDays: nil,
                    operation: operation
                )
            case .recoveryAvailable, .insufficient:
                pendingFreezeRecovery = status
            }
        } catch {
            guard isCurrentAttendanceOperation(operation) else { return }
            onRemoteError(error)
        }
    }

    func confirmFreezeUse(now: Date = Date()) async {
        guard
            let recovery = pendingFreezeRecovery,
            recovery.status == .recoveryAvailable,
            let operation = beginAttendanceOperation()
        else { return }

        defer { finishAttendanceOperation(operation) }

        do {
            let didApply = try await submitAttendance(
                now: now,
                decision: .use,
                expectedMissedDays: recovery.requiredFreezes,
                operation: operation
            )
            if didApply {
                pendingFreezeRecovery = nil
            }
        } catch {
            guard isCurrentAttendanceOperation(operation) else { return }
            guard Self.isStaleRecovery(error) else {
                onRemoteError(error)
                return
            }

            do {
                let refreshedStatus = try await repository.fetchAttendanceStatus()
                guard isCurrentAttendanceOperation(operation) else { return }
                switch refreshedStatus.status {
                case .notNeeded:
                    let didApply = try await submitAttendance(
                        now: now,
                        decision: nil,
                        expectedMissedDays: nil,
                        operation: operation
                    )
                    if didApply {
                        pendingFreezeRecovery = nil
                    }
                case .recoveryAvailable, .insufficient:
                    pendingFreezeRecovery = refreshedStatus
                }
            } catch {
                guard isCurrentAttendanceOperation(operation) else { return }
                onRemoteError(error)
            }
        }
    }

    func skipFreezeUse(now: Date = Date()) async {
        guard pendingFreezeRecovery?.status == .recoveryAvailable else { return }
        await confirmSkip(now: now)
    }

    func confirmInsufficientRecovery(now: Date = Date()) async {
        guard pendingFreezeRecovery?.status == .insufficient else { return }
        await confirmSkip(now: now)
    }

    private func confirmSkip(now: Date) async {
        guard pendingFreezeRecovery != nil, let operation = beginAttendanceOperation() else { return }
        defer { finishAttendanceOperation(operation) }

        do {
            let didApply = try await submitAttendance(
                now: now,
                decision: .skip,
                expectedMissedDays: nil,
                operation: operation
            )
            if didApply {
                pendingFreezeRecovery = nil
            }
        } catch {
            guard isCurrentAttendanceOperation(operation) else { return }
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

    func fetchStreakDetail() async {
        streakDetailGeneration += 1
        let generation = streakDetailGeneration
        streakDetailLoadState = .loading
        do {
            let detail = try await repository.fetchStreakDetail()
            guard generation == streakDetailGeneration else { return }
            streakDetail = detail
            streakDetailLoadState = .loaded
        } catch {
            guard generation == streakDetailGeneration else { return }
            onRemoteError(error)
            streakDetailLoadState = .failed
        }
    }

    func dismissPendingRewardGrant() {
        pendingRewardGrant = nil
    }

    func reset() {
        loadGeneration += 1
        rewardHistoryGeneration += 1
        streakDetailGeneration += 1
        attendanceOperationGeneration &+= 1
        activeAttendanceOperation = nil
        serverHome = nil
        points = 0
        streak = 0
        freezeInventory = 0
        errorMessage = nil
        isLoading = false
        pendingRewardGrant = nil
        pendingFreezeRecovery = nil
        rewardHistory = []
        rewardHistoryLoadState = .idle
        streakDetail = nil
        streakDetailLoadState = .idle
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

    private func submitAttendance(
        now: Date,
        decision: FreezeDecisionDTO?,
        expectedMissedDays: Int?,
        operation: Int
    ) async throws -> Bool {
        loadGeneration += 1
        let result = try await repository.earnAttendance(
            now: now,
            decision: decision,
            expectedMissedDays: expectedMissedDays
        )
        guard isCurrentAttendanceOperation(operation) else { return false }
        loadGeneration += 1
        applyAndNotify(result.userStats)
        if !result.idempotentReplay {
            if let streakGrant = rewardGrant(for: result.streak) {
                pendingRewardGrant = streakGrant
                onStreakEvent(streakGrant.kind.analyticsType, streakGrant.amount)
            } else if result.grantedPoints > 0 {
                pendingRewardGrant = RewardGrant(amount: result.grantedPoints, kind: .attendance)
            }
        }
        if result.grantedPoints > 0 && !result.idempotentReplay {
            onRewardEarned(result.grantedPoints, "attendance")
        }
        return true
    }

    private func beginAttendanceOperation() -> Int? {
        guard activeAttendanceOperation == nil else { return nil }
        attendanceOperationGeneration &+= 1
        activeAttendanceOperation = attendanceOperationGeneration
        return attendanceOperationGeneration
    }

    private func finishAttendanceOperation(_ operation: Int) {
        if activeAttendanceOperation == operation {
            activeAttendanceOperation = nil
        }
    }

    private func isCurrentAttendanceOperation(_ operation: Int) -> Bool {
        activeAttendanceOperation == operation
    }

    private static func isStaleRecovery(_ error: Error) -> Bool {
        guard case let RemoteStoreError.server(status, code, _) = error else { return false }
        return status == 409 && code == 4014
    }

    private func rewardGrant(for streak: AttendanceStreakDTO) -> RewardGrant? {
        if streak.freezeConsumed > 0 && streak.freezeGranted > 0 {
            return RewardGrant(
                amount: streak.freezeGranted,
                kind: .streakFreezeUsedAndGranted(
                    consumed: streak.freezeConsumed,
                    granted: streak.freezeGranted,
                    inventory: streak.freezeInventory,
                    streakCount: streak.current
                )
            )
        }
        if streak.freezeGranted > 0 {
            return RewardGrant(
                amount: streak.freezeGranted,
                kind: .streakFreezeGranted(
                    streakCount: streak.current,
                    granted: streak.freezeGranted,
                    inventory: streak.freezeInventory
                )
            )
        }
        if streak.freezeConsumed > 0 {
            return RewardGrant(
                amount: streak.freezeConsumed,
                kind: .streakFreezeUsed(
                    consumed: streak.freezeConsumed,
                    inventory: streak.freezeInventory
                )
            )
        }
        return switch streak.event {
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
