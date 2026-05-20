import XCTest
@testable import ChewChewIOS

final class SessionScoreTests: XCTestCase {

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

    // MARK: - compute

    func testCompute_nil_when_chewsNil() {
        let dto = makeDTO(chews: nil, fraction: 0.7)
        XCTAssertNil(SessionScore.compute(dto))
    }

    func testCompute_nil_when_fractionNil() {
        let dto = makeDTO(chews: 300, fraction: nil)
        XCTAssertNil(SessionScore.compute(dto))
    }

    func testCompute_returnsScore() {
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 600)
        let score = SessionScore.compute(dto)
        XCTAssertNotNil(score)
        if let score = score {
            XCTAssertGreaterThanOrEqual(score.total, 0)
            XCTAssertLessThanOrEqual(score.total, 100)
        }
    }

    // MARK: - Grade

    func testGrade_good_when_80plus() {
        XCTAssertEqual(SessionScore.Grade.from(total: 80), .good)
        XCTAssertEqual(SessionScore.Grade.from(total: 100), .good)
        XCTAssertEqual(SessionScore.Grade.from(total: 95), .good)
    }

    func testGrade_soso_when_60to79() {
        XCTAssertEqual(SessionScore.Grade.from(total: 60), .soso)
        XCTAssertEqual(SessionScore.Grade.from(total: 79), .soso)
        XCTAssertEqual(SessionScore.Grade.from(total: 70), .soso)
    }

    func testGrade_bad_when_below60() {
        XCTAssertEqual(SessionScore.Grade.from(total: 59), .bad)
        XCTAssertEqual(SessionScore.Grade.from(total: 0), .bad)
        XCTAssertEqual(SessionScore.Grade.from(total: 30), .bad)
    }
}
