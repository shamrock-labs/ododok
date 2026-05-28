import XCTest

@MainActor
final class CalendarUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testTracking_emptyState() {
        app.launchArguments = ["-resetState", "-skipOnboarding", "-startTab", "track", "-useNoopRemote"]
        app.launch()

        // "오늘의 식사 기록" header
        XCTAssert(app.staticTexts["오늘의 식사 기록"].waitForExistence(timeout: 10))

        // "0회" meal count badge
        XCTAssert(app.staticTexts["0회"].waitForExistence(timeout: 5))

        // Empty state message
        XCTAssert(app.staticTexts["오늘은 아직 식사 전이에요"].waitForExistence(timeout: 5))
    }

    func testTracking_calendarHeader() {
        app.launchArguments = ["-resetState", "-skipOnboarding", "-startTab", "track", "-useNoopRemote"]
        app.launch()

        // "식사 캘린더" section header
        XCTAssert(app.staticTexts["식사 캘린더"].waitForExistence(timeout: 10))

        // Year/month text should exist (e.g. "2026년 5월")
        // We look for any static text matching the year pattern
        let yearMonthPredicate = NSPredicate(format: "label CONTAINS '년'")
        let yearMonthText = app.staticTexts.matching(yearMonthPredicate).firstMatch
        XCTAssert(yearMonthText.waitForExistence(timeout: 5),
            "Expected year/month text (e.g. '2026년 5월') to be visible in calendar")
    }
}
