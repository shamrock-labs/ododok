import SwiftUI

struct SoftShadow: ViewModifier {
    enum Size { case base, lg, pill }
    let size: Size

    func body(content: Content) -> some View {
        let amber = Color.rewardAcorn
        let copper = Color.highlightShadow
        switch size {
        case .base: content.shadow(color: amber.opacity(0.10), radius: 10, x: 0, y: 6)
        case .lg:   content.shadow(color: amber.opacity(0.18), radius: 25, x: 0, y: 16)
        case .pill: content.shadow(color: copper.opacity(0.25), radius: 6, x: 0, y: 4)
        }
    }
}

extension View {
    func softShadow(_ size: SoftShadow.Size = .base) -> some View {
        modifier(SoftShadow(size: size))
    }

    @ViewBuilder
    func appElevation(_ elevation: AppElevation) -> some View {
        switch elevation {
        case .flat:
            self
        case .floating:
            self.shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        }
    }
}
