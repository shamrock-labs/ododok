import XCTest
@testable import ChewChewIOS

final class DailyReportContractTests: XCTestCase {
    func testDailyModelUsesServerMealCountAndAverageScore() throws {
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let first = makeMeal(startedAt: date, score: 90, chews: 300)
        let second = makeMeal(startedAt: date.addingTimeInterval(60), score: 50, chews: 500)
        let report = DailyReportDTO(
            date: "2024-08-29",
            timezone: "Asia/Seoul",
            mealCount: 7,
            totalEatingSeconds: 1_000,
            totalChews: 999,
            avgChewRatePerMin: 44,
            avgChewingFraction: 0.77,
            avgTotalScore: 61,
            meals: [first, second],
            vsYesterday: .init(mealCountDelta: 2, avgChewRatePerMinDelta: 3, totalEatingSecondsDelta: 120)
        )

        let model = try XCTUnwrap(DailyReportModel.from(date: date, report: report, previousReport: nil))

        XCTAssertEqual(model.mealCount, 7)
        XCTAssertEqual(model.dayScore, 61)
        XCTAssertEqual(model.grade, .soso)
        XCTAssertEqual(model.totalChews, 999)
        XCTAssertEqual(model.totalDurationSec, 1_000)
        XCTAssertEqual(model.avgChewsPerMinute, 44)
        XCTAssertEqual(model.avgChewingFraction, 0.77)
        XCTAssertEqual(model.sessionCount, 2)
    }

    func testDailyModelUsesStoredMealReportsForMealSummaries() throws {
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let meal = makeMeal(startedAt: date, score: 88, chews: 432)
        let report = DailyReportDTO(
            date: "2024-08-29",
            timezone: "Asia/Seoul",
            mealCount: 1,
            totalEatingSeconds: 720,
            totalChews: 432,
            avgChewRatePerMin: 36,
            avgChewingFraction: 0.6,
            avgTotalScore: 88,
            meals: [meal],
            vsYesterday: nil
        )

        let model = try XCTUnwrap(DailyReportModel.from(date: date, report: report, previousReport: nil))

        XCTAssertEqual(model.mealSummaries.first?.score, 88)
        XCTAssertEqual(model.mealSummaries.first?.chews, 432)
        XCTAssertEqual(model.mealSummaries.first?.representative.mealReport, meal.mealReport)
    }

    private func makeMeal(startedAt: Date, score: Int, chews: Int) -> DailyReportMealDTO {
        let sessionId = UUID()
        let report = MealReportDTO(
            status: .generated,
            sessionId: sessionId,
            scorePolicyVersion: "legacy-ios-v1",
            analysisModelVersion: "server",
            totalScore: score,
            axisScores: .init(chewingRate: 80, chewingTimeRatio: 70, totalChewCount: 60, mealDuration: 90),
            metrics: .init(
                chewingRatePerMin: nil,
                legacyMealRatePerMin: 36,
                chewingTimeRatio: 0.6,
                totalChewCount: chews,
                mealDurationSec: 720
            ),
            grade: score >= 80 ? .good : (score >= 60 ? .soso : .bad),
            recommendedBaseline: .init(
                chewingRatePerMin: .init(target: 28),
                chewingTimeRatio: 0.5,
                totalChewCount: 200,
                mealDurationSec: 720
            )
        )
        return DailyReportMealDTO(
            sessionId: sessionId,
            slot: "LUNCH",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(720),
            durationSec: 720,
            totalChews: chews,
            chewRatePerMin: 36,
            chewingFraction: 0.6,
            paceBadge: "RECOMMENDED",
            mealReport: report
        )
    }
}
