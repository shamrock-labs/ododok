import XCTest
@testable import ChewChewIOS

final class ReportCardModelTests: XCTestCase {

    private func makeDTO(
        chews: Int? = 300,
        fraction: Double? = 0.7,
        durationSec: Double = 600
    ) -> ChewingSessionDTO {
        ChewingSessionDTO(
            id: UUID(),
            deviceId: "test",
            startedAt: Date(),
            endedAt: Date(),
            durationSec: durationSec,
            sensorLocation: "default",
            sampleCount: 3000,
            sampleRateHz: 50,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: 432,
            restSeconds: 168,
            chewingFraction: fraction,
            estimatedTotalChews: chews,
            modelVersion: "test"
        )
    }

    // MARK: - from(_:)

    func testFrom_nil_for_unanalyzed() {
        // All analysis fields nil → from(dto) should be nil
        let dto = makeDTO(chews: nil, fraction: nil)
        XCTAssertNil(ReportCardModel.from(dto))
    }

    func testFrom_validDTO_returnsModel() {
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 600)
        let model = ReportCardModel.from(dto)
        XCTAssertNotNil(model)
        if let model = model {
            XCTAssertEqual(model.chewCount, 300)
            XCTAssertEqual(model.totalDurationSec, 600, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(model.score, 0)
            XCTAssertLessThanOrEqual(model.score, 100)
            XCTAssertGreaterThanOrEqual(model.satisfaction, 0)
            XCTAssertLessThanOrEqual(model.satisfaction, 5)
        }
    }

    func testFrom_satisfaction_in_0to5() {
        // Test various score values and verify satisfaction is always 0–5
        let testCases: [(Int, Double)] = [
            (0, 0.0),
            (100, 1.0),
            (200, 0.5),
            (300, 0.7),
            (500, 0.9),
        ]
        for (chews, fraction) in testCases {
            let dto = makeDTO(chews: chews > 0 ? chews : nil, fraction: fraction)
            if chews == 0 { continue }
            if let model = ReportCardModel.from(dto) {
                XCTAssertGreaterThanOrEqual(model.satisfaction, 0,
                    "satisfaction must be >= 0 for chews=\(chews) fraction=\(fraction)")
                XCTAssertLessThanOrEqual(model.satisfaction, 5,
                    "satisfaction must be <= 5 for chews=\(chews) fraction=\(fraction)")
            }
        }
    }
}
