import XCTest
@testable import ChewChewIOS

final class StreakDetailPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_043_000)
    private let skewedDeviceNow = Date(timeIntervalSince1970: 1_924_961_400)

    func testCalendarRingStylesKeepRecordsStandardAndStreakThin() {
        XCTAssertEqual(CalendarStatusRingStyle.standard.baseLineWidth, 3)
        XCTAssertEqual(CalendarStatusRingStyle.standard.progressLineWidth, 3.2)
        XCTAssertEqual(CalendarStatusRingStyle.streak.baseLineWidth, 1.5)
        XCTAssertEqual(CalendarStatusRingStyle.streak.progressLineWidth, 2)
    }

    func testStreakSheetDefaultsShowLegendAndExplainFreezeAwards() {
        XCTAssertEqual(StreakDetailSheetPolicy.defaultDetentFraction, 0.72)
        XCTAssertEqual(FreezeAwardGuidePresentation.default.title, "프리즈는 이렇게 받아요")
        XCTAssertEqual(
            FreezeAwardGuidePresentation.default.message,
            "스트릭 7일, 30일, 100일을 처음 달성할 때마다 프리즈 1개를 받아요."
        )
        XCTAssertEqual(
            FreezeAwardGuidePresentation.default.supportingText,
            "프리즈는 최대 3개까지 보유할 수 있어요."
        )
    }

    func testLegacyDetailWithoutMonthUsesServerAsOfMonth() throws {
        let detail = try JSONDecoder().decode(
            StreakDetailDTO.self,
            from: Data(
                #"{"asOf":"2026-07-15","current":8,"longest":18,"startedOn":"2026-07-08","freezeInventory":1,"days":[]}"#.utf8
            )
        )

        XCTAssertEqual(detail.resolvedMonth, "2026-07")
        XCTAssertEqual(StreakDetailPresentation.make(detail: detail).monthTitle, "2026년 7월")
    }

    func testMakeBuildsRequestedMonthUsingServerAsOfDespiteDeviceClockSkew() {
        let detail = StreakDetailDTO(
            asOf: "2026-07-15",
            month: "2026-07",
            oldestRecordedOn: "2026-06-21",
            current: 0,
            longest: 0,
            startedOn: nil,
            freezeInventory: 0,
            days: []
        )
        let presentation = StreakDetailPresentation.make(
            detail: detail,
            now: skewedDeviceNow
        )

        XCTAssertEqual(presentation.days.count, 42)
        XCTAssertEqual(presentation.days.compactMap { $0 }.first?.dateID, "2026-07-01")
        XCTAssertEqual(presentation.days.compactMap { $0 }.last?.dateID, "2026-07-31")
        XCTAssertEqual(presentation.monthTitle, "2026년 7월")
        XCTAssertEqual(presentation.days.compactMap { $0 }.filter(\.isToday).map(\.dateID), ["2026-07-15"])
        XCTAssertEqual(presentation.day(id: "2026-07-16")?.state, .upcoming)
        XCTAssertTrue(presentation.canMovePrevious)
        XCTAssertFalse(presentation.canMoveNext)
    }

    func testMakeMapsAttendedFrozenAndMissingServerRowsWithoutChangingSummary() {
        let detail = StreakDetailDTO(
            asOf: "2026-07-15",
            month: "2026-07",
            oldestRecordedOn: "2026-06-21",
            current: 12,
            longest: 18,
            startedOn: "2026-07-02",
            freezeInventory: 2,
            days: [
                StreakDayDTO(date: "2026-07-13", state: .attended),
                StreakDayDTO(date: "2026-07-14", state: .frozen),
                StreakDayDTO(date: "2026-07-15", state: .attended)
            ]
        )

        let presentation = StreakDetailPresentation.make(detail: detail, now: now)

        XCTAssertEqual(presentation.current, 12)
        XCTAssertEqual(presentation.freezeInventory, 2)
        XCTAssertEqual(presentation.startedOnText, "7월 2일부터 이어가는 중")
        XCTAssertEqual(presentation.day(id: "2026-07-12")?.state, .missing)
        XCTAssertEqual(presentation.day(id: "2026-07-12")?.accessibilityLabel, "12일, 기록 없음")
        XCTAssertEqual(presentation.day(id: "2026-07-13")?.state, .attended)
        XCTAssertEqual(presentation.day(id: "2026-07-14")?.state, .frozen)
        XCTAssertEqual(presentation.day(id: "2026-07-15")?.state, .attended)
        XCTAssertEqual(presentation.day(id: "2026-07-12")?.ringKind, .neutral)
        XCTAssertEqual(presentation.day(id: "2026-07-13")?.ringKind, .attended)
        XCTAssertEqual(presentation.day(id: "2026-07-14")?.ringKind, .frozen)
        XCTAssertEqual(presentation.day(id: "2026-07-16")?.ringKind, .neutral)
        XCTAssertEqual(presentation.day(id: "2026-07-15")?.accessibilityIdentifier, "StreakDay-2026-07-15")
    }

    func testMakeUsesOnlyRowsInRequestedMonth() {
        let detail = StreakDetailDTO(
            asOf: "2026-07-15",
            month: "2026-06",
            oldestRecordedOn: "2026-06-01",
            current: 2,
            longest: 7,
            startedOn: nil,
            freezeInventory: 0,
            days: [
                StreakDayDTO(date: "2026-06-01", state: .frozen),
                StreakDayDTO(date: "2026-07-15", state: .attended),
                StreakDayDTO(date: "2026-07-16", state: .attended)
            ]
        )

        let presentation = StreakDetailPresentation.make(detail: detail, now: now)

        XCTAssertEqual(presentation.days.count, 42)
        XCTAssertEqual(presentation.day(id: "2026-06-01")?.state, .frozen)
        XCTAssertNil(presentation.day(id: "2026-07-01"))
        XCTAssertNil(presentation.day(id: "2026-07-16"))
        XCTAssertEqual(presentation.startedOnText, "시작일 정보 없음")
        XCTAssertFalse(presentation.canMovePrevious)
        XCTAssertTrue(presentation.canMoveNext)
    }

    func testMakeWithoutDetailPreservesOnlyKnownCacheWhileLoading() {
        let presentation = StreakDetailPresentation.make(
            detail: nil,
            cachedCurrent: 12,
            cachedFreezeInventory: 2,
            isLoading: true,
            now: now
        )

        XCTAssertEqual(presentation.current, 12)
        XCTAssertEqual(presentation.freezeInventory, 2)
        XCTAssertEqual(presentation.startedOnText, "스트릭 정보를 확인하는 중")
        XCTAssertTrue(presentation.days.compactMap { $0 }.allSatisfy { $0.state == .unknownLoading })
        XCTAssertEqual(
            presentation.day(id: "2026-07-15")?.accessibilityLabel,
            "15일, 스트릭 정보 확인 중, 오늘"
        )
    }

    func testMakeWithoutDetailUsesNeutralUnknownCopyAfterFailure() {
        let presentation = StreakDetailPresentation.make(
            detail: nil,
            cachedCurrent: 5,
            cachedFreezeInventory: 1,
            isLoading: false,
            now: now
        )

        XCTAssertEqual(presentation.current, 5)
        XCTAssertEqual(presentation.freezeInventory, 1)
        XCTAssertEqual(presentation.startedOnText, "시작일 정보 없음")
        XCTAssertTrue(presentation.days.compactMap { $0 }.allSatisfy { $0.state == .unknownUnavailable })
        XCTAssertEqual(
            presentation.day(id: "2026-07-15")?.accessibilityLabel,
            "15일, 스트릭 기록 정보 없음, 오늘"
        )
        XCTAssertTrue(presentation.showsCalendar)
        XCTAssertTrue(presentation.canMovePrevious)
        XCTAssertFalse(presentation.canMoveNext)
    }

    func testZeroStreakHidesMissingStartDateCopy() {
        let presentation = StreakDetailPresentation.make(
            detail: nil,
            cachedCurrent: 0,
            isLoading: false,
            now: now
        )

        XCTAssertEqual(presentation.current, 0)
        XCTAssertEqual(presentation.startedOnText, "")
    }

    func testUnavailableDetailUsesLocallySelectedMonthAndKeepsNavigation() {
        let presentation = StreakDetailPresentation.make(
            detail: nil,
            selectedMonth: "2026-06",
            isLoading: false,
            now: now
        )

        XCTAssertEqual(presentation.monthTitle, "2026년 6월")
        XCTAssertTrue(presentation.canMovePrevious)
        XCTAssertTrue(presentation.canMoveNext)
        XCTAssertTrue(presentation.days.compactMap { $0 }.allSatisfy { $0.state == .unknownUnavailable })
    }
}

private extension StreakDetailPresentation {
    func day(id: String) -> StreakDayPresentation? {
        days.compactMap { $0 }.first { $0.dateID == id }
    }
}
