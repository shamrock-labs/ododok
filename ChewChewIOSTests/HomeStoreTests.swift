import XCTest
@testable import ChewChewIOS

// Attendance recovery scenarios intentionally keep the store's behavior matrix together.
// swiftlint:disable file_length
@MainActor
// swiftlint:disable:next type_body_length
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
                AttendanceResultDTO(
                    grantedPoints: 10,
                    capped: false,
                    idempotentReplay: false,
                    streak: makeAttendanceStreak(event: "INCREMENTED"),
                    userStats: home
                )
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

    func testSuccessfulAttendanceImmediatelyMarksTodayInStreakDetail() async {
        let now = Date(timeIntervalSince1970: 1_784_171_400)
        let home = makeHome(points: 10, streak: 1, freeze: 0)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .success(
                AttendanceResultDTO(
                    grantedPoints: 10,
                    capped: false,
                    idempotentReplay: false,
                    streak: makeAttendanceStreak(current: 1, event: "FIRST_DAY"),
                    userStats: home
                )
            ),
            streakDetailResult: .failure(TestError.fetch)
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded(now: now)
        await store.fetchStreakDetail()

        XCTAssertEqual(store.streakDetail?.current, 1)
        XCTAssertEqual(store.streakDetail?.startedOn, "2026-07-16")
        XCTAssertEqual(
            store.streakDetail?.days.first { $0.date == "2026-07-16" }?.state,
            .attended
        )
    }

    func testGrantDailyAttendanceRecoveryAvailableWaitsThenUsePostsPreviewCount() async {
        let status = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResult: .success(status)
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.pendingFreezeRecovery, status)
        XCTAssertEqual(repository.attendanceRequests, [])

        await store.confirmFreezeUse()

        XCTAssertEqual(
            repository.attendanceRequests,
            [AttendanceRequestSpy(decision: .use, expectedMissedDays: 2)]
        )
        XCTAssertNil(store.pendingFreezeRecovery)
    }

    func testGrantDailyAttendanceNotNeededPostsImmediatelyWithoutDecision() async {
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResult: .success(makeAttendanceStatus(.notNeeded))
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(
            repository.attendanceRequests,
            [AttendanceRequestSpy(decision: nil, expectedMissedDays: nil)]
        )
        XCTAssertNil(store.pendingFreezeRecovery)
    }

    func testGrantDailyAttendanceRecoveryAvailableSkipPostsSkip() async {
        let status = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResult: .success(status)
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded()
        await store.skipFreezeUse()

        XCTAssertEqual(
            repository.attendanceRequests,
            [AttendanceRequestSpy(decision: .skip, expectedMissedDays: nil)]
        )
        XCTAssertNil(store.pendingFreezeRecovery)
    }

    func testGrantDailyAttendanceInsufficientWaitsForConfirmationThenPostsSkip() async {
        let status = makeAttendanceStatus(.insufficient, missedDays: 2, inventory: 1)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResult: .success(status)
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.pendingFreezeRecovery, status)
        XCTAssertEqual(repository.attendanceRequests, [])

        await store.confirmInsufficientRecovery()

        XCTAssertEqual(
            repository.attendanceRequests,
            [AttendanceRequestSpy(decision: .skip, expectedMissedDays: nil)]
        )
        XCTAssertNil(store.pendingFreezeRecovery)
    }

    func testAttendanceStatusFailureKeepsCachedHomeAndReportsRemoteError() async {
        let initialHome = makeHome(points: 50, streak: 3, freeze: 1, chew: 40, progress: 0.2)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResult: .failure(TestError.fetch)
        )
        var receivedError: Error?
        let store = HomeStore(
            repository: repository,
            initialHome: initialHome,
            onRemoteError: { receivedError = $0 }
        )

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.serverHome, initialHome)
        XCTAssertEqual(repository.attendanceRequests, [])
        XCTAssertNotNil(receivedError)
    }

    func testFailedFreezeUseKeepsDecisionVisibleForRetry() async {
        let status = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .failure(TestError.fetch),
            attendanceStatusResult: .success(status)
        )
        var didReceiveError = false
        let store = HomeStore(repository: repository, onRemoteError: { _ in didReceiveError = true })

        await store.grantDailyAttendanceIfNeeded()
        await store.confirmFreezeUse()

        XCTAssertEqual(store.pendingFreezeRecovery, status)
        XCTAssertTrue(didReceiveError)
    }

    func testStaleFreezeUseRefetchesDecisionWithoutMutatingHomeOrRewardDialog() async {
        let initialStatus = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let refreshedStatus = makeAttendanceStatus(.insufficient, missedDays: 3, inventory: 2)
        let initialHome = makeHome(points: 50, streak: 3, freeze: 1)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .failure(RemoteStoreError.server(status: 409, code: 4014, message: "stale")),
            attendanceStatusResults: [.success(initialStatus), .success(refreshedStatus)]
        )
        let store = HomeStore(repository: repository, initialHome: initialHome)
        store.applySessionReward(
            from: makeSessionResult(
                rewardPoints: 15,
                streak: SessionStreakDTO(current: 3, event: "INCREMENTED", freezeInventory: 0)
            )
        )
        let rewardBeforeUse = store.pendingRewardGrant

        await store.grantDailyAttendanceIfNeeded()
        await store.confirmFreezeUse()

        XCTAssertEqual(store.pendingFreezeRecovery, refreshedStatus)
        XCTAssertEqual(store.serverHome, initialHome)
        XCTAssertEqual(store.pendingRewardGrant, rewardBeforeUse)
        XCTAssertEqual(repository.attendanceStatusFetchCount, 2)
    }

    func testStaleFreezeUseRefetchingNotNeededSubmitsNormalAttendance() async {
        let initialStatus = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let initialHome = makeHome(points: 50, streak: 3, freeze: 1)
        let attendanceHome = makeHome(points: 60, streak: 1, freeze: 1)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResults: [
                .failure(RemoteStoreError.server(status: 409, code: 4014, message: "stale")),
                .success(
                    AttendanceResultDTO(
                        grantedPoints: 0,
                        capped: false,
                        idempotentReplay: true,
                        streak: makeAttendanceStreak(event: "RESET"),
                        userStats: attendanceHome
                    )
                )
            ],
            attendanceStatusResults: [
                .success(initialStatus),
                .success(makeAttendanceStatus(.notNeeded))
            ]
        )
        let store = HomeStore(repository: repository, initialHome: initialHome)
        store.applySessionReward(
            from: makeSessionResult(
                rewardPoints: 15,
                streak: SessionStreakDTO(current: 3, event: "INCREMENTED", freezeInventory: 0)
            )
        )
        let rewardBeforeUse = store.pendingRewardGrant

        await store.grantDailyAttendanceIfNeeded()
        await store.confirmFreezeUse()

        XCTAssertEqual(
            repository.attendanceRequests,
            [
                AttendanceRequestSpy(decision: .use, expectedMissedDays: 2),
                AttendanceRequestSpy(decision: nil, expectedMissedDays: nil)
            ]
        )
        XCTAssertEqual(store.serverHome, attendanceHome)
        XCTAssertEqual(store.pendingRewardGrant, rewardBeforeUse)
        XCTAssertNil(store.pendingFreezeRecovery)
    }

    func testDuplicateAttendanceTasksCreateOnlyOneDecisionAndOnePost() async {
        let status = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResult: .success(status),
            attendanceStatusDelayNanoseconds: 100_000_000,
            attendanceDelayNanoseconds: 100_000_000
        )
        let store = HomeStore(repository: repository)

        async let firstGrant: Void = store.grantDailyAttendanceIfNeeded()
        async let secondGrant: Void = store.grantDailyAttendanceIfNeeded()
        _ = await (firstGrant, secondGrant)

        XCTAssertEqual(repository.attendanceStatusFetchCount, 1)
        XCTAssertEqual(store.pendingFreezeRecovery, status)

        async let firstUse: Void = store.confirmFreezeUse()
        async let secondUse: Void = store.confirmFreezeUse()
        _ = await (firstUse, secondUse)

        XCTAssertEqual(
            repository.attendanceRequests,
            [AttendanceRequestSpy(decision: .use, expectedMissedDays: 2)]
        )
        XCTAssertNil(store.pendingFreezeRecovery)
    }

    func testResetInvalidatesInFlightAttendanceStatusAndAllowsNewAccountRequest() async {
        let oldStatus = makeAttendanceStatus(.recoveryAvailable, missedDays: 2, inventory: 3)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceStatusResults: [.success(oldStatus), .success(makeAttendanceStatus(.notNeeded))],
            attendanceStatusDelayNanoseconds: 100_000_000
        )
        let store = HomeStore(repository: repository)

        async let oldAccountRequest: Void = store.grantDailyAttendanceIfNeeded()
        while repository.attendanceStatusFetchCount == 0 {
            await Task.yield()
        }
        store.reset()
        await oldAccountRequest

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(repository.attendanceStatusFetchCount, 2)
        XCTAssertNil(store.pendingFreezeRecovery)
        XCTAssertEqual(
            repository.attendanceRequests,
            [AttendanceRequestSpy(decision: nil, expectedMissedDays: nil)]
        )
    }

    func testResetPreventsInFlightAttendancePostFromApplyingOldAccountResult() async {
        let oldHome = makeHome(points: 99, streak: 8, freeze: 2)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .success(
                AttendanceResultDTO(
                    grantedPoints: 10,
                    capped: false,
                    idempotentReplay: false,
                    streak: makeAttendanceStreak(event: "INCREMENTED"),
                    userStats: oldHome
                )
            ),
            attendanceStatusResult: .success(makeAttendanceStatus(.notNeeded)),
            attendanceDelayNanoseconds: 100_000_000
        )
        let store = HomeStore(repository: repository)

        async let oldAccountRequest: Void = store.grantDailyAttendanceIfNeeded()
        while repository.attendanceRequests.isEmpty {
            await Task.yield()
        }
        store.reset()
        await oldAccountRequest

        XCTAssertNil(store.serverHome)
        XCTAssertEqual(store.points, 0)
        XCTAssertNil(store.pendingRewardGrant)
    }

    func testGrantDailyAttendanceIdempotentReplayDoesNotShowReward() async {
        let home = makeHome(points: 10, streak: 1, freeze: 0, chew: 0, progress: 0)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .success(
                AttendanceResultDTO(
                    grantedPoints: 0,
                    capped: false,
                    idempotentReplay: true,
                    streak: makeAttendanceStreak(
                        event: "MILESTONE",
                        freezeConsumed: 1,
                        freezeGranted: 1
                    ),
                    userStats: home
                )
            )
        )
        let store = HomeStore(repository: repository)

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(store.points, 10)
        XCTAssertNil(store.pendingRewardGrant)
    }

    func testGrantDailyAttendancePrioritizesCombinedFreezeUseAndGrant() async {
        let home = makeHome(points: 10, streak: 7, freeze: 1)
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            attendanceResult: .success(
                AttendanceResultDTO(
                    grantedPoints: 10,
                    capped: false,
                    idempotentReplay: false,
                    streak: makeAttendanceStreak(
                        current: 7,
                        event: "MILESTONE",
                        freezeInventory: 1,
                        freezeConsumed: 2,
                        freezeGranted: 1
                    ),
                    userStats: home
                )
            )
        )
        var earned: (Int, String)?
        let store = HomeStore(repository: repository, onRewardEarned: { earned = ($0, $1) })

        await store.grantDailyAttendanceIfNeeded()

        XCTAssertEqual(
            store.pendingRewardGrant,
            RewardGrant(
                amount: 1,
                kind: .streakFreezeUsedAndGranted(
                    consumed: 2,
                    granted: 1,
                    inventory: 1,
                    streakCount: 7
                )
            )
        )
        XCTAssertEqual(earned?.0, 10)
        XCTAssertEqual(earned?.1, "attendance")
    }

    func testGrantDailyAttendanceMapsGrantUseResetAndFirstDay() async {
        let cases: [(AttendanceStreakDTO, RewardGrant)] = [
            (
                makeAttendanceStreak(current: 7, event: "MILESTONE", freezeInventory: 2, freezeGranted: 1),
                RewardGrant(
                    amount: 1,
                    kind: .streakFreezeGranted(streakCount: 7, granted: 1, inventory: 2)
                )
            ),
            (
                makeAttendanceStreak(current: 6, event: "SAVED_BY_FREEZE", freezeInventory: 1, freezeConsumed: 2),
                RewardGrant(amount: 2, kind: .streakFreezeUsed(consumed: 2, inventory: 1))
            ),
            (
                makeAttendanceStreak(current: 1, event: "RESET"),
                RewardGrant(amount: 0, kind: .streakReset)
            ),
            (
                makeAttendanceStreak(current: 1, event: "FIRST_DAY"),
                RewardGrant(amount: 0, kind: .streakFirstDay)
            )
        ]

        for (streak, expectedGrant) in cases {
            let repository = FakeHomeRepository(
                result: .success(makeHome()),
                attendanceResult: .success(
                    AttendanceResultDTO(
                        grantedPoints: 0,
                        capped: true,
                        idempotentReplay: false,
                        streak: streak,
                        userStats: makeHome(streak: streak.current, freeze: streak.freezeInventory)
                    )
                )
            )
            let store = HomeStore(repository: repository)

            await store.grantDailyAttendanceIfNeeded()

            XCTAssertEqual(store.pendingRewardGrant, expectedGrant)
        }
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
                AttendanceResultDTO(
                    grantedPoints: 10,
                    capped: false,
                    idempotentReplay: false,
                    streak: makeAttendanceStreak(current: 2, event: "INCREMENTED", freezeInventory: 1),
                    userStats: attendanceHome
                )
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

    func testApplySessionRewardIgnoresLegacySessionStreakEvent() {
        let store = HomeStore(repository: FakeHomeRepository(result: .success(makeHome())))
        let result = makeSessionResult(
            rewardPoints: 15,
            streak: SessionStreakDTO(current: 7, event: "MILESTONE", freezeInventory: 1)
        )

        store.applySessionReward(from: result)

        XCTAssertEqual(store.pendingRewardGrant, RewardGrant(amount: 15, kind: .sessionComplete))
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

    func testFetchStreakDetailSuccessStoresDetail() async {
        let detail = makeStreakDetail()
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            streakDetailResult: .success(detail)
        )
        let store = HomeStore(repository: repository)

        await store.fetchStreakDetail()

        XCTAssertEqual(store.streakDetail, detail)
        XCTAssertEqual(store.streakDetailLoadState, .loaded)
    }

    func testMoveStreakMonthFetchesOnlyTheAdjacentMonth() async {
        let detail = makeStreakDetail()
        let previous = StreakDetailDTO(
            asOf: detail.asOf,
            month: "2026-06",
            oldestRecordedOn: "2026-05-20",
            current: detail.current,
            longest: detail.longest,
            startedOn: detail.startedOn,
            freezeInventory: detail.freezeInventory,
            days: []
        )
        let repository = SequencedStreakHomeRepository(results: [.success(detail), .success(previous)])
        let store = HomeStore(repository: repository)

        await store.fetchStreakDetail()
        await store.moveStreakMonth(delta: -1)

        XCTAssertEqual(repository.requestedMonths, [nil, "2026-06"])
        XCTAssertEqual(store.streakDetail?.resolvedMonth, "2026-06")
    }

    func testMoveStreakMonthStopsAtOldestAndCurrentMonths() async {
        let detail = makeStreakDetail()
        let currentRepository = SequencedStreakHomeRepository(results: [.success(detail)])
        let currentStore = HomeStore(repository: currentRepository)

        await currentStore.fetchStreakDetail()
        await currentStore.moveStreakMonth(delta: 1)

        XCTAssertEqual(currentRepository.requestedMonths, [nil])

        var oldestDetail = detail
        oldestDetail.month = "2026-06"
        let oldestRepository = SequencedStreakHomeRepository(results: [.success(oldestDetail)])
        let oldestStore = HomeStore(repository: oldestRepository)

        await oldestStore.fetchStreakDetail()
        await oldestStore.moveStreakMonth(delta: -1)

        XCTAssertEqual(oldestRepository.requestedMonths, [nil])
    }

    func testFetchStreakDetailFailureKeepsLastGoodDetail() async {
        let detail = makeStreakDetail()
        let repository = SequencedStreakHomeRepository(results: [.success(detail), .failure(TestError.fetch)])
        let store = HomeStore(repository: repository)

        await store.fetchStreakDetail()
        await store.fetchStreakDetail()

        XCTAssertEqual(store.streakDetail, detail)
        XCTAssertEqual(store.streakDetailLoadState, .failed)
    }

    func testFetchStreakDetailCanRetryAfterFirstFailure() async {
        let detail = makeStreakDetail()
        let repository = SequencedStreakHomeRepository(results: [.failure(TestError.fetch), .success(detail)])
        let store = HomeStore(repository: repository)

        await store.fetchStreakDetail()
        XCTAssertNil(store.streakDetail)
        XCTAssertEqual(store.streakDetailLoadState, .failed)

        await store.fetchStreakDetail()
        XCTAssertEqual(store.streakDetail, detail)
        XCTAssertEqual(store.streakDetailLoadState, .loaded)
    }

    func testMoveStreakMonthStillRequestsAdjacentMonthAfterInitialFailure() async {
        let repository = SequencedStreakHomeRepository(results: [
            .failure(TestError.fetch),
            .failure(TestError.fetch),
        ])
        let store = HomeStore(repository: repository)

        await store.fetchStreakDetail()
        let initialMonth = store.streakSelectedMonth
        await store.moveStreakMonth(delta: -1)

        XCTAssertEqual(repository.requestedMonths.first, nil)
        XCTAssertEqual(repository.requestedMonths.count, 2)
        XCTAssertNotNil(initialMonth)
        XCTAssertNotEqual(store.streakSelectedMonth, initialMonth)
    }

    func testResetClearsStreakDetailState() async {
        let repository = FakeHomeRepository(
            result: .success(makeHome()),
            streakDetailResult: .success(makeStreakDetail())
        )
        let store = HomeStore(repository: repository)
        await store.fetchStreakDetail()

        store.reset()

        XCTAssertNil(store.streakDetail)
        XCTAssertEqual(store.streakDetailLoadState, .idle)
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

    private func makeAttendanceStreak(
        current: Int = 1,
        event: String,
        freezeInventory: Int = 0,
        freezeConsumed: Int = 0,
        freezeGranted: Int = 0
    ) -> AttendanceStreakDTO {
        AttendanceStreakDTO(
            current: current,
            longest: max(current, 18),
            startedOn: "2026-07-08",
            event: event,
            freezeInventory: freezeInventory,
            freezeConsumed: freezeConsumed,
            freezeGranted: freezeGranted
        )
    }

    private func makeAttendanceStatus(
        _ status: AttendanceRecoveryStatus,
        missedDays: Int = 0,
        inventory: Int = 0
    ) -> AttendanceStatusDTO {
        AttendanceStatusDTO(
            asOf: "2026-07-16",
            status: status,
            missedDates: missedDays > 0
                ? (1...missedDays).map { "2026-07-\(String(format: "%02d", $0))" }
                : [],
            requiredFreezes: missedDays,
            freezeInventory: inventory
        )
    }

    private func makeStreakDetail() -> StreakDetailDTO {
        StreakDetailDTO(
            asOf: "2026-07-15",
            month: "2026-07",
            oldestRecordedOn: "2026-06-21",
            current: 8,
            longest: 18,
            startedOn: "2026-07-08",
            freezeInventory: 1,
            days: [
                StreakDayDTO(date: "2026-07-14", state: .attended),
                StreakDayDTO(date: "2026-07-15", state: .frozen)
            ]
        )
    }
}

#if DEBUG
final class StreakDemoFixtureTests: XCTestCase {
    func testCurrentMonthFixtureShowsLongStreakAndFreezeDays() {
        let detail = StreakDemoFixture.detail(month: nil)

        XCTAssertEqual(StreakDemoFixture.home.streak, 18)
        XCTAssertEqual(StreakDemoFixture.home.freezeInventory, 2)
        XCTAssertEqual(detail.resolvedMonth, "2026-07")
        XCTAssertEqual(detail.oldestRecordedOn, "2026-04-08")
        XCTAssertEqual(detail.current, 18)
        XCTAssertEqual(detail.startedOn, "2026-06-29")
        XCTAssertEqual(detail.freezeInventory, 2)
        XCTAssertEqual(detail.days.first { $0.date == "2026-07-03" }?.state, .frozen)
        XCTAssertEqual(detail.days.first { $0.date == "2026-07-11" }?.state, .frozen)
        XCTAssertEqual(detail.days.first { $0.date == "2026-07-16" }?.state, .attended)
    }

    func testPreviousMonthFixtureContainsBrokenAndCurrentStreakSegments() {
        let detail = StreakDemoFixture.detail(month: "2026-06")

        XCTAssertEqual(detail.resolvedMonth, "2026-06")
        XCTAssertEqual(detail.days.first { $0.date == "2026-06-06" }?.state, .frozen)
        XCTAssertNil(detail.days.first { $0.date == "2026-06-13" })
        XCTAssertEqual(detail.days.first { $0.date == "2026-06-29" }?.state, .attended)
        XCTAssertEqual(detail.days.first { $0.date == "2026-06-30" }?.state, .attended)
    }

    func testOutOfRangeMonthFixtureKeepsContractWithNoRows() {
        let detail = StreakDemoFixture.detail(month: "2026-03")

        XCTAssertEqual(detail.resolvedMonth, "2026-03")
        XCTAssertTrue(detail.days.isEmpty)
        XCTAssertEqual(detail.oldestRecordedOn, "2026-04-08")
    }

    func testDailyReportsMatchFixtureSessionsAcrossCaptureWeek() {
        let expected: [(date: String, meals: Int, chews: Int)] = [
            ("2026-07-10", 1, 620),
            ("2026-07-11", 1, 760),
            ("2026-07-12", 1, 690),
            ("2026-07-13", 1, 840),
            ("2026-07-14", 3, 735),
            ("2026-07-15", 1, 790),
            ("2026-07-16", 1, 812),
        ]

        for item in expected {
            let report = StreakDemoFixture.dailyReport(date: item.date)
            XCTAssertEqual(report.mealCount, item.meals, item.date)
            XCTAssertEqual(report.meals.count, item.meals, item.date)
            XCTAssertEqual(report.totalChews, item.chews, item.date)
        }

        XCTAssertEqual(
            StreakDemoFixture.dailyReport(date: "2026-07-14").meals.map(\.slot),
            ["BREAKFAST", "LUNCH", "DINNER"]
        )
        XCTAssertEqual(StreakDemoFixture.dailyReport(date: "2026-07-09").mealCount, 0)
    }

    func testActiveDebugProfileRoutesHomeAndStreakAwayFromRemoteStore() async throws {
        let repository = RemoteStoreHomeRepository(
            remoteStore: NoopRemoteStore(),
            debugProfileIsActive: { true }
        )

        let home = try await repository.fetchHome()
        let detail = try await repository.fetchStreakDetail(month: "2026-06")

        XCTAssertEqual(home.streak, 18)
        XCTAssertEqual(home.freezeInventory, 2)
        XCTAssertEqual(detail.resolvedMonth, "2026-06")
        XCTAssertFalse(detail.days.isEmpty)
    }

    func testInactiveDebugProfileKeepsExistingRemoteStoreRoute() async throws {
        let repository = RemoteStoreHomeRepository(
            remoteStore: NoopRemoteStore(),
            debugProfileIsActive: { false }
        )

        let home = try await repository.fetchHome()
        let detail = try await repository.fetchStreakDetail(month: "2026-06")

        XCTAssertEqual(home.streak, 0)
        XCTAssertEqual(home.freezeInventory, 0)
        XCTAssertTrue(detail.days.isEmpty)
    }
}
#endif

private struct AttendanceRequestSpy: Equatable {
    let decision: FreezeDecisionDTO?
    let expectedMissedDays: Int?
}

private final class FakeHomeRepository: HomeRepository {
    private let result: Result<HomeStateDTO, Error>
    private var attendanceResults: [Result<AttendanceResultDTO, Error>]
    private let rewardHistoryResult: Result<[RewardHistoryDTO], Error>
    private let streakDetailResult: Result<StreakDetailDTO, Error>
    private let delayNanoseconds: UInt64
    private var attendanceStatusResults: [Result<AttendanceStatusDTO, Error>]
    private let attendanceStatusDelayNanoseconds: UInt64
    private let attendanceDelayNanoseconds: UInt64
    private(set) var attendanceStatusFetchCount = 0
    private(set) var attendanceRequests: [AttendanceRequestSpy] = []

    init(
        result: Result<HomeStateDTO, Error>,
        attendanceResult: Result<AttendanceResultDTO, Error>? = nil,
        attendanceResults: [Result<AttendanceResultDTO, Error>]? = nil,
        attendanceStatusResult: Result<AttendanceStatusDTO, Error> = .success(
            AttendanceStatusDTO(asOf: "", status: .notNeeded, missedDates: [], requiredFreezes: 0, freezeInventory: 0)
        ),
        attendanceStatusResults: [Result<AttendanceStatusDTO, Error>]? = nil,
        rewardHistoryResult: Result<[RewardHistoryDTO], Error> = .success([]),
        streakDetailResult: Result<StreakDetailDTO, Error> = .success(.empty),
        delayNanoseconds: UInt64 = 0,
        attendanceStatusDelayNanoseconds: UInt64 = 0,
        attendanceDelayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        let defaultAttendanceResult = attendanceResult ?? result.map {
            AttendanceResultDTO(
                grantedPoints: 0,
                capped: false,
                idempotentReplay: true,
                streak: .empty,
                userStats: $0
            )
        }
        self.attendanceResults = attendanceResults ?? [defaultAttendanceResult]
        self.rewardHistoryResult = rewardHistoryResult
        self.streakDetailResult = streakDetailResult
        self.delayNanoseconds = delayNanoseconds
        self.attendanceStatusResults = attendanceStatusResults ?? [attendanceStatusResult]
        self.attendanceStatusDelayNanoseconds = attendanceStatusDelayNanoseconds
        self.attendanceDelayNanoseconds = attendanceDelayNanoseconds
    }

    func fetchHome() async throws -> HomeStateDTO {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }

    func earnAttendance(now: Date) async throws -> AttendanceResultDTO {
        try await earnAttendance(now: now, decision: nil, expectedMissedDays: nil)
    }

    func fetchAttendanceStatus() async throws -> AttendanceStatusDTO {
        attendanceStatusFetchCount += 1
        let result = attendanceStatusResults.count > 1
            ? attendanceStatusResults.removeFirst()
            : attendanceStatusResults[0]
        if attendanceStatusDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: attendanceStatusDelayNanoseconds)
        }
        return try result.get()
    }

    func earnAttendance(
        now: Date,
        decision: FreezeDecisionDTO?,
        expectedMissedDays: Int?
    ) async throws -> AttendanceResultDTO {
        attendanceRequests.append(
            AttendanceRequestSpy(decision: decision, expectedMissedDays: expectedMissedDays)
        )
        let result = attendanceResults.count > 1
            ? attendanceResults.removeFirst()
            : attendanceResults[0]
        if attendanceDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: attendanceDelayNanoseconds)
        }
        return try result.get()
    }

    func fetchRewardHistory() async throws -> [RewardHistoryDTO] {
        try rewardHistoryResult.get()
    }

    func fetchStreakDetail(month: String?) async throws -> StreakDetailDTO {
        try streakDetailResult.get()
    }
}

private final class SequencedStreakHomeRepository: HomeRepository {
    private var results: [Result<StreakDetailDTO, Error>]
    private(set) var requestedMonths: [String?] = []

    init(results: [Result<StreakDetailDTO, Error>]) {
        self.results = results
    }

    func fetchHome() async throws -> HomeStateDTO { .empty(deviceId: "test") }
    func earnAttendance(now: Date) async throws -> AttendanceResultDTO {
        try await earnAttendance(now: now, decision: nil, expectedMissedDays: nil)
    }
    func fetchAttendanceStatus() async throws -> AttendanceStatusDTO {
        AttendanceStatusDTO(asOf: "", status: .notNeeded, missedDates: [], requiredFreezes: 0, freezeInventory: 0)
    }
    func earnAttendance(
        now: Date,
        decision: FreezeDecisionDTO?,
        expectedMissedDays: Int?
    ) async throws -> AttendanceResultDTO {
        AttendanceResultDTO(
            grantedPoints: 0,
            capped: false,
            idempotentReplay: true,
            streak: .empty,
            userStats: .empty(deviceId: "test")
        )
    }
    func fetchRewardHistory() async throws -> [RewardHistoryDTO] { [] }
    func fetchStreakDetail(month: String?) async throws -> StreakDetailDTO {
        requestedMonths.append(month)
        return try results.removeFirst().get()
    }
}

private enum TestError: Error {
    case fetch
}
