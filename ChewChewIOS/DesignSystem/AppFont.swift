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
            // Pretendard 패키지엔 Heavy weight가 없어 가장 굵은 Black을 사용.
            // system fallback weight는 `.heavy`로 유지해 폰트 없을 때 그 weight로 노출.
            case .heavy:    "Pretendard-Black"
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

    /// 타입 위계 역할. 11개로 흩어진 size·weight 조합을 닫힌 집합으로 묶는다.
    /// Black(`.heavy`)은 `display`와 핵심 stat 숫자에만 한정 — "전부 굵어 위계 없음"을 막는다.
    /// 마이그레이션 동안 기존 `.appFont(weight, size:)`도 그대로 살아 있다.
    enum Role {
        case display   // 화면/히어로 타이틀
        case title     // 카드·페이지 섹션 제목
        case headline  // 서브섹션
        case body      // 주요 본문
        case callout   // 보조/캡션 (최다)
        case caption   // 마이크로 라벨
        case micro     // 최소 허용치 (가독 하한 11pt)

        var weight: AppWeight {
            switch self {
            case .display:  .heavy
            case .title:    .bold
            case .headline: .bold
            case .body:     .semibold
            case .callout:  .semibold
            case .caption:  .medium
            case .micro:    .semibold
            }
        }

        var size: CGFloat {
            switch self {
            case .display:  24
            case .title:    20
            case .headline: 17
            case .body:     15
            case .callout:  13
            case .caption:  12
            case .micro:    11
            }
        }
    }

    static func appFont(_ role: Role) -> Font {
        appFont(role.weight, size: role.size)
    }
}
