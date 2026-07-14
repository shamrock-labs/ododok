import XCTest
@testable import ChewChewIOS

@MainActor
final class HomeStoreTests: XCTestCase {
    func testRefreshSuccessAppliesServerHome() async {
        let repository = FakeHomeRepository(result: .success(makeHome(points: 120, streak: 4, freeze: 1, chew: 80, progress: 0.4)))
        let store = HomeStore(repository: repository)

        await store.refresh()

        XCTAssertEqual(store.points, 120)
        XCTAssertEqual(store.currentStreak, 4)
        XCTAssertEqual(store.freezeInventory, 1)
        XCTAssertEqual(store.todayRealChewCount, 80)
        XCTAssertEqual(store.todayProgress, 0.4, accuracy: 0.0001)
        XCTAssertNil(store.errorMessage)
    }

    func testRefreshFailureKeepsPreviousHomeAndSetsErrorMessage() async {
        let initialHome = makeHome(points: 50, streak: 3, freeze: 1, chew: 40, progress: 0.2)
        let repository = FakeHomeRepository(result: .failure(TestError.fetch))
        let store = HomeStore(repository: repository, initialHome: initialHome)

        await store.refresh()

        XCTAssertEqual(store.points, 50)
        XCTAssertEqual(store.currentStreak, 3)
        XCTAssertEqual(store.todayRealChewCount, 40)
        XCTAssertNotNil(store.errorMessage)
    }

    func testRefreshCallsApplyCallback() async {
        let home = makeHome(points: 90, streak: 2, freeze: 0, chew: 30, progress: 0.15)
        let repository = FakeHomeRepository(result: .success(home))
        var appliedHome: HomeStateDTO?
        let store = HomeStore(repository: repository, onHomeApplied: { appliedHome = $0 })

        await store.refresh()

        XCTAssertEqual(appliedHome, home)
    }

    func testApplyExternalInvalidatesPendingRefresh() async {
        let slowHome = makeHome(points: 10, streak: 1, freeze: 0, chew: 10, progress: 0.05)
        let writeHome = makeHome(points: 200, streak: 8, freeze: 2, chew: 120, progress: 0.6)
        let repository = FakeHomeRepository(result: .success(slowHome), delayNanoseconds: 200_000_000)
        let store = HomeStore(repository: repository)

        async let pendingRefresh: Void = store.refresh()
        while !store.isLoading {
            await Task.yield()
        }
        store.applyExternal(writeHome)
        await pendingRefresh

        XCTAssertEqual(store.points, 200)
        XCTAssertEqual(store.currentStreak, 8)
        XCTAssertEqual(store.todayRealChewCount, 120)
    }

    func testShouldApplyCanDropStaleRefresh() async {
        let repository = FakeHomeRepository(result: .success(makeHome(points: 10, streak: 1, freeze: 0, chew: 10, progress: 0.05)))
        let store = HomeStore(repository: repository, initialPoints: 5, initialStreak: 2, initialFreezeInventory: 1)

        await store.refresh { false }

        XCTAssertEqual(store.points, 5)
        XCTAssertEqual(store.currentStreak, 2)
        XCTAssertEqual(store.freezeInventory, 1)
    }

    func testFallbackUsesStoredServerReportChewCountWhenServerHomeIsMissing() {
        let store = HomeStore(
            repository: FakeHomeRepository(result: .success(makeHome())),
            serverReportTodayChewCount: { 30 }
        )

        XCTAssertEqual(store.todayRealChewCount, 30)
        XCTAssertEqual(store.todayProgress, Double(30) / Double(Constants.dailyGoal), accuracy: 0.0001)
    }

    func testFallbackUsesStoredServerReportChewCountWhenServerGoalIsZero() {
        let legacyHome = makeHome(points: 1, streak: 1, freeze: 0, chew: 0, goal: 0, progress: 0)
        let store = HomeStore(
            repository: FakeHomeRepository(result: .success(makeHome())),
            initialHome: legacyHome,
            serverReportTodayChewCount: { 45 }
        )

        XCTAssertEqual(store.todayRealChewCount, 45)
        XCTAssertEqual(store.todayProgress, Double(45) / Double(Constants.dailyGoal), accuracy: 0.0001)
    }

    func testResetClearsHomeState() {
        let store = HomeStore(
            repository: FakeHomeRepository(result: .success(makeHome())),
            initialHome: makeHome(points: 80, streak: 4, freeze: 2, chew: 20, progress: 0.1)
        )

        store.reset()

        XCTAssertNil(store.serverHome)
        XCTAssertEqual(store.points, 0)
        XCTAssertEqual(store.currentStreak, 0)
        XCTAssertEqual(store.freezeInventory, 0)
        XCTAssertNil(store.errorMessage)
    }

    func testSyncLocalCacheUpdatesDisplayedStatsAndServerSnapshot() {
        let store = HomeStore(
            repository: FakeHomeRepository(result: .success(makeHome())),
            initialHome: makeHome(points: 80, streak: 4, freeze: 2, chew: 20, progress: 0.1)
        )

        store.syncLocalCache(points: 30, streak: 3, freezeInventory: 1)

        XCTAssertEqual(store.points, 30)
        XCTAssertEqual(store.currentStreak, 3)
        XCTAssertEqual(store.freezeInventory, 1)
        XCTAssertEqual(store.serverHome?.points, 30)
    }

    func testGrantDailyAttendanceAppliesHomeAndShowsReward() async {
        let home = makeHome(points: 10, streak: 1, freeze: 0, chew: 0, progress: 0)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .success(
                AttendanceResultDTO(grantedPoints: 10, capped: false, idempotentReplay: false, userStats: home)
            )
        )
        var rewarded: (amount: Int, kind: String)?
        let store = HomeStore(
            repository: repository,
            onRewardEarned: { rewarded = ($0, $1) }
        )

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.points, 10)
        XCTAssertEqual(store.pendingRewardGrant, RewardGrant(amount: 10, kind: .attendance))
        XCTAssertEqual(rewarded?.amount, 10)
        XCTAssertEqual(rewarded?.kind, "attendance")
    }

    func testGrantDailyAttendanceIdempotentReplayDoesNotShowReward() async {
        let home = makeHome(points: 10, streak: 1, freeze: 0, chew: 0, progress: 0)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .success(
                AttendanceResultDTO(grantedPoints: 0, capped: false, idempotentReplay: true, userStats: home)
            )
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.points, 10)
        XCTAssertNil(store.pendingRewardGrant)
    }

    func testGrantDailyAttendanceFailureKeepsStateAndCallsRemoteError() async {
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .failure(TestError.fetch)
        )
        var didReceiveError = false
        let store = HomeStore(
            repository: repository,
            initialPoints: 7,
            onRemoteError: { _ in didReceiveError = true }
        )

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.points, 7)
        XCTAssertNil(store.pendingRewardGrant)
        XCTAssertTrue(didReceiveError)
    }

    func testGrantDailyAttendanceInvalidatesPendingRefresh() async {
        let staleHome = makeHome(points: 1, streak: 1, freeze: 0, chew: 0, progress: 0)
        let attendanceHome = makeHome(points: 20, streak: 2, freeze: 1, chew: 0, progress: 0)
        let repository = FakeHomeRepository(
            result: .success(staleHome),
            attendanceResult: .success(
                AttendanceResultDTO(grantedPoints: 10, capped: false, idempotentReplay: false, userStats: attendanceHome)
            ),
            delayNanoseconds: 200_000_000
        )
        let store = HomeStore(repository: repository)

        async let pendingRefresh: Void = store.refresh()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.grantDailyAttendanceIfNeeded()
        await pendingRefresh

        XCTAssertEqual(store.points, 20)
        XCTAssertEqual(store.currentStreak, 2)
        XCTAssertEqual(store.freezeInventory, 1)
    }

    func testApplySessionRewardPrioritizesStreakEventOverSessionReward() {
        let store = HomeStore(repository: FakeHomeRepository(result: .success(makeHome())))
        let result = makeSessionResult(
            rewardPoints: 15,
            streak: SessionStreakDTO(current: 7, event: "MILESTONE", freezeInventory: 1)
        )

        store.applySessionReward(from: result)

        XCTAssertEqual(store.pendingRewardGrant, RewardGrant(amount: 1, kind: .streakMilestone(streakCount: 7)))
    }

    func testApplySessionRewardShowsSessionRewardWhenNoStreakEvent() {
        let store = HomeStore(repository: FakeHomeRepository(result: .success(makeHome())))
        let result = makeSessionResult(
            rewardPoints: 15,
            streak: SessionStreakDTO(current: 3, event: "INCREMENTED", freezeInventory: 0)
        )

        store.applySessionReward(from: result)

        XCTAssertEqual(store.pendingRewardGrant, RewardGrant(amount: 15, kind: .sessionComplete))
    }

    func testFetchRewardHistorySuccess() async {
        let history = [
            RewardHistoryDTO(
                id: UUID(),
                eventType: .attendance,
                eventDay: "2026-07-07",
                grantedPoints: 10,
                capped: false,
                sessionId: nil
            )
        ]
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            rewardHistoryResult: .success(history)
        )
        let store = HomeStore(repository: repository)

        await store.fetchRewardHistory()

        XCTAssertEqual(store.rewardHistory, history)
        XCTAssertEqual(store.rewardHistoryLoadState, .loaded)
    }

    func testFetchRewardHistoryFailureSetsFailedState() async {
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            rewardHistoryResult: .failure(TestError.fetch)
        )
        let store = HomeStore(repository: repository)

        await store.fetchRewardHistory()

        XCTAssertEqual(store.rewardHistoryLoadState, .failed)
    }

    private static func makeHome(
        points: Int = 0,
        streak: Int = 0,
        freeze: Int = 0,
        chew: Int = 0,
        goal: Int = Constants.dailyGoal,
        progress: Double = 0
    ) -> HomeStateDTO {
        HomeStateDTO(
            deviceId: "device-id",
            displayName: nil,
            points: points,
            streak: streak,
            freezeInventory: freeze,
            todayRealChewCount: chew,
            dailyGoal: goal,
            todayProgress: progress,
            todayCompleted: false
        )
    }

    private func makeHome(
        points: Int = 0,
        streak: Int = 0,
        freeze: Int = 0,
        chew: Int = 0,
        goal: Int = Constants.dailyGoal,
        progress: Double = 0
    ) -> HomeStateDTO {
        Self.makeHome(points: points, streak: streak, freeze: freeze, chew: chew, goal: goal, progress: progress)
    }

    private func makeSessionResult(
        rewardPoints: Int,
        streak: SessionStreakDTO
    ) -> CreateSessionResultDTO {
        let session = ChewingSessionDTO(
            id: UUID(),
            deviceId: "device-id",
            startedAt: Date(),
            endedAt: Date(),
            durationSec: 120,
            sensorLocation: "simulator",
            sampleCount: 10,
            sampleRateHz: 50,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: 60,
            restSeconds: 60,
            chewingFraction: 0.5,
            estimatedTotalChews: 50,
            modelVersion: "test",
            chewingTimeline: "[]"
        )
        return CreateSessionResultDTO(
            chewingSession: session,
            mealReport: MealReportDTO(
                status: .generated,
                sessionId: session.id,
                scorePolicyVersion: "legacy-ios-v1",
                analysisModelVersion: session.modelVersion,
                totalScore: 71,
                axisScores: MealReportAxisScoresDTO(
                    chewingRate: 0,
                    chewingTimeRatio: 100,
                    totalChewCount: 100,
                    mealDuration: 85
                ),
                metrics: MealReportMetricsDTO(
                    chewingRatePerMin: nil,
                    legacyMealRatePerMin: 25,
                    chewingTimeRatio: 0.5,
                    totalChewCount: 50,
                    mealDurationSec: 120
                ),
                grade: .soso,
                recommendedBaseline: MealReportRecommendedBaselineDTO(
                    chewingRatePerMin: MealReportTargetDTO(target: 28),
                    chewingTimeRatio: 0.6,
                    totalChewCount: 300,
                    mealDurationSec: 720
                )
            ),
            chewingSessionAccepted: true,
            rewardEligible: rewardPoints > 0,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: rewardPoints, capped: false, idempotentReplay: false),
            streak: streak,
            today: SessionTodayDTO(completed: false),
            userStats: makeHome()
        )
    }
}

private final class FakeHomeRepository: HomeRepository {
    private let result: Result<HomeStateDTO, Error>
    private let attendanceResult: Result<AttendanceResultDTO, Error>
    private let rewardHistoryResult: Result<[RewardHistoryDTO], Error>
    private let delayNanoseconds: UInt64

    init(
        result: Result<HomeStateDTO, Error>,
        attendanceResult: Result<AttendanceResultDTO, Error>? = nil,
        rewardHistoryResult: Result<[RewardHistoryDTO], Error> = .success([]),
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.attendanceResult = attendanceResult ?? result.map {
            AttendanceResultDTO(grantedPoints: 0, capped: false, idempotentReplay: true, userStats: $0)
        }
        self.rewardHistoryResult = rewardHistoryResult
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchHome() async throws -> HomeStateDTO {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }

    func earnAttendance(now: Date) async throws -> AttendanceResultDTO {
        try attendanceResult.get()
    }

    func fetchRewardHistory() async throws -> [RewardHistoryDTO] {
        try rewardHistoryResult.get()
    }
}

private enum TestError: Error {
    case fetch
}
