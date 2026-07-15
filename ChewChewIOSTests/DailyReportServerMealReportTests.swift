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
        XCTAssertEqual(model.rateGuidance, .target(31))
        XCTAssertEqual(model.recommendedChewingFraction, 0.64)
        XCTAssertEqual(model.recommendedChewCount, 333)
        XCTAssertEqual(model.recommendedDurationSec, 777)
    }

    func testUnavailableCopyMatchesEveryKnownServerReasonAndUnknownFallback() {
        let cases: [(MealReportReasonDTO, MealReportUnavailableContent)] = [
            (
                .sessionTooShort,
                .init(
                    emoji: "⏱️",
                    title: "식사 기록이 너무 짧았어요",
                    message: "30초 이상 식사하면 리포트를 만들 수 있어요."
                )
            ),
            (
                .analysisMissing,
                .init(
                    emoji: "🎧",
                    title: "씹기 신호를 받지 못했어요",
                    message: "AirPods 연결과 센서 신호를 확인한 뒤 다시 기록해 주세요."
                )
            ),
            (
                .invalidAnalysisInput,
                .init(
                    emoji: "🔎",
                    title: "분석값을 확인하지 못했어요",
                    message: "이번 식사의 분석값이 올바르지 않아 리포트를 만들지 않았어요."
                )
            ),
            (
                .unsupportedModelVersion,
                .init(
                    emoji: "⬆️",
                    title: "아직 지원하지 않는 분석이에요",
                    message: "앱을 최신 버전으로 업데이트한 뒤 다시 확인해 주세요."
                )
            ),
        ]

        for (reason, expected) in cases {
            XCTAssertEqual(
                MealReportUnavailableContent.from(.init(status: .unreportable, reason: reason)),
                expected
            )
        }

        XCTAssertEqual(
            MealReportUnavailableContent.from(
                .init(status: .unreportable, reason: .unknown("FUTURE_REASON"))
            ),
            .init(
                emoji: "🐿️",
                title: "리포트를 준비하고 있어요",
                message: "알 수 없는 사유로 리포트를 표시할 수 없어요. 잠시 후 다시 확인해 주세요."
            )
        )
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
