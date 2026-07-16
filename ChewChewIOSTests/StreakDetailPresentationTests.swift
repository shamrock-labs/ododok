import XCTest
@testable import ChewChewIOS

final class StreakDetailPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_043_000)
    private let skewedDeviceNow = Date(timeIntervalSince1970: 1_924_961_400)

    func testMakeBuildsFourteenDaysEndingAtServerAsOfDespiteDeviceClockSkew() {
        let detail = StreakDetailDTO(
            asOf: "2026-07-15",
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

        XCTAssertEqual(presentation.days.count, 14)
        XCTAssertEqual(presentation.days.first?.dateID, "2026-07-02")
        XCTAssertEqual(presentation.days.last?.dateID, "2026-07-15")
        XCTAssertEqual(presentation.days.last?.weekday, "수")
        XCTAssertEqual(presentation.days.filter(\.isToday).map(\.dateID), ["2026-07-15"])
    }

    func testMakeMapsAttendedFrozenAndMissingServerRowsWithoutChangingSummary() {
        let detail = StreakDetailDTO(
            asOf: "2026-07-15",
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

        let presentation = StreakDetailPresentation.make(detail: detail, hasFailed: true, now: now)

        XCTAssertEqual(presentation.current, 12)
        XCTAssertEqual(presentation.longestText, "최장 스트릭 18일")
        XCTAssertEqual(presentation.freezeInventory, 2)
        XCTAssertEqual(presentation.startedOnText, "7월 2일부터 이어가는 중")
        XCTAssertEqual(presentation.day(id: "2026-07-12")?.state, .missing)
        XCTAssertEqual(presentation.day(id: "2026-07-12")?.accessibilityLabel, "12일, 기록 없음")
        XCTAssertEqual(presentation.day(id: "2026-07-13")?.state, .attended)
        XCTAssertEqual(presentation.day(id: "2026-07-14")?.state, .frozen)
        XCTAssertEqual(presentation.day(id: "2026-07-15")?.state, .attended)
        XCTAssertEqual(presentation.day(id: "2026-07-15")?.accessibilityIdentifier, "StreakDay-2026-07-15")
        XCTAssertFalse(presentation.showsRetry)
    }

    func testMakeIgnoresServerRowsOutsideVisibleWindow() {
        let detail = StreakDetailDTO(
            asOf: "2026-07-15",
            current: 2,
            longest: 7,
            startedOn: nil,
            freezeInventory: 0,
            days: [
                StreakDayDTO(date: "2026-07-01", state: .frozen),
                StreakDayDTO(date: "2026-07-15", state: .attended),
                StreakDayDTO(date: "2026-07-16", state: .attended)
            ]
        )

        let presentation = StreakDetailPresentation.make(detail: detail, now: now)

        XCTAssertEqual(presentation.days.count, 14)
        XCTAssertNil(presentation.day(id: "2026-07-01"))
        XCTAssertNil(presentation.day(id: "2026-07-16"))
        XCTAssertEqual(presentation.startedOnText, "시작일 정보 없음")
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
        XCTAssertEqual(presentation.longestText, "최장 스트릭 —")
        XCTAssertEqual(presentation.startedOnText, "스트릭 정보를 확인하는 중")
        XCTAssertTrue(presentation.days.allSatisfy { $0.state == .unknownLoading })
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
            hasFailed: true,
            now: now
        )

        XCTAssertEqual(presentation.current, 5)
        XCTAssertEqual(presentation.freezeInventory, 1)
        XCTAssertEqual(presentation.longestText, "최장 스트릭 —")
        XCTAssertEqual(presentation.startedOnText, "시작일 정보 없음")
        XCTAssertTrue(presentation.days.allSatisfy { $0.state == .unknownUnavailable })
        XCTAssertEqual(
            presentation.day(id: "2026-07-15")?.accessibilityLabel,
            "15일, 스트릭 기록 정보 없음, 오늘"
        )
        XCTAssertTrue(presentation.showsRetry)
    }
}

private extension StreakDetailPresentation {
    func day(id: String) -> StreakDayPresentation? {
        days.first { $0.dateID == id }
    }
}
