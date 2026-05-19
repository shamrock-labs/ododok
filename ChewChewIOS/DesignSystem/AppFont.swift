import SwiftUI

/// 앱 전역 폰트 wrapper. PRD #4 acceptance — Pretendard 임베드. 호출부는
/// `.appFont(.regular, size: 13)` 형태로 SwiftUI `.font(.system(size:, weight:))`를
/// 일대일 교체. 폰트 파일이 번들에 없으면 SwiftUI가 자동으로 system 폰트로 폴백.
extension Font {
    /// PRD #4 Pretendard 5단계 + 옵셔널 italic. system weight와 1:1 매핑.
    enum AppWeight {
        case regular, medium, semibold, bold, heavy

        fileprivate var postScriptName: String {
            switch self {
            case .regular:  "Pretendard-Regular"
            case .medium:   "Pretendard-Medium"
            case .semibold: "Pretendard-SemiBold"
            case .bold:     "Pretendard-Bold"
            case .heavy:    "Pretendard-Heavy"
            }
        }

        fileprivate var systemFallback: Font.Weight {
            switch self {
            case .regular:  .regular
            case .medium:   .medium
            case .semibold: .semibold
            case .bold:     .bold
            case .heavy:    .heavy
            }
        }
    }

    static func appFont(_ weight: AppWeight, size: CGFloat) -> Font {
        .custom(weight.postScriptName, size: size)
            .weight(weight.systemFallback)
    }
}
