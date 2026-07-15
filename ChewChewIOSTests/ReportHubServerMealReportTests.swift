import XCTest
@testable import ChewChewIOS

final class ReportHubServerMealReportTests: XCTestCase {
    @MainActor
    func testDailyReportSelectionIgnoresAStalePreviousReportFromAnOlderDate() async throws {
        let loader = DailyReportSelectionLoader()
        let firstSelection = loader.beginSelection()
        let firstCurrent = report(date: "2026-07-14", score: 14)
        let firstPrevious = report(date: "2026-07-13", score: 13)
        let secondCurrent = report(date: "2026-07-15", score: 15)
        let secondPrevious = report(date: "2026-07-14", score: 140)
        let firstPreviousGate = AsyncReportGate()

        let staleLoad = Task { @MainActor in
            await loader.load(
                selectionID: firstSelection,
                currentDate: "2026-07-14",
                previousDate: "2026-07-13"
            ) { date in
                if date == "2026-07-13" { return try await firstPreviousGate.value() }
                return firstCurrent
            }
        }

        let secondSelection = loader.beginSelection()
        await loader.load(
            selectionID: secondSelection,
            currentDate: "2026-07-15",
            previousDate: "2026-07-14"
        ) { date in
            date == "2026-07-15" ? secondCurrent : secondPrevious
        }
        await firstPreviousGate.resume(returning: firstPrevious)
        await staleLoad.value

        XCTAssertEqual(loader.currentReport?.date, "2026-07-15")
        XCTAssertEqual(loader.previousReport?.avgTotalScore, 140)
    }

    @MainActor
    func testDailyReportSelectionExposesNonAuthFetchFailureMessage() async {
        let loader = DailyReportSelectionLoader()
        let selection = loader.beginSelection()

        await loader.load(
            selectionID: selection,
            currentDate: "2026-07-15",
            previousDate: "2026-07-14"
        ) { _ in
            throw RemoteStoreError.offline
        }

        XCTAssertEqual(loader.errorMessage, RemoteStoreError.offline.userMessage)
    }

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

    func testGeneratedSessionsPreserveMixedPolicyServerSnapshots() throws {
        let legacyAxes = MealReportAxisScoresDTO(
            chewingRate: 11,
            chewingTimeRatio: 22,
            totalChewCount: 33,
            mealDuration: 44
        )
        let v1Axes = MealReportAxisScoresDTO(
            chewingRate: 91,
            chewingTimeRatio: 82,
            totalChewCount: 73,
            mealDuration: 64
        )
        let legacy = makeSession(report: generatedReport(
            policy: "legacy-ios-v1",
            score: 41,
            axes: legacyAxes,
            totalChews: 300,
            duration: 600
        ))
        let v1 = makeSession(report: generatedReport(
            policy: "meal-score-v1",
            score: 93,
            axes: v1Axes,
            totalChews: 420,
            duration: 720
        ))

        let selected = ReportHubDaySnapshot.generatedSessions(from: [legacy, v1])
        let selectedReports = try selected.map { try XCTUnwrap($0.mealReport) }

        XCTAssertEqual(selected.map(\.id), [legacy.id, v1.id])
        XCTAssertEqual(selectedReports.map(\.scorePolicyVersion), ["legacy-ios-v1", "meal-score-v1"])
        XCTAssertEqual(selectedReports.map(\.totalScore), [41, 93])
        XCTAssertEqual(selectedReports.map(\.axisScores), [legacyAxes, v1Axes])
        XCTAssertNil(selectedReports[1].metrics?.legacyMealRatePerMin)
        XCTAssertTrue(MealSessionReportability.isReportable(v1))
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

    private func generatedReport(
        policy: String = "legacy-ios-v1",
        score: Int = 80,
        axes: MealReportAxisScoresDTO = .init(
            chewingRate: 80,
            chewingTimeRatio: 80,
            totalChewCount: 80,
            mealDuration: 80
        ),
        totalChews: Int,
        duration: Double
    ) -> MealReportDTO {
        let isV1 = policy == "meal-score-v1"
        return MealReportDTO(
            status: .generated, scorePolicyVersion: policy, analysisModelVersion: "server",
            totalScore: score,
            axisScores: axes,
            metrics: .init(chewingRatePerMin: isV1 ? 100 : nil, legacyMealRatePerMin: isV1 ? nil : 30,
                           chewingTimeRatio: 0.7, totalChewCount: totalChews, mealDurationSec: duration),
            grade: .good,
            recommendedBaseline: .init(
                chewingRatePerMin: isV1
                    ? .init(target: nil, min: 56, max: 130)
                    : .init(target: 28),
                chewingTimeRatio: 0.6,
                                       totalChewCount: 300, mealDurationSec: 720)
        )
    }

    private func report(date: String, score: Double) -> DailyReportDTO {
        DailyReportDTO(
            date: date,
            timezone: "Asia/Seoul",
            mealCount: 0,
            totalEatingSeconds: 0,
            totalChews: 0,
            avgChewRatePerMin: nil,
            avgChewingFraction: nil,
            avgTotalScore: score,
            meals: [],
            vsYesterday: nil
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

private actor AsyncReportGate {
    private var continuation: CheckedContinuation<DailyReportDTO, Error>?
    private var pendingReport: DailyReportDTO?

    func value() async throws -> DailyReportDTO {
        if let pendingReport {
            self.pendingReport = nil
            return pendingReport
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func resume(returning report: DailyReportDTO) {
        if let continuation {
            continuation.resume(returning: report)
            self.continuation = nil
        } else {
            pendingReport = report
        }
    }
}
