import SwiftUI
import UIKit

extension Color {
    static let cream    = Color(hex: 0xFAF7F2)
    static let cream2   = Color(hex: 0xF5EDE0)

    static let acorn50  = Color(hex: 0xFBF3E8)
    static let acorn100 = Color(hex: 0xF5E2C8)
    static let acorn200 = Color(hex: 0xE8C99B)
    static let acorn300 = Color(hex: 0xD9B07F)
    static let acorn400 = Color(hex: 0xC8956D)
    static let acorn500 = Color(hex: 0xB07F58)
    static let acorn600 = Color(hex: 0x9C6E47)
    static let acorn700 = Color(hex: 0x7B532E)
    static let acorn800 = Color(hex: 0x5C3E25)

    static let sage50   = Color(hex: 0xEDF6EE)
    static let sage100  = Color(hex: 0xD4ECD7)
    static let sage200  = Color(hex: 0xB8DEC0)
    static let sage400  = Color(hex: 0x7FC298)
    static let sage500  = Color(hex: 0x5FAA7E)
    static let sage600  = Color(hex: 0x4A8E66)

    static let butter50  = Color(hex: 0xFFF9E5)
    static let butter100 = Color(hex: 0xFCF1D2)
    static let butter400 = Color(hex: 0xF5C97B)
    static let butter500 = Color(hex: 0xE8B055)
    static let butter600 = Color(hex: 0xC9912E)

    /// 카카오 브랜드 옐로우(공식 #FEE500). 카카오 공유/초대 버튼 전용.
    static let kakaoYellow = Color(hex: 0xFEE500)

    /// Google 브랜드 토큰. Google 로그인 버튼 전용.
    static let googleText   = Color(hex: 0x3C4043)
    static let googleBorder = Color(hex: 0xDADCE0)
    static let googleBlue   = Color(hex: 0x4285F4)

    static let blush100 = Color(hex: 0xFCE7E0)
    static let blush200 = Color(hex: 0xF8CFC0)
    static let blush400 = Color(hex: 0xF4A99B)
    static let blush500 = Color(hex: 0xE88C7B)
    static let blush600 = Color(hex: 0xD96F5C)

    static let ink100 = Color(hex: 0xF2EDE5)
    static let ink400 = Color(hex: 0x8C7B66)
    static let ink600 = Color(hex: 0x5C4F3E)
    static let ink800 = Color(hex: 0x2D2418)

    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// 라이트/다크 두 값을 받아 `colorScheme`에 따라 자동 전환하는 동적 색.
    /// Phase 1에서는 light == dark로 정의해 시각 변화가 0이고, Phase 5에서 dark 인자만
    /// 채우면 호출부 수정 없이 다크모드가 들어온다.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8)  & 0xFF) / 255.0,
                blue:  CGFloat( hex        & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }
}

// MARK: - 시맨틱 토큰 레이어
//
// 위 raw 스케일(acorn/sage/butter/blush/ink…)은 "팔레트"고, 아래가 "시스템"이다.
// 화면·컴포넌트는 raw가 아니라 의미 토큰(textPrimary, surface, accentChew…)에만 의존한다.
// 각 토큰은 동적 색이라 Phase 5에서 dark 인자만 채우면 전 화면 다크모드가 켜진다.
// 현재는 light == dark(= 기존 raw 값)이라 라이트모드 픽셀이 종전과 동일하다.
extension Color {
    // 텍스트 (라이트=ink 스케일, 다크=warm off-white로 반전)
    static let textPrimary   = Color(light: 0x2D2418, dark: 0xF2EDE6)
    static let textSecondary = Color(light: 0x5C4F3E, dark: 0xC2B6A4)
    static let textTertiary  = Color(light: 0x8C7B66, dark: 0x9A8E7C)

    // 표면 / 배경 (라이트=cream/white, 다크=warm near-black 계열)
    static let surface        = Color(light: 0xFFFFFF, dark: 0x262019) // 카드 표면
    static let surfaceSunken  = Color(light: 0xFBF3E8, dark: 0x1E1913) // 내부 패널(표면보다 어둡게)
    static let pageBackground = Color(light: 0xFAF7F2, dark: 0x17130E) // 화면 배경
    static let hairline       = Color(light: 0xF2EDE5, dark: 0x39312A) // 구분선/링 트랙

    // 인터랙티브 / 강조 (다크에선 한 단계 밝은 acorn으로 대비 확보)
    static let tintPrimary     = Color(light: 0x7B532E, dark: 0xD9B07F) // acorn700 → acorn300
    static let tintInteractive = Color(light: 0x9C6E47, dark: 0xE8C99B) // acorn600 → acorn200

    // 지표 액센트 (다크에선 한 단계 밝은 톤)
    static let accentChew  = Color(light: 0xB07F58, dark: 0xD9B07F) // 저작
    static let accentTime  = Color(light: 0x5FAA7E, dark: 0x7FC298) // 시간
    static let accentFocus = Color(light: 0xC9912E, dark: 0xF5C97B) // 집중/비율
    static let accentGood  = Color(light: 0x4A8E66, dark: 0x7FC298) // 긍정
    static let accentWarn  = Color(light: 0xE88C7B, dark: 0xF4A99B) // 주의
}

// MARK: - Usage-first semantic aliases
//
// Astryx Foundations의 color 원칙처럼 호출부는 raw hex/palette보다 용도 이름을 우선한다.
// 값은 기존 semantic token을 그대로 가리켜 main 화면의 시각값을 바꾸지 않는다.
extension Color {
    // Text
    static let textDefault       = textPrimary
    static let textMuted         = textSecondary
    static let textSubtle        = textTertiary
    static let textPlaceholder   = textTertiary
    static let textDisabled      = textTertiary.opacity(0.65)
    static let textAction        = tintPrimary
    static let textActionStrong  = tintInteractive
    static let textActionInverse = surface
    static let textDanger        = accentWarn

    // Surface hierarchy: body -> surface -> sunken/input -> overlay.
    static let bgBody          = pageBackground
    static let bgPage          = pageBackground
    static let bgSurface       = surface
    static let bgCard          = surface
    static let bgPopover       = surface
    static let bgSunken        = surfaceSunken
    static let bgInput         = surface
    static let bgInputFocused  = surface
    static let bgInputDisabled = surfaceSunken
    static let bgOverlayScrim  = Color(light: 0x000000, dark: 0x000000).opacity(0.32)
    static let bgSelected      = tintInteractive.opacity(0.12)

    // Border / rings
    static let borderDefault    = hairline
    static let borderMuted      = hairline.opacity(0.8)
    static let borderInput      = hairline
    static let borderFocus      = tintInteractive
    static let borderEmphasized = acorn200
    static let borderSelected   = acorn100

    // Status
    static let statusSuccess = accentGood
    static let statusWarning = accentFocus
    static let statusDanger  = accentWarn
    static let statusWarningMuted = butter100
    static let statusDangerMuted = blush100
    static let statusSuccessMuted = sage50
    static let statusSuccessBorder = sage100

    // Data / product feedback
    static let dataChew = accentChew
    static let dataTime = accentTime
    static let dataSpeed = accentWarn
    static let dataRatio = accentFocus
    static let dataChewGradient = [acorn300, acorn500, acorn700]
    static let rewardAcorn = tintPrimary
    static let rewardAcornStrong = tintInteractive
    static let controlOnSurface = surface.opacity(0.72)
    static let controlOnAccent = surface
    static let illustrationHalo = blush100
    static let illustrationHaloFade = acorn50
    static let illustrationRing = acorn400
    static let illustrationShadow = acorn800
    static let illustrationSparkle = butter500
    static let mealStartGradient = [acorn400, acorn600]
    // 시작 버튼(acorn 400→600)과 같은 2단 깊이로 — 활성 상태가 흐릿해 보이지 않게 한 톤 진하게.
    static let mealStopGradient = [blush500, blush600]
    static let highlightShadow = acorn400

    // Input component aliases
    static let inputBg            = bgInput
    static let inputBgFocused     = bgInputFocused
    static let inputBgDisabled    = bgInputDisabled
    static let inputText          = textDefault
    static let inputPlaceholder   = textPlaceholder
    static let inputBorder        = borderInput
    static let inputFocusedBorder = borderFocus
}

extension LinearGradient {
    /// 메인 탭 배경. 동적 색 엔드포인트라 colorScheme에 따라 자동 전환된다.
    /// 라이트 값은 기존 acorn50/cream/sage50와 동일(픽셀 동일), 다크는 warm near-black.
    static let appBackground = LinearGradient(
        colors: [
            Color(light: 0xFBF3E8, dark: 0x1F1912).opacity(0.7), // acorn50 / warm dark
            Color(light: 0xFAF7F2, dark: 0x17130E),              // cream / 화면 배경 dark
            Color(light: 0xEDF6EE, dark: 0x141A16).opacity(0.6), // sage50 / cool dark
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
