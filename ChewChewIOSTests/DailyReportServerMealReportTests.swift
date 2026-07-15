import XCTest
@testable import ChewChewIOS

final class DailyReportServerMealReportTests: XCTestCase {
    func testDailyModelUsesStoredMetricsAndBaselineInsteadOfRawAnalysis() throws {
        let session = makeSession(
            rawChews: 1,
            rawDuration: 30,
            reportChews: 589,
            reportDuration: 811,
            baselineRate: 31,
            baselineRatio: 0.64,
            baselineChews: 333,
            baselineDuration: 777
        )

        let report = try XCTUnwrap(session.mealReport)
        let model = try XCTUnwrap(DailyReportModel.from(
            date: session.startedAt,
            report: DailyReportDTO(
                date: "2024-08-29",
                timezone: "Asia/Seoul",
                mealCount: 1,
                totalEatingSeconds: report.metrics?.mealDurationSec ?? 0,
                totalChews: report.metrics?.totalChewCount ?? 0,
                avgChewRatePerMin: report.metrics?.legacyMealRatePerMin,
                avgChewingFraction: report.metrics?.chewingTimeRatio,
                avgTotalScore: report.totalScore.map(Double.init),
                meals: [DailyReportMealDTO(
                    sessionId: session.id,
                    slot: "LUNCH",
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    durationSec: report.metrics?.mealDurationSec ?? 0,
                    totalChews: report.metrics?.totalChewCount,
                    chewRatePerMin: report.metrics?.legacyMealRatePerMin,
                    chewingFraction: report.metrics?.chewingTimeRatio,
                    paceBadge: "RECOMMENDED",
                    mealReport: report
                )],
                vsYesterday: nil
            ),
            previousReport: nil
        ))

        XCTAssertEqual(model.totalChews, 589)
        XCTAssertEqual(model.totalDurationSec, 811)
        XCTAssertEqual(model.avgChewingFraction, 0.97, accuracy: 0.001)
        XCTAssertEqual(model.recommendedChewsPerMinute, 31)
        XCTAssertEqual(model.recommendedChewingFraction, 0.64)
        XCTAssertEqual(model.recommendedChewCount, 333)
        XCTAssertEqual(model.recommendedDurationSec, 777)
    }

    func testUnavailableCopyIsDistinctForEveryServerReasonAndUnknownFallback() {
        let tooShort = MealReportUnavailableContent.from(.init(status: .unreportable, reason: .sessionTooShort))
        let missing = MealReportUnavailableContent.from(.init(status: .unreportable, reason: .analysisMissing))
        let invalid = MealReportUnavailableContent.from(.init(status: .unreportable, reason: .invalidAnalysisInput))
        let unknown = MealReportUnavailableContent.from(.init(status: .unknown("QUEUED")))

        XCTAssertNotEqual(tooShort, missing)
        XCTAssertNotEqual(missing, invalid)
        XCTAssertNotEqual(invalid, tooShort)
        XCTAssertTrue(tooShort.message.contains("30초"))
        XCTAssertTrue(missing.message.contains("신호"))
        XCTAssertTrue(invalid.message.contains("분석값"))
        XCTAssertTrue(unknown.title.contains("준비"))
    }

    private func makeSession(
        rawChews: Int,
        rawDuration: Double,
        reportChews: Int,
        reportDuration: Double,
        baselineRate: Double,
        baselineRatio: Double,
        baselineChews: Int,
        baselineDuration: Double
    ) -> ChewingSessionDTO {
        let startedAt = Date(timeIntervalSince1970: 1_725_000_000)
        let sessionId = UUID()
        return ChewingSessionDTO(
            id: sessionId, deviceId: "test", startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(rawDuration), durationSec: rawDuration,
            sensorLocation: "default", sampleCount: 1, sampleRateHz: 50,
            storagePath: nil, appVersion: nil, chewingSeconds: 1, restSeconds: 29,
            chewingFraction: 0.01, estimatedTotalChews: rawChews, modelVersion: "raw",
            mealReport: MealReportDTO(
                status: .generated, sessionId: sessionId,
                scorePolicyVersion: "legacy-ios-v1", analysisModelVersion: "server",
                totalScore: 71,
                axisScores: .init(chewingRate: 0, chewingTimeRatio: 100, totalChewCount: 100, mealDuration: 85),
                metrics: .init(chewingRatePerMin: nil, legacyMealRatePerMin: 43.6,
                               chewingTimeRatio: 0.97, totalChewCount: reportChews,
                               mealDurationSec: reportDuration),
                grade: .soso,
                recommendedBaseline: .init(
                    chewingRatePerMin: .init(target: baselineRate),
                    chewingTimeRatio: baselineRatio,
                    totalChewCount: baselineChews,
                    mealDurationSec: baselineDuration
                )
            )
        )
    }
}
