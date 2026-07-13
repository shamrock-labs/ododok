import XCTest
@testable import ChewChewIOS

final class ReportCardModelTests: XCTestCase {

    private func makeDTO(
        chews: Int? = 300,
        fraction: Double? = 0.7,
        durationSec: Double = 600,
        chewingTimeline: String? = nil
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
            modelVersion: "test",
            chewingTimeline: chewingTimeline
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
        }
    }

    func testFrom_chewingTimeline_mapsToCompressedSegments() {
        let dto = makeDTO(chewingTimeline: "111001")
        let model = ReportCardModel.from(dto)

        XCTAssertEqual(model?.chewRestSegments, [
            ReportCardModel.ChewRestSegment(isChewing: true, durationSec: 3),
            ReportCardModel.ChewRestSegment(isChewing: false, durationSec: 2),
            ReportCardModel.ChewRestSegment(isChewing: true, durationSec: 1),
        ])
    }

    func testFrom_score_in_0to100() {
        // 다양한 입력에서 score가 항상 0~100 범위인지 확인
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
                XCTAssertGreaterThanOrEqual(model.score, 0,
                    "score must be >= 0 for chews=\(chews) fraction=\(fraction)")
                XCTAssertLessThanOrEqual(model.score, 100,
                    "score must be <= 100 for chews=\(chews) fraction=\(fraction)")
            }
        }
    }

    // MARK: - 30초 가드

    func testFrom_nil_when_durationSec_29() {
        // 29초 세션 — 분석 필드가 있어도 nil 반환해야 함
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 29)
        XCTAssertNil(ReportCardModel.from(dto))
    }

    func testFrom_nonNil_when_durationSec_30() {
        // 경계: 30초 세션 — non-nil이어야 함
        let dto = makeDTO(chews: 300, fraction: 0.7, durationSec: 30)
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

    // MARK: - ChewRestSegment.dominantRuns

    private func mkSeg(_ chewing: Bool, _ durationSec: Double) -> ReportCardModel.ChewRestSegment {
        ReportCardModel.ChewRestSegment(isChewing: chewing, durationSec: durationSec)
    }

    func testDominantRuns_emptyOrZeroColumns_returnsEmpty() {
        XCTAssertTrue(ReportCardModel.ChewRestSegment.dominantRuns([], total: 0, columnCount: 10).isEmpty)
        XCTAssertTrue(ReportCardModel.ChewRestSegment.dominantRuns([mkSeg(true, 5)], total: 5, columnCount: 0).isEmpty)
    }

    func testDominantRuns_allChewing_singleFullRun() {
        let runs = ReportCardModel.ChewRestSegment.dominantRuns([mkSeg(true, 10)], total: 10, columnCount: 4)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.isChewing, true)
        XCTAssertEqual(runs.first?.columns, 4)
    }

    func testDominantRuns_majorityVotePerColumn() {
        // 씹기 1초 + 쉬기 3초, 2칸(칸당 2초): 0번 칸 타이(>=)→씹기, 1번 칸 전부 쉬기
        let runs = ReportCardModel.ChewRestSegment.dominantRuns([mkSeg(true, 1), mkSeg(false, 3)], total: 4, columnCount: 2)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].isChewing, true)
        XCTAssertEqual(runs[0].columns, 1)
        XCTAssertEqual(runs[1].isChewing, false)
        XCTAssertEqual(runs[1].columns, 1)
    }

    func testDominantRuns_mergesAdjacentSameState() {
        let runs = ReportCardModel.ChewRestSegment.dominantRuns([mkSeg(false, 9)], total: 9, columnCount: 3)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].isChewing, false)
        XCTAssertEqual(runs[0].columns, 3)
    }

    func testDominantRuns_shortPulseDropsInLongColumn() {
        // 칸당 3초인데 씹기 펄스 1초 → 다수결에서 탈락(알려진 트레이드오프).
        let runs = ReportCardModel.ChewRestSegment.dominantRuns(
            [mkSeg(false, 4), mkSeg(true, 1), mkSeg(false, 4)], total: 9, columnCount: 3
        )
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].isChewing, false)
        XCTAssertEqual(runs[0].columns, 3)
    }

    func testDominantRuns_columnCountIsPreserved() {
        let runs = ReportCardModel.ChewRestSegment.dominantRuns([mkSeg(true, 5), mkSeg(false, 5)], total: 10, columnCount: 7)
        XCTAssertEqual(runs.reduce(0) { $0 + $1.columns }, 7)
    }
}
