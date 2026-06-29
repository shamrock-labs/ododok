import CoreGraphics

/// 코너 radius 스케일. 흩어진 14종(6~28)을 5단으로 닫는다.
/// 카드 컨테이너는 `lg`로 통일, 아웃라이어(헤더 22·다람쥐카드 26)는 해당 컴포넌트 로컬 상수로 둔다.
enum AppRadius {
    static let xs: CGFloat = 10  // 작은 아이콘 배경·칩
    static let sm: CGFloat = 14  // 서브카드·인포박스
    static let md: CGFloat = 18  // 내부 패널
    static let lg: CGFloat = 24  // 카드 컨테이너 표준
    static let xl: CGFloat = 28  // 히어로(리포트) 카드 — lg로 흡수 예정
}

/// 스페이싱 스케일. 매직넘버 패딩을 의미 토큰으로 묶는다.
enum AppSpacing {
    static let page: CGFloat = 20     // 화면 바깥 좌우 여백
    static let cardH: CGFloat = 14    // 카드 내부 좌우
    static let cardV: CGFloat = 12    // 카드 내부 상하
    static let gap: CGFloat = 12      // 요소 간 표준 간격
    static let gapTight: CGFloat = 8  // 좁은 간격
}
