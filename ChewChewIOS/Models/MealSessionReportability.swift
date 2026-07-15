import Foundation

/// 서버가 저장한 식사 리포트의 생성 여부를 판단하는 단일 정본.
enum MealSessionReportability {
    /// 측정 진행 중 안내에만 쓰는 서버 정책과 공유된 최소 식사 길이.
    /// 저장된 세션의 리포트 가능 여부는 이 값으로 재판정하지 않는다.
    static let minDurationSec: Double = 30

    static func isReportable(_ dto: ChewingSessionDTO) -> Bool {
        completeGeneratedReport(dto.mealReport, sessionId: dto.id) != nil
    }

    static func completeGeneratedReport(
        _ report: MealReportDTO?,
        sessionId: UUID
    ) -> MealReportDTO? {
        guard let report,
              report.status == .generated,
              report.reason == nil,
              report.sessionId == sessionId,
              let score = report.totalScore,
              (0...100).contains(score),
              let axes = report.axisScores,
              axisScoresAreValid(axes),
              let metrics = report.metrics,
              let grade = report.grade,
              isKnown(grade),
              let baseline = report.recommendedBaseline,
              sharedMetricsAreValid(metrics),
              sharedBaselineIsValid(baseline),
              policySpecificMetricsAreValid(
                policy: report.scorePolicyVersion,
                metrics: metrics,
                baseline: baseline
              ) else { return nil }
        return report
    }

    static func isValidServerReport(_ report: MealReportDTO, sessionId: UUID) -> Bool {
        switch report.status {
        case .generated:
            return completeGeneratedReport(report, sessionId: sessionId) != nil
        case .unreportable:
            return report.reason != nil
        case .unknown:
            return false
        }
    }

    private static func isKnown(_ grade: MealReportGradeDTO) -> Bool {
        switch grade {
        case .good, .soso, .bad: true
        case .unknown: false
        }
    }

    private static func axisScoresAreValid(_ axes: MealReportAxisScoresDTO) -> Bool {
        [axes.chewingRate, axes.chewingTimeRatio, axes.totalChewCount, axes.mealDuration]
            .allSatisfy { (0...100).contains($0) }
    }

    private static func sharedMetricsAreValid(_ metrics: MealReportMetricsDTO) -> Bool {
        metrics.chewingTimeRatio.isFinite
            && (0...1).contains(metrics.chewingTimeRatio)
            && metrics.totalChewCount >= 0
            && metrics.mealDurationSec.isFinite
            && metrics.mealDurationSec > 0
    }

    private static func sharedBaselineIsValid(_ baseline: MealReportRecommendedBaselineDTO) -> Bool {
        baseline.chewingTimeRatio.isFinite
            && (0...1).contains(baseline.chewingTimeRatio)
            && baseline.totalChewCount > 0
            && baseline.mealDurationSec.isFinite
            && baseline.mealDurationSec > 0
    }

    private static func policySpecificMetricsAreValid(
        policy: String?,
        metrics: MealReportMetricsDTO,
        baseline: MealReportRecommendedBaselineDTO
    ) -> Bool {
        switch policy {
        case "legacy-ios-v1":
            finiteNonNegative(metrics.legacyMealRatePerMin)
                && metrics.chewingRatePerMin == nil
                && positive(baseline.chewingRatePerMin.target)
                && baseline.chewingRatePerMin.min == nil
                && baseline.chewingRatePerMin.max == nil
        case "meal-score-v1":
            finiteNonNegative(metrics.chewingRatePerMin)
                && metrics.legacyMealRatePerMin == nil
                && baseline.chewingRatePerMin.target == nil
                && validRange(
                    min: baseline.chewingRatePerMin.min,
                    max: baseline.chewingRatePerMin.max
                )
        default:
            false
        }
    }

    private static func finiteNonNegative(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value >= 0
    }

    private static func positive(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value > 0
    }

    private static func validRange(min: Double?, max: Double?) -> Bool {
        guard positive(min), positive(max), let min, let max else { return false }
        return min <= max
    }
}
