import SwiftUI

/// 앱 전역 폰트 wrapper. PRD #4 acceptance — Pretendard 임베드.
/// 폰트 파일이 번들에 없으면 SwiftUI가 자동으로 system 폰트로 폴백.
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

    /// 타입 위계 역할. 화면별 size·weight 조합을 닫힌 집합으로 묶는다.
    /// Black(`.heavy`)은 `display`와 핵심 stat 숫자에만 한정 — "전부 굵어 위계 없음"을 막는다.
    enum Role {
        case display   // 화면/히어로 타이틀
        case loginWordmark
        case title     // 카드·페이지 섹션 제목
        case headline  // 서브섹션
        case sectionTitle
        case body      // 주요 본문
        case dialogTitle
        case dialogMessage
        case dialogAction
        case dialogActionStrong
        case inputText
        case rewardNumber
        case callout   // 보조/캡션 (최다)
        case caption   // 마이크로 라벨
        case micro     // 최소 허용치 (가독 하한 11pt)
        case regularMicro
        case regularCaption
        case regularCallout
        case regularLabel
        case regularBodyLarge
        case regularHeadline
        case regularTitle
        case regularDisplaySmall
        case regularEmojiMedium
        case regularEmojiLarge
        case regularEmojiXLarge
        case regularEmojiXXLarge
        case regularEmojiHuge
        case mediumCaption
        case mediumBodyLarge
        case mediumHeadline
        case semiboldMicro
        case semiboldCaption
        case semiboldCallout
        case semiboldLabel
        case semiboldBody
        case semiboldBodyLarge
        case semiboldHeadline
        case boldMicro
        case boldCaption
        case boldCallout
        case boldLabel
        case boldBody
        case boldBodyLarge
        case boldHeadline
        case boldTitleCompact
        case boldTitle
        case boldTitleLarge
        case heavyMicro
        case heavyCaption
        case heavyCallout
        case heavyLabel
        case heavyBody
        case heavyBodyLarge
        case heavyHeadline
        case heavyHeadlineLarge
        case heavyTitleCompact
        case heavyTitle
        case heavyTitleLarge
        case heavyTitleXLarge
        case heavyDisplaySmall
        case heavyDisplay

        var weight: AppWeight {
            switch self {
            case .display:  .heavy
            case .loginWordmark: .heavy
            case .title:    .bold
            case .headline: .bold
            case .sectionTitle: .heavy
            case .body:     .semibold
            case .dialogTitle: .bold
            case .dialogMessage: .semibold
            case .dialogAction: .medium
            case .dialogActionStrong: .bold
            case .inputText: .semibold
            case .rewardNumber: .heavy
            case .callout:  .semibold
            case .caption:  .medium
            case .micro:    .semibold
            case .regularMicro,
                 .regularCaption,
                 .regularCallout,
                 .regularLabel,
                 .regularBodyLarge,
                 .regularHeadline,
                 .regularTitle,
                 .regularDisplaySmall,
                 .regularEmojiMedium,
                 .regularEmojiLarge,
                 .regularEmojiXLarge,
                 .regularEmojiXXLarge,
                 .regularEmojiHuge:
                .regular
            case .mediumCaption,
                 .mediumBodyLarge,
                 .mediumHeadline:
                .medium
            case .semiboldMicro,
                 .semiboldCaption,
                 .semiboldCallout,
                 .semiboldLabel,
                 .semiboldBody,
                 .semiboldBodyLarge,
                 .semiboldHeadline:
                .semibold
            case .boldMicro,
                 .boldCaption,
                 .boldCallout,
                 .boldLabel,
                 .boldBody,
                 .boldBodyLarge,
                 .boldHeadline,
                 .boldTitleCompact,
                 .boldTitle,
                 .boldTitleLarge:
                .bold
            case .heavyMicro,
                 .heavyCaption,
                 .heavyCallout,
                 .heavyLabel,
                 .heavyBody,
                 .heavyBodyLarge,
                 .heavyHeadline,
                 .heavyHeadlineLarge,
                 .heavyTitleCompact,
                 .heavyTitle,
                 .heavyTitleLarge,
                 .heavyTitleXLarge,
                 .heavyDisplaySmall,
                 .heavyDisplay:
                .heavy
            }
        }

        var size: CGFloat {
            switch self {
            case .display:  24
            case .loginWordmark: 40
            case .title:    20
            case .headline: 17
            case .sectionTitle: 17
            case .body:     15
            case .dialogTitle: 17
            case .dialogMessage: 15
            case .dialogAction: 16
            case .dialogActionStrong: 16
            case .inputText: 16
            case .rewardNumber: 36
            case .callout:  14
            case .caption:  12
            case .micro:    11
            case .regularMicro: 11
            case .regularCaption: 12
            case .regularCallout: 14
            case .regularLabel: 14
            case .regularBodyLarge: 16
            case .regularHeadline: 18
            case .regularTitle: 20
            case .regularDisplaySmall: 24
            case .regularEmojiMedium: 28
            case .regularEmojiLarge: 30
            case .regularEmojiXLarge: 32
            case .regularEmojiXXLarge: 40
            case .regularEmojiHuge: 44
            case .mediumCaption: 12
            case .mediumBodyLarge: 16
            case .mediumHeadline: 18
            case .semiboldMicro: 11
            case .semiboldCaption: 12
            case .semiboldCallout: 14
            case .semiboldLabel: 14
            case .semiboldBody: 15
            case .semiboldBodyLarge: 16
            case .semiboldHeadline: 17
            case .boldMicro: 11
            case .boldCaption: 12
            case .boldCallout: 14
            case .boldLabel: 14
            case .boldBody: 15
            case .boldBodyLarge: 16
            case .boldHeadline: 17
            case .boldTitleCompact: 19
            case .boldTitle: 20
            case .boldTitleLarge: 22
            case .heavyMicro: 11
            case .heavyCaption: 12
            case .heavyCallout: 14
            case .heavyLabel: 14
            case .heavyBody: 15
            case .heavyBodyLarge: 16
            case .heavyHeadline: 17
            case .heavyHeadlineLarge: 18
            case .heavyTitleCompact: 19
            case .heavyTitle: 20
            case .heavyTitleLarge: 21
            case .heavyTitleXLarge: 22
            case .heavyDisplaySmall: 24
            case .heavyDisplay: 28
            }
        }
    }

    static func appFont(_ role: Role) -> Font {
        appFont(role.weight, size: role.size)
    }
}
