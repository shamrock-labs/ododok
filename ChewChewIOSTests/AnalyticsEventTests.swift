import XCTest
@testable import ChewChewIOS

final class AnalyticsEventTests: XCTestCase {
    func testReportDateSelectedEventSchema() {
        let event = AnalyticsEvent.reportDateSelected(
            source: "calendar",
            selectedDate: "2026-06-30",
            daysFromToday: 0,
            mealCount: 2
        )

        XCTAssertEqual(event.name, "report_date_selected")
        XCTAssertEqual(event.properties["source"] as? String, "calendar")
        XCTAssertEqual(event.properties["selected_date"] as? String, "2026-06-30")
        XCTAssertEqual(event.properties["days_from_today"] as? Int, 0)
        XCTAssertEqual(event.properties["meal_count"] as? Int, 2)
    }

    func testDailyReportOpenedOmitsMissingScoreFields() {
        let event = AnalyticsEvent.dailyReportOpened(
            selectedDate: "2026-06-30",
            daysFromToday: 0,
            mealCount: 0,
            sessionCount: 0,
            dayScore: nil,
            grade: nil
        )

        XCTAssertEqual(event.name, "daily_report_opened")
        XCTAssertNil(event.properties["day_score"])
        XCTAssertNil(event.properties["grade"])
        XCTAssertEqual(event.properties["session_count"] as? Int, 0)
    }

    func testMealReportOpenedIncludesOptionalAnalysisFieldsWhenPresent() {
        let event = AnalyticsEvent.mealReportOpened(
            source: "report_hub",
            selectedDate: "2026-06-30",
            daysFromToday: 0,
            mealSlot: "lunch",
            score: 84,
            estimatedTotalChews: 432,
            durationSec: 720
        )

        XCTAssertEqual(event.name, "meal_report_opened")
        XCTAssertEqual(event.properties["source"] as? String, "report_hub")
        XCTAssertEqual(event.properties["meal_slot"] as? String, "lunch")
        XCTAssertEqual(event.properties["score"] as? Int, 84)
        XCTAssertEqual(event.properties["estimated_total_chews"] as? Int, 432)
        XCTAssertEqual(event.properties["duration_sec"] as? Int, 720)
    }
}
