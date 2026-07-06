import XCTest
@testable import ChewChewIOS

final class MealSessionRecordMapperTests: XCTestCase {
    func testReportableDTOCreatesRecord() {
        let startedAt = Date(timeIntervalSince1970: 1_800)
        let dto = makeDTO(startedAt: startedAt, durationSec: 600)

        let record = MealSessionRecord(dto)

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
            estimatedTotalChews: nil
        )

        XCTAssertNil(MealSessionRecord(dto))
    }

    func testShortDurationDTOReturnsNil() {
        let dto = makeDTO(durationSec: 59.9)

        XCTAssertNil(MealSessionRecord(dto))
    }

    func testSixtySecondBoundaryCreatesRecord() {
        let dto = makeDTO(durationSec: 60)

        XCTAssertNotNil(MealSessionRecord(dto))
    }

    private func makeDTO(
        startedAt: Date = Date(timeIntervalSince1970: 1_000),
        durationSec: Double = 600,
        chewingSeconds: Double? = 420,
        restSeconds: Double? = 180,
        chewingFraction: Double? = 0.7,
        estimatedTotalChews: Int? = 300
    ) -> ChewingSessionDTO {
        ChewingSessionDTO(
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
            modelVersion: "test"
        )
    }
}
