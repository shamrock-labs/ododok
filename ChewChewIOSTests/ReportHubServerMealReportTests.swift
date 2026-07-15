import XCTest
@testable import ChewChewIOS

final class ReportHubServerMealReportTests: XCTestCase {
    func testDaySnapshotUsesOnlyGeneratedServerReports() {
        let generated = makeSession(
            rawChews: 2,
            rawDuration: 31,
            report: generatedReport(totalChews: 450, duration: 900)
        )
        let unreportable = makeSession(
            rawChews: 999,
            rawDuration: 999,
            report: MealReportDTO(status: .unreportable, reason: .analysisMissing)
        )

        let snapshot = ReportHubDaySnapshot(date: generated.startedAt, sessions: [generated, unreportable])

        XCTAssertEqual(snapshot.chewCount, 450)
        XCTAssertEqual(snapshot.minutes, 15)
        XCTAssertEqual(snapshot.mealCount, 1)
    }

    func testGeneratedSessionsFiltersOutRawOnlyAndUnreportableRows() {
        let generated = makeSession(report: generatedReport(totalChews: 300, duration: 600))
        let rawOnly = makeSession(report: nil)
        let unreportable = makeSession(report: .init(status: .unreportable, reason: .sessionTooShort))

        XCTAssertEqual(
            ReportHubDaySnapshot.generatedSessions(from: [rawOnly, generated, unreportable]).map(\.id),
            [generated.id]
        )
    }

    func testDaySnapshotUsesDailyEndpointCountAndAverageScore() {
        let report = DailyReportDTO(
            date: "2026-07-15",
            timezone: "Asia/Seoul",
            mealCount: 5,
            totalEatingSeconds: 1_200,
            totalChews: 900,
            avgChewRatePerMin: 45,
            avgChewingFraction: 0.6,
            avgTotalScore: 77.6,
            meals: [],
            vsYesterday: nil
        )

        let snapshot = ReportHubDaySnapshot(date: Date(), report: report)

        XCTAssertEqual(snapshot.mealCount, 5)
        XCTAssertEqual(snapshot.avgTotalScore, 78)
        XCTAssertEqual(snapshot.avgChewCount, 180)
        XCTAssertEqual(snapshot.minutes, 4)
    }

    private func generatedReport(totalChews: Int, duration: Double) -> MealReportDTO {
        MealReportDTO(
            status: .generated, scorePolicyVersion: "legacy-ios-v1", analysisModelVersion: "server",
            totalScore: 80,
            axisScores: .init(chewingRate: 80, chewingTimeRatio: 80, totalChewCount: 80, mealDuration: 80),
            metrics: .init(chewingRatePerMin: nil, legacyMealRatePerMin: 30,
                           chewingTimeRatio: 0.7, totalChewCount: totalChews, mealDurationSec: duration),
            grade: .good,
            recommendedBaseline: .init(chewingRatePerMin: .init(target: 28), chewingTimeRatio: 0.6,
                                       totalChewCount: 300, mealDurationSec: 720)
        )
    }

    private func makeSession(
        rawChews: Int = 1,
        rawDuration: Double = 30,
        report: MealReportDTO?
    ) -> ChewingSessionDTO {
        let startedAt = Date(timeIntervalSince1970: 1_725_000_000)
        let sessionId = UUID()
        var report = report
        if report?.status == .generated, report?.sessionId == nil {
            report?.sessionId = sessionId
        }
        return ChewingSessionDTO(
            id: sessionId, deviceId: "test", startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(rawDuration), durationSec: rawDuration,
            sensorLocation: "default", sampleCount: 10, sampleRateHz: 50,
            storagePath: nil, appVersion: nil, chewingSeconds: 1, restSeconds: 29,
            chewingFraction: 0.01, estimatedTotalChews: rawChews, modelVersion: "raw",
            mealReport: report
        )
    }
}
