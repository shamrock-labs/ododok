import Foundation

/// 사용자가 설정 화면에서 선택한 AirPods 모델. CMHeadphoneMotionManager는 모델
/// 종속이 없어 측정 자체엔 영향을 주지 않지만, 안내·디스플레이용으로 저장한다.
/// `@AppStorage("ododok.airpodsModel")` 키로 영속화.
///
/// Apple 공식 IMU 지원 기종: AirPods Pro 1/2세대, AirPods 3/4세대, AirPods Max.
/// (일반 AirPods 1/2세대는 IMU 미탑재 — 콜백 자체가 나오지 않음.)
/// v1.0 picker UI는 Max 제외 — Pro 2 → Pro 1 → 4 → 3 순.
enum AirPodsModel: String, CaseIterable, Identifiable {
    case pro2
    case pro
    case fourth
    case third

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pro2:   "AirPods Pro 2"
        case .pro:    "AirPods Pro"
        case .fourth: "AirPods 4"
        case .third:  "AirPods 3세대"
        }
    }
}

extension AirPodsModel {
    static let storageKey = "ododok.airpodsModel"
    static let `default`: AirPodsModel = .pro2
}
