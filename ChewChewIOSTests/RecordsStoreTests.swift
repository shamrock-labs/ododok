import XCTest
@testable import ChewChewIOS

@MainActor
final class RecordsStoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            XCTFail("UTC time zone must be available")
            return calendar
        }
        calendar.timeZone = timeZone
        return calendar
    }

    func testLoadMonthSuccessStoresCurrentMonthSessions() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let repository = fakeRepository([
            monthStart(jan): [makeRecord(startedAt: jan), makeRecord(startedAt: date(year: 2026, month: 1, day: 11))]
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
            monthStart(jan): [makeRecord(startedAt: jan)],
            monthStart(feb): [makeRecord(startedAt: feb)]
        ])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()
        await store.moveMonth(delta: 1)

        XCTAssertEqual(store.displayedMonth, monthStart(feb))
        XCTAssertEqual(store.monthSessions.map(\.startedAt), [feb])
    }

    func testMoveMonthBeforeOldestMonthIsBlocked() async {
        let feb = date(year: 2026, month: 2, day: 3)
        let repository = fakeRepository([monthStart(feb): [makeRecord(startedAt: feb)]])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: feb)

        await store.loadInitial()
        await store.moveMonth(delta: -1)

        XCTAssertEqual(store.displayedMonth, monthStart(feb))
    }

    func testDeleteSessionSuccessRemovesOnlyAfterRepositorySucceeds() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let target = makeRecord(startedAt: jan)
        let other = makeRecord(startedAt: date(year: 2026, month: 1, day: 11))
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
        let repository = fakeRepository([monthStart(jan): [makeRecord(startedAt: jan)]])
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        await store.loadMonth()
        await store.deleteAllSessions()

        let didDeleteAll = await repository.didDeleteAllSessions()
        XCTAssertTrue(store.monthSessions.isEmpty)
        XCTAssertTrue(didDeleteAll)
    }

    func testDeleteAllSessionsInvalidatesPendingLoad() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let session = makeRecord(startedAt: jan)
        let repository = fakeRepository(
            [monthStart(jan): [session]],
            delaysByMonth: [monthStart(jan): 200_000_000]
        )
        let store = RecordsStore(repository: repository, calendar: calendar, initialMonth: jan)

        async let pendingLoad: Void = store.loadMonth()
        await Task.yield()
        await store.deleteAllSessions()
        await pendingLoad

        XCTAssertTrue(store.monthSessions.isEmpty)
    }

    func testDeleteSessionFailureKeepsList() async {
        let jan = date(year: 2026, month: 1, day: 10)
        let target = makeRecord(startedAt: jan)
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
        let janSession = makeRecord(startedAt: jan)
        let febSession = makeRecord(startedAt: feb)
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
        _ sessionsByMonth: [Date: [MealSessionRecord]],
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
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            XCTFail("Invalid fixed test date")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func monthStart(_ date: Date) -> Date {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            XCTFail("Invalid month interval")
            return date
        }
        return monthInterval.start
    }

    private func makeRecord(startedAt: Date) -> MealSessionRecord {
        let dto = ChewingSessionDTO(
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
        guard let record = MealSessionRecord(dto) else {
            XCTFail("Test record must be reportable")
            return MealSessionRecord(
                id: dto.id,
                startedAt: dto.startedAt,
                durationSec: dto.durationSec,
                reportCard: fallbackReportCard(endedAt: dto.endedAt)
            )
        }
        return record
    }

    private func fallbackReportCard(endedAt: Date) -> ReportCardModel {
        ReportCardModel(
            score: 80,
            grade: .good,
            chewCount: 300,
            totalDurationSec: 600,
            chewsPerMinute: 30,
            chewingFraction: 0.7,
            chewingSeconds: 432,
            restSeconds: 168,
            speedScore: 80,
            rhythmScore: 80,
            continuityScore: 80,
            lengthScore: 80,
            caption: nil,
            mood: .happy,
            endedAt: endedAt
        )
    }
}

private enum TestError: Error {
    case fetch
    case delete
}

private actor FakeMealSessionRepository: MealSessionRepository {
    private let calendar: Calendar
    private let sessionsByMonth: [Date: [MealSessionRecord]]
    private let fetchError: Error?
    private let deleteError: Error?
    private let deleteAllError: Error?
    private let delaysByMonth: [Date: UInt64]
    private var deletedIDs: [UUID] = []
    private var deleteAllCalled = false

    init(
        calendar: Calendar,
        sessionsByMonth: [Date: [MealSessionRecord]],
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

    func fetchSessions(since: Date, until: Date?) async throws -> [MealSessionRecord] {
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
