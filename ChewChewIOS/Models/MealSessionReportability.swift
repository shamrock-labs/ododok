import Foundation

/// 서버가 저장한 식사 리포트의 생성 여부를 판단하는 단일 정본.
enum MealSessionReportability {
    /// 측정 진행 중 안내에만 쓰는 서버 정책과 공유된 최소 식사 길이.
    /// 저장된 세션의 리포트 가능 여부는 이 값으로 재판정하지 않는다.
    static let minDurationSec: Double = 30

    static func isReportable(_ dto: ChewingSessionDTO) -> Bool {
        dto.mealReport?.status == .generated
    }
}
