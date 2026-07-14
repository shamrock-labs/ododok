import XCTest
@testable import ChewChewIOS

final class MealSessionRecordMapperTests: XCTestCase {
    func testReportableDTOCreatesRecord() {
        let startedAt = Date(timeIntervalSince1970: 1_800)
        let dto = makeDTO(startedAt: startedAt, durationSec: 600)

        let record = MealSessionRecordMapper.map(dto)

        XCTAssertEqual(record?.id, dto.id)
        XCTAssertEqual(record?.startedAt, startedAt)
        XCTAssertEqual(record?.durationSec, 600)
        XCTAssertEqual(record?.reportCard.totalDurationSec, 600)
    }

    func testUnreportableDTOWithMissingAnalysisReturnsNil() {
        let dto = makeDTO(
            chewingSeconds: nil,
            restSeconds: nil,
            chewingFraction: nil,
            estimatedTotalChews: nil,
            mealReport: MealReportDTO(status: .unreportable, reason: .analysisMissing)
        )

        XCTAssertNil(MealSessionRecordMapper.map(dto))
        XCTAssertFalse(MealSessionReportability.isReportable(dto))
    }

    func testGeneratedReportDoesNotReapplyLocalShortDurationRule() {
        let dto = makeDTO(durationSec: 29.9)

        XCTAssertNotNil(MealSessionRecordMapper.map(dto))
        XCTAssertTrue(MealSessionReportability.isReportable(dto))
    }

    func testThirtySecondBoundaryCreatesRecord() {
        let dto = makeDTO(durationSec: 30)

        XCTAssertNotNil(MealSessionRecordMapper.map(dto))
        XCTAssertTrue(MealSessionReportability.isReportable(dto))
    }

    private func makeDTO(
        startedAt: Date = Date(timeIntervalSince1970: 1_000),
        durationSec: Double = 600,
        chewingSeconds: Double? = 420,
        restSeconds: Double? = 180,
        chewingFraction: Double? = 0.7,
        estimatedTotalChews: Int? = 300,
        mealReport: MealReportDTO? = nil
    ) -> ChewingSessionDTO {
        let report = mealReport ?? MealReportDTO(
            status: .generated,
            scorePolicyVersion: "legacy-ios-v1",
            analysisModelVersion: "test",
            totalScore: 80,
            axisScores: MealReportAxisScoresDTO(
                chewingRate: 80,
                chewingTimeRatio: 80,
                totalChewCount: 80,
                mealDuration: 80
            ),
            metrics: MealReportMetricsDTO(
                chewingRatePerMin: nil,
                legacyMealRatePerMin: 30,
                chewingTimeRatio: 0.7,
                totalChewCount: 300,
                mealDurationSec: durationSec
            ),
            grade: .good,
            recommendedBaseline: MealReportRecommendedBaselineDTO(
                chewingRatePerMin: MealReportTargetDTO(target: 28),
                chewingTimeRatio: 0.5,
                totalChewCount: 200,
                mealDurationSec: 720
            )
        )
        return ChewingSessionDTO(
            id: UUID(),
            deviceId: "test-device",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(durationSec),
            durationSec: durationSec,
            sensorLocation: "default",
            sampleCount: 3_000,
            sampleRateHz: 50,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewingFraction: chewingFraction,
            estimatedTotalChews: estimatedTotalChews,
            modelVersion: "test",
            mealReport: report
        )
    }
}
