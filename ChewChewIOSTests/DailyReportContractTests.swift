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
        XCTAssertEqual(model.rateGuidance, .target(28))
        XCTAssertEqual(model.rateGuidance.displayText, "28")
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

    func testDailyModelDoesNotInferSignalTrustFromFabricatedSessionMetadata() throws {
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

        XCTAssertEqual(model.trust.badge, "저장 리포트")
        XCTAssertFalse(model.trust.badge.contains("신호"))
    }

    func testDailyMealSelectionPreservesMixedPolicyServerSnapshots() throws {
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let legacyAxes = MealReportAxisScoresDTO(
            chewingRate: 12,
            chewingTimeRatio: 23,
            totalChewCount: 34,
            mealDuration: 45
        )
        let v1Axes = MealReportAxisScoresDTO(
            chewingRate: 96,
            chewingTimeRatio: 87,
            totalChewCount: 78,
            mealDuration: 69
        )
        let meals = [
            makeMeal(
                startedAt: date,
                slot: "LUNCH",
                policy: "legacy-ios-v1",
                score: 43,
                axes: legacyAxes,
                chews: 300
            ),
            makeMeal(
                startedAt: date.addingTimeInterval(60),
                slot: "DINNER",
                policy: "meal-score-v1",
                score: 94,
                axes: v1Axes,
                chews: 420
            ),
        ]

        let report = DailyReportDTO(
            date: "2024-08-29",
            timezone: "Asia/Seoul",
            mealCount: 2,
            totalEatingSeconds: 1_440,
            totalChews: 720,
            avgChewRatePerMin: 68,
            avgChewingFraction: 0.6,
            avgTotalScore: 68.5,
            meals: meals,
            vsYesterday: nil
        )

        let model = try XCTUnwrap(DailyReportModel.from(
            date: date,
            report: report,
            previousReport: nil
        ))
        let selectedReports = try model.mealSummaries.map {
            try XCTUnwrap($0.representative.mealReport)
        }

        XCTAssertEqual(selectedReports.map(\.scorePolicyVersion), ["legacy-ios-v1", "meal-score-v1"])
        XCTAssertEqual(selectedReports.map(\.totalScore), [43, 94])
        XCTAssertEqual(selectedReports.map(\.axisScores), [legacyAxes, v1Axes])
        XCTAssertEqual(model.rateGuidance, .perMeal)
        XCTAssertEqual(model.rateGuidance.displayText, "끼니별 기준")
        XCTAssertEqual(model.tomorrowGoal, "내일은 각 끼니 리포트의 권장 속도 기준을 확인해봐요.")
        XCTAssertNil(selectedReports[1].metrics?.legacyMealRatePerMin)
        XCTAssertTrue(MealSessionReportability.isReportable(meals[1].session))
    }

    func testDailyModelSupportsAllV1ReportsWithStoredRangeAndTotals() throws {
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let meals = [
            makeMeal(
                startedAt: date,
                slot: "LUNCH",
                policy: "meal-score-v1",
                score: 61,
                axes: .init(
                    chewingRate: 10,
                    chewingTimeRatio: 80,
                    totalChewCount: 80,
                    mealDuration: 80
                ),
                chews: 300
            ),
            makeMeal(
                startedAt: date.addingTimeInterval(60),
                slot: "DINNER",
                policy: "meal-score-v1",
                score: 77,
                axes: .init(
                    chewingRate: 10,
                    chewingTimeRatio: 80,
                    totalChewCount: 80,
                    mealDuration: 80
                ),
                chews: 420
            ),
        ]
        let report = DailyReportDTO(
            date: "2024-08-29",
            timezone: "Asia/Seoul",
            mealCount: 2,
            totalEatingSeconds: 1_440,
            totalChews: 720,
            avgChewRatePerMin: 100,
            avgChewingFraction: 0.6,
            avgTotalScore: 69,
            meals: meals,
            vsYesterday: nil
        )

        let model = try XCTUnwrap(DailyReportModel.from(
            date: date,
            report: report,
            previousReport: nil
        ))

        XCTAssertEqual(model.rateGuidance, .range(min: 56, max: 130))
        XCTAssertEqual(model.rateGuidance.displayText, "56~130")
        XCTAssertEqual(model.tomorrowGoal, "내일은 첫 5분 동안 분당 56~130회 범위를 의식해봐요.")
        XCTAssertEqual(model.mealCount, 2)
        XCTAssertEqual(model.totalChews, 720)
        XCTAssertEqual(model.totalDurationSec, 1_440)
        XCTAssertEqual(model.dayScore, 69)
    }

    private func makeMeal(
        startedAt: Date,
        slot: String = "LUNCH",
        policy: String = "legacy-ios-v1",
        score: Int,
        axes: MealReportAxisScoresDTO = .init(
            chewingRate: 80,
            chewingTimeRatio: 70,
            totalChewCount: 60,
            mealDuration: 90
        ),
        chews: Int
    ) -> DailyReportMealDTO {
        let sessionId = UUID()
        let isV1 = policy == "meal-score-v1"
        let report = MealReportDTO(
            status: .generated,
            sessionId: sessionId,
            scorePolicyVersion: policy,
            analysisModelVersion: "server",
            totalScore: score,
            axisScores: axes,
            metrics: .init(
                chewingRatePerMin: isV1 ? 100 : nil,
                legacyMealRatePerMin: isV1 ? nil : 36,
                chewingTimeRatio: 0.6,
                totalChewCount: chews,
                mealDurationSec: 720
            ),
            grade: score >= 80 ? .good : (score >= 60 ? .soso : .bad),
            recommendedBaseline: .init(
                chewingRatePerMin: isV1
                    ? .init(target: nil, min: 56, max: 130)
                    : .init(target: 28),
                chewingTimeRatio: 0.5,
                totalChewCount: 200,
                mealDurationSec: 720
            )
        )
        return DailyReportMealDTO(
            sessionId: sessionId,
            slot: slot,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(720),
            durationSec: 720,
            totalChews: chews,
            chewRatePerMin: isV1 ? 100 : 36,
            chewingFraction: 0.6,
            paceBadge: "RECOMMENDED",
            mealReport: report
        )
    }
}
