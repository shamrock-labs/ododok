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

    // MARK: - 60초 가드

    func testFrom_nil_when_durationSec_59() {
        // 59초 세션 — 분석 필드가 있어도 nil 반환해야 함
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 59)
        XCTAssertNil(ReportCardModel.from(dto))
    }

    func testFrom_nonNil_when_durationSec_60() {
        // 경계: 60초 세션 — non-nil이어야 함
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 60)
        XCTAssertNotNil(ReportCardModel.from(dto))
    }

    // MARK: - mood 매핑

    func testFrom_mood_good_isChampOrHappy() {
        // good 등급(score ≥ 80) → .champ 또는 .happy
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 720)
        // 여러 번 반복해 두 값 모두 허용됨을 확인 (결정론적으로 둘 중 하나)
        for _ in 0..<20 {
            if let model = ReportCardModel.from(dto), model.grade == .good {
                XCTAssertTrue(model.mood == .champ || model.mood == .happy,
                    "good 등급 mood는 .champ 또는 .happy여야 함, got \(model.mood)")
            }
        }
    }

    func testFrom_mood_bad_isSleepy() {
        // bad 등급(score < 60) → .sleepy
        // 분당 0회에 가까운 값으로 bad 유도: chews 0, fraction 0.0
        let dto = makeDTO(chews: 0, fraction: 0.0, durationSec: 60)
        if let model = ReportCardModel.from(dto) {
            if model.grade == .bad {
                XCTAssertEqual(model.mood, .sleepy)
            }
        }
    }

    func testFrom_mood_soso_isPuffy() {
        // soso 등급(60 ≤ score < 80) → .puffy
        // fraction=0.5, chews=150 → 점수 중간대 유도
        let dto = makeDTO(chews: 150, fraction: 0.5, durationSec: 600)
        if let model = ReportCardModel.from(dto) {
            if model.grade == .soso {
                XCTAssertEqual(model.mood, .puffy)
            }
        }
    }

    // MARK: - CaptionPool

    func testCaptionPool_good_nonNil() {
        let caption = CaptionPool.report(for: .good)
        XCTAssertNotNil(caption)
        XCTAssertFalse(caption?.isEmpty ?? true)
    }

    func testCaptionPool_soso_nonNil() {
        let caption = CaptionPool.report(for: .soso)
        XCTAssertNotNil(caption)
        XCTAssertFalse(caption?.isEmpty ?? true)
    }

    func testCaptionPool_bad_nonNil() {
        let caption = CaptionPool.report(for: .bad)
        XCTAssertNotNil(caption)
        XCTAssertFalse(caption?.isEmpty ?? true)
    }

    func testFrom_caption_nonNil_for_valid_session() {
        // 유효 세션에서 caption이 채워져야 함
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 600)
        let model = ReportCardModel.from(dto)
        XCTAssertNotNil(model?.caption)
    }

    // MARK: - scoreCountUpValue

    func testScoreCountUp_progress0_returns0() {
        XCTAssertEqual(scoreCountUpValue(progress: 0, target: 85), 0)
    }

    func testScoreCountUp_progress1_returnsTarget() {
        XCTAssertEqual(scoreCountUpValue(progress: 1, target: 85), 85)
    }

    func testScoreCountUp_progress0_5_returnsHalfRounded() {
        // 0.5 * 85 = 42.5 → 반올림 43
        XCTAssertEqual(scoreCountUpValue(progress: 0.5, target: 85), 43)
    }

    func testScoreCountUp_clamps_above1() {
        XCTAssertEqual(scoreCountUpValue(progress: 2.0, target: 100), 100)
    }

    func testScoreCountUp_clamps_below0() {
        XCTAssertEqual(scoreCountUpValue(progress: -0.5, target: 100), 0)
    }
}
