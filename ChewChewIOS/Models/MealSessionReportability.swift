import Foundation

/// 세션이 리포트/점수를 낼 수 있는지 판단하는 단일 정본.
///
/// 리스트·상세(`ReportCardModel.from`)와 records 매핑의 oldest 조회가
/// 같은 규칙을 쓰도록 판정 로직과 임계값을 한 곳에 둔다.
/// (버그 F 재발 방지 — "리포트 가능한가"를 여러 곳에 복붙하지 않는다.)
enum MealSessionReportability {
    /// 리포트 대상으로 인정하는 최소 식사 길이.
    static let minDurationSec: Double = 30

    static func isReportable(_ dto: ChewingSessionDTO) -> Bool {
        dto.durationSec >= minDurationSec && SessionScore.compute(dto) != nil
    }
}
