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
        await Task.yield()
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

    func testFallbackUsesLocalTodayRealChewCountWhenServerHomeIsMissing() {
        let store = HomeStore(
            repository: FakeHomeRepository(result: .success(makeHome())),
            localTodayRealChewCount: { 30 }
        )

        XCTAssertEqual(store.todayRealChewCount, 30)
        XCTAssertEqual(store.todayProgress, Double(30) / Double(Constants.dailyGoal), accuracy: 0.0001)
    }

    func testFallbackUsesLocalTodayRealChewCountWhenServerGoalIsZero() {
        let legacyHome = makeHome(points: 1, streak: 1, freeze: 0, chew: 0, goal: 0, progress: 0)
        let store = HomeStore(
            repository: FakeHomeRepository(result: .success(makeHome())),
            initialHome: legacyHome,
            localTodayRealChewCount: { 45 }
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
}

private final class FakeHomeRepository: HomeRepository {
    private let result: Result<HomeStateDTO, Error>
    private let delayNanoseconds: UInt64

    init(result: Result<HomeStateDTO, Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchHome() async throws -> HomeStateDTO {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

private enum TestError: Error {
    case fetch
}
