import XCTest
@testable import ChewChewIOS

@MainActor
final class RecordsStoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testLoadMonthSuccessStoresCurrentMonthSessions() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let repository = fakeRepository([
            monthStart(jan): [makeDTO(startedAt: jan), makeDTO(startedAt: date(year: 2026, month: 1, day: 11))]
        ])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()

        XCTAssertEqual(store.monthSessions.count, 2)
        XCTAssertNil(store.errorMessage)
    }

    func testLoadMonthEmptyRecordsStoresEmptyList() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let repository = fakeRepository([monthStart(jan): []])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()

        XCTAssertTrue(store.monthSessions.isEmpty)
        XCTAssertNil(store.errorMessage)
    }

    func testLoadMonthFailureSetsErrorMessage() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let repository = fakeRepository([:], fetchError: TestError.fetch)
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()

        XCTAssertTrue(store.monthSessions.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testMoveMonthLoadsNextMonth() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let feb = date(year: 2026, month: 2, day: 3)
        let repository = fakeRepository([
            monthStart(jan): [makeDTO(startedAt: jan)],
            monthStart(feb): [makeDTO(startedAt: feb)]
        ])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()
        await store.moveMonth(delta: 1)

        XCTAssertEqual(store.displayedMonth, monthStart(feb))
        XCTAssertEqual(store.monthSessions.map(\.startedAt), [feb])
    }

    func testMoveMonthBeforeOldestMonthIsBlocked() async {
        let feb = date(year: 2026, month: 2, day: 3)
        let repository = fakeRepository([monthStart(feb): [makeDTO(startedAt: feb)]])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: feb)

        await store.loadInitial()
        await store.moveMonth(delta: -1)

        XCTAssertEqual(store.displayedMonth, monthStart(feb))
    }

    func testDeleteSessionSuccessRemovesOnlyAfterRepositorySucceeds() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let target = makeDTO(startedAt: jan)
        let other = makeDTO(startedAt: date(year: 2026, month: 1, day: 11))
        let repository = fakeRepository([monthStart(jan): [target, other]])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()
        await store.deleteSession(target)

        let deletedIDs = await repository.deletedSessionIDs()
        XCTAssertEqual(store.monthSessions.map(\.id), [other.id])
        XCTAssertEqual(deletedIDs, [target.id])
    }

    func testDeleteAllSessionsSuccessClearsList() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let repository = fakeRepository([monthStart(jan): [makeDTO(startedAt: jan)]])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()
        await store.deleteAllSessions()

        let didDeleteAll = await repository.didDeleteAllSessions()
        XCTAssertTrue(store.monthSessions.isEmpty)
        XCTAssertTrue(didDeleteAll)
    }

    func testDeleteSessionFailureKeepsList() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let target = makeDTO(startedAt: jan)
        let repository = fakeRepository([monthStart(jan): [target]], deleteError: TestError.delete)
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()
        await store.deleteSession(target)

        XCTAssertEqual(store.monthSessions.map(\.id), [target.id])
        XCTAssertNotNil(store.errorMessage)
    }

    func testLatestWinsKeepsLastRequestedMonth() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let feb = date(year: 2026, month: 2, day: 3)
        let janSession = makeDTO(startedAt: jan)
        let febSession = makeDTO(startedAt: feb)
        let repository = fakeRepository(
            [
                monthStart(jan): [janSession],
                monthStart(feb): [febSession]
            ],
            delaysByMonth: [
                monthStart(jan): 200_000_000,
                monthStart(feb): 10_000_000
            ]
        )
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        async let firstLoad: Void = store.loadMonth()
        await Task.yield()
        async let secondLoad: Void = store.moveMonth(delta: 1)
        _ = await (firstLoad, secondLoad)

        XCTAssertEqual(store.displayedMonth, monthStart(feb))
        XCTAssertEqual(store.monthSessions.map(\.id), [febSession.id])
    }

    private func fakeRepository(
        _ sessionsByMonth: [Date: [ChewingSessionDTO]],
        fetchError: Error? = nil,
        deleteError: Error? = nil,
        deleteAllError: Error? = nil,
        delaysByMonth: [Date: UInt64] = [:]
    ) -> FakeMealSessionRepository {
        FakeMealSessionRepository(
            calendar: calendar,
            sessionsByMonth: sessionsByMonth,
            fetchError: fetchError,
            deleteError: deleteError,
            deleteAllError: deleteAllError,
            delaysByMonth: delaysByMonth
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    private func makeDTO(startedAt: Date) -> ChewingSessionDTO {
        ChewingSessionDTO(
            id: UUID(),
            deviceId: "test-device",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSec: 600,
            sensorLocation: "default",
            sampleCount: 3_000,
            sampleRateHz: 50,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: 432,
            restSeconds: 168,
            chewingFraction: 0.7,
            estimatedTotalChews: 300,
            modelVersion: "test"
        )
    }
}

private enum TestError: Error {
    case fetch
    case delete
}

private actor FakeMealSessionRepository: MealSessionRepository {
    private let calendar: Calendar
    private let sessionsByMonth: [Date: [ChewingSessionDTO]]
    private let fetchError: Error?
    private let deleteError: Error?
    private let deleteAllError: Error?
    private let delaysByMonth: [Date: UInt64]
    private var deletedIDs: [UUID] = []
    private var deleteAllCalled = false

    init(
        calendar: Calendar,
        sessionsByMonth: [Date: [ChewingSessionDTO]],
        fetchError: Error?,
        deleteError: Error?,
        deleteAllError: Error?,
        delaysByMonth: [Date: UInt64]
    ) {
        self.calendar = calendar
        self.sessionsByMonth = sessionsByMonth
        self.fetchError = fetchError
        self.deleteError = deleteError
        self.deleteAllError = deleteAllError
        self.delaysByMonth = delaysByMonth
    }

    func fetchSessions(since: Date, until: Date?) async throws -> [ChewingSessionDTO] {
        if let fetchError { throw fetchError }
        if since == .distantPast {
            return sessionsByMonth.values.flatMap { $0 }
        }

        let month = calendar.dateInterval(of: .month, for: since)?.start ?? since
        if let delay = delaysByMonth[month] {
            try? await Task.sleep(nanoseconds: delay)
        }
        return sessionsByMonth[month] ?? []
    }

    func deleteSession(id: UUID) async throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
    }

    func deleteAllSessions() async throws {
        if let deleteAllError { throw deleteAllError }
        deleteAllCalled = true
    }

    func deletedSessionIDs() -> [UUID] {
        deletedIDs
    }

    func didDeleteAllSessions() -> Bool {
        deleteAllCalled
    }
}
