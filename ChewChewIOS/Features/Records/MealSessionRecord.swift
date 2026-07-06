import Foundation

/// 기록 화면에서 사용하는 식사 세션 도메인 모델.
///
/// 서버 DTO의 필드 모양이 아니라, 기록 화면이 표시하고 이동하는 의미만 담는다.
struct MealSessionRecord: Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let durationSec: Double
    let reportCard: ReportCardModel
}
