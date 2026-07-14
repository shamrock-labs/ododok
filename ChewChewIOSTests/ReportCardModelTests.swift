import XCTest
@testable import ChewChewIOS

final class ReportCardModelTests: XCTestCase {

    private func makeDTO(
        chews: Int? = 300,
        fraction: Double? = 0.7,
        durationSec: Double = 600,
        chewingSeconds: Double? = 432,
        restSeconds: Double? = 168,
        chewingTimeline: String? = nil,
        mealReport: MealReportDTO? = nil,
        includesDefaultReport: Bool = true
    ) -> ChewingSessionDTO {
        let report = mealReport ?? (includesDefaultReport ? makeGeneratedReport() : nil)
        return ChewingSessionDTO(
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
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewingFraction: fraction,
            estimatedTotalChews: chews,
            modelVersion: "test",
            chewingTimeline: chewingTimeline,
            mealReport: report
        )
    }

    private func makeGeneratedReport(
        status: MealReportStatusDTO = .generated,
        totalScore: Int? = 71,
        axisScores: MealReportAxisScoresDTO? = .init(
            chewingRate: 0,
            chewingTimeRatio: 100,
            totalChewCount: 100,
            mealDuration: 85
        ),
        metrics: MealReportMetricsDTO? = .init(
            chewingRatePerMin: nil,
            legacyMealRatePerMin: 43.6,
            chewingTimeRatio: 0.97,
            totalChewCount: 589,
            mealDurationSec: 811
        ),
        grade: MealReportGradeDTO? = .soso,
        recommendedBaseline: MealReportRecommendedBaselineDTO? = .init(
            chewingRatePerMin: .init(target: 31.5),
            chewingTimeRatio: 0.63,
            totalChewCount: 257,
            mealDurationSec: 845
        ),
        reason: MealReportReasonDTO? = nil
    ) -> MealReportDTO {
        MealReportDTO(
            status: status,
            reason: reason,
            scorePolicyVersion: "legacy-ios-v1",
            analysisModelVersion: "test",
            totalScore: totalScore,
            axisScores: axisScores,
            metrics: metrics,
            grade: grade,
            recommendedBaseline: recommendedBaseline
        )
    }

    // MARK: - from(_:)

    func testFrom_nil_when_mealReport_is_missing() {
        let dto = makeDTO(chews: 300, fraction: 0.7, includesDefaultReport: false)
        XCTAssertNil(ReportCardModel.from(dto))
    }

    func testFrom_generatedReport_usesServerSnapshot_asSourceOfTruth() {
        // Raw session values deliberately disagree with the stored server snapshot.
        let dto = makeDTO(
            chews: 12,
            fraction: 0.1,
            durationSec: 40,
            chewingSeconds: 1,
            restSeconds: 39,
            chewingTimeline: "111001"
        )
        let model = ReportCardModel.from(dto)

        XCTAssertEqual(model?.score, 71)
        XCTAssertEqual(model?.speedScore, 0)
        XCTAssertEqual(model?.rhythmScore, 100)
        XCTAssertEqual(model?.continuityScore, 100)
        XCTAssertEqual(model?.lengthScore, 85)
        XCTAssertEqual(model?.grade, .soso)
        XCTAssertEqual(model?.chewsPerMinute ?? -1, 43.6, accuracy: 0.001)
        XCTAssertEqual(model?.chewingFraction ?? -1, 0.97, accuracy: 0.001)
        XCTAssertEqual(model?.chewCount, 589)
        XCTAssertEqual(model?.totalDurationSec ?? -1, 811, accuracy: 0.001)
        XCTAssertEqual(model?.recommendedChewsPerMinute ?? -1, 31.5, accuracy: 0.001)
        XCTAssertEqual(model?.recommendedChewingFraction ?? -1, 0.63, accuracy: 0.001)
        XCTAssertEqual(model?.recommendedChewCount, 257)
        XCTAssertEqual(model?.recommendedDurationSec ?? -1, 845, accuracy: 0.001)
        XCTAssertEqual(model?.chewingSeconds ?? -1, 811 * 0.97, accuracy: 0.001)
        XCTAssertEqual(model?.restSeconds ?? -1, 811 * 0.03, accuracy: 0.001)
        XCTAssertEqual(model?.chewRestSegments, [])
    }

    func testFrom_unreportableReport_returnsNil() {
        let report = makeGeneratedReport(status: .unreportable, reason: .sessionTooShort)
        XCTAssertNil(ReportCardModel.from(makeDTO(mealReport: report)))
    }

    func testFrom_unknownStatusOrGrade_returnsNil() {
        XCTAssertNil(ReportCardModel.from(makeDTO(mealReport: makeGeneratedReport(status: .unknown("FUTURE")))))
        XCTAssertNil(ReportCardModel.from(makeDTO(mealReport: makeGeneratedReport(grade: .unknown("excellent")))))
    }

    func testFrom_generatedReport_withIncompletePayload_returnsNil() {
        XCTAssertNil(ReportCardModel.from(makeDTO(mealReport: makeGeneratedReport(totalScore: nil))))
        XCTAssertNil(ReportCardModel.from(makeDTO(mealReport: makeGeneratedReport(recommendedBaseline: nil))))
    }

    func testFrom_bothRawDurationsMissing_derivesMeaningfulDurationsFromReportMetrics() {
        let model = ReportCardModel.from(makeDTO(chewingSeconds: nil, restSeconds: nil))

        XCTAssertEqual(model?.chewingSeconds ?? -1, 811 * 0.97, accuracy: 0.001)
        XCTAssertEqual(model?.restSeconds ?? -1, 811 * 0.03, accuracy: 0.001)
        XCTAssertEqual((model?.chewingSeconds ?? 0) + (model?.restSeconds ?? 0), 811, accuracy: 0.001)
    }

    func testFrom_onlyRawChewingDurationPresent_ignoresItAndUsesReportMetrics() {
        let model = ReportCardModel.from(makeDTO(chewingSeconds: 123, restSeconds: nil))

        XCTAssertEqual(model?.chewingSeconds ?? -1, 811 * 0.97, accuracy: 0.001)
        XCTAssertEqual(model?.restSeconds ?? -1, 811 * 0.03, accuracy: 0.001)
    }

    func testFrom_onlyRawRestDurationPresent_ignoresItAndUsesReportMetrics() {
        let model = ReportCardModel.from(makeDTO(chewingSeconds: nil, restSeconds: 45))

        XCTAssertEqual(model?.chewingSeconds ?? -1, 811 * 0.97, accuracy: 0.001)
        XCTAssertEqual(model?.restSeconds ?? -1, 811 * 0.03, accuracy: 0.001)
    }

    func testFrom_missingRawDurations_clampsReportRatioBeforeDerivingDurations() {
        let metrics = MealReportMetricsDTO(
            chewingRatePerMin: nil,
            legacyMealRatePerMin: 43.6,
            chewingTimeRatio: 1.4,
            totalChewCount: 589,
            mealDurationSec: 811
        )
        let model = ReportCardModel.from(makeDTO(
            chewingSeconds: nil,
            restSeconds: nil,
            mealReport: makeGeneratedReport(metrics: metrics)
        ))

        XCTAssertEqual(model?.chewingSeconds, 811)
        XCTAssertEqual(model?.restSeconds, 0)
    }

    func testFrom_rawChewingTimeline_omitsSegmentsUntilServerSnapshotsTimeline() {
        let dto = makeDTO(chewingTimeline: "111001")
        let model = ReportCardModel.from(dto)

        XCTAssertEqual(model?.chewRestSegments, [])
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

    func testFrom_generatedReport_doesNotReapplyLocalDurationGuard() {
        XCTAssertNotNil(ReportCardModel.from(makeDTO(durationSec: 29)))
    }

    // MARK: - mood 매핑

    func testFrom_mood_good_isChampOrHappy() {
        // good 등급(score ≥ 80) → .champ 또는 .happy
        let report = makeGeneratedReport(totalScore: 92, grade: .good)
        let dto = makeDTO(mealReport: report)
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
        let dto = makeDTO(mealReport: makeGeneratedReport(totalScore: 42, grade: .bad))
        if let model = ReportCardModel.from(dto) {
            if model.grade == .bad {
                XCTAssertEqual(model.mood, .sleepy)
            }
        }
    }

    func testFrom_mood_soso_isPuffy() {
        // soso 등급(60 ≤ score < 80) → .puffy
        let dto = makeDTO(mealReport: makeGeneratedReport(totalScore: 71, grade: .soso))
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

    func testRecommendedChewsPerMinuteFormatter_preservesFractionAndOmitsZeroDecimal() {
        XCTAssertEqual(formatRecommendedChewsPerMinute(31.5), "31.5")
        XCTAssertEqual(formatRecommendedChewsPerMinute(28), "28")
    }

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
