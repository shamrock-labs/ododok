import CoreGraphics
import Foundation

/// 코너 radius 스케일. 흩어진 14종(6~28)을 5단으로 닫는다.
/// 카드 컨테이너는 `lg`로 통일, 아웃라이어(헤더 22·다람쥐카드 26)는 해당 컴포넌트 로컬 상수로 둔다.
enum AppRadius {
    static let xs: CGFloat = 10  // 작은 아이콘 배경·칩
    static let sm: CGFloat = 14  // 서브카드·인포박스
    static let md: CGFloat = 18  // 내부 패널
    static let lg: CGFloat = 24  // 카드 컨테이너 표준
    static let xl: CGFloat = 28  // 히어로(리포트) 카드 — lg로 흡수 예정

    // Astryx Shape의 inner → element → container → page 의미 이름.
    static let none: CGFloat = 0
    static let inner = xs
    static let element = sm
    static let elementLarge: CGFloat = 16
    static let container = md
    static let containerLoose: CGFloat = 20
    static let page = xl
    static let full: CGFloat = 9999
    static let iconContainer: CGFloat = 11
}

/// 스페이싱 스케일. 매직넘버 패딩을 의미 토큰으로 묶는다.
enum AppSpacing {
    // 4pt 기반 scale. 기존 화면에서 쓰는 6/8/12/16/20/24/28/32/40/44를 닫힌 집합으로 둔다.
    static let none: CGFloat = 0
    static let half: CGFloat = 2
    static let one: CGFloat = 4
    static let oneHalf: CGFloat = 6
    static let two: CGFloat = 8
    static let three: CGFloat = 12
    static let four: CGFloat = 16
    static let five: CGFloat = 20
    static let six: CGFloat = 24
    static let seven: CGFloat = 28
    static let eight: CGFloat = 32
    static let nine: CGFloat = 36
    static let ten: CGFloat = 40
    static let eleven: CGFloat = 44

    static let page: CGFloat = 20     // 화면 바깥 좌우 여백
    static let cardH: CGFloat = 14    // 카드 내부 좌우
    static let cardV: CGFloat = 12    // 카드 내부 상하
    static let gap: CGFloat = 12      // 요소 간 표준 간격
    static let gapTight: CGFloat = 8  // 좁은 간격
    static let iconGap: CGFloat = 9
    static let microGap: CGFloat = 3  // badge와 보조 텍스트처럼 기존 main에서 쓰는 초밀도 간격
    static let microLabelGap: CGFloat = 5

    static let sectionGap = five
    static let sectionGapCompact = three
    static let inner: CGFloat = 10
    static let controlH = four
    static let controlV = three
    static let badgeH: CGFloat = 7
    static let badgeV = microGap
    static let row = four
    static let pageInsetCompact: CGFloat = 10
    static let pageInsetVertical = four
    static let cardContent = four
    static let cardContentLarge = six
    static let cell = cardH
    static let dialogH: CGFloat = 22
    static let dialogV = five
    static let overlayH = ten
    static let inputH: CGFloat = 18
    static let inputV: CGFloat = 14
    static let inputVLarge: CGFloat = 15
    static let verticalLoose: CGFloat = 18
    static let actionV: CGFloat = 17
    static let topInsetCompact: CGFloat = 10
    static let overlayBottom: CGFloat = 110
    static let sheetContent: CGFloat = 20
    static let dialogContentH: CGFloat = 22
    static let dialogContentV: CGFloat = 24
    static let toastH = four
    static let toastV = inner
    static let cardOuter = six
    static let cardOuterBottom = seven
}

enum AppSize {
    static let hairline: CGFloat = 0.5
    static let border: CGFloat = 1
    static let dialogMaxWidth: CGFloat = 320
    static let dialogActionHeight: CGFloat = 44
    static let iconSmall: CGFloat = 18
    static let iconContainerCompact: CGFloat = 30
    static let iconContainer: CGFloat = 34
    static let iconContainerLarge: CGFloat = 36
    static let iconContainerTiny: CGFloat = 26
    static let iconContainerXL: CGFloat = 56
    static let statusDot: CGFloat = 12
    static let statusDotTiny: CGFloat = 6
}

enum AppMotion {
    static let durationFast: TimeInterval = 0.16
    static let durationSignal: TimeInterval = 0.07
    static let durationButtonPress: TimeInterval = 0.12
    static let durationStateChange: TimeInterval = 0.22
    static let durationPageChange: TimeInterval = 0.25
    static let durationProgress: TimeInterval = 0.7
    static let durationWave: TimeInterval = 2.2
    static let durationPulse: TimeInterval = 1.2
    static let durationChew: TimeInterval = 0.72
    static let durationDemoChew: TimeInterval = 0.9

    static let springFastResponse: Double = 0.28
    static let springResponse: Double = 0.32
    static let springDampingFraction: Double = 0.88
    static let springDemoResponse: Double = 0.3
    static let springPlayfulResponse: Double = 0.35
    static let springPlayfulDamping: Double = 0.6
    static let springSquirrelResponse: Double = 0.42
    static let springSquirrelDamping: Double = 0.55
}

enum AppElevation {
    case flat
    case low
    case medium
    case high
    case inset
}
