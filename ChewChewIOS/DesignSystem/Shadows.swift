import SwiftUI

/// 뉴모피즘 — 어두운/밝은 한 쌍의 대각 그림자
struct NeuoShadow: ViewModifier {
    enum Size { case sm, md }
    let size: Size

    func body(content: Content) -> some View {
        let warm = Color(red: 180/255, green: 150/255, blue: 110/255)
        switch size {
        case .sm:
            content
                .shadow(color: warm.opacity(0.14), radius: 8, x: 5, y: 5)
                .shadow(color: Color.white.opacity(0.85), radius: 8, x: -5, y: -5)
        case .md:
            content
                .shadow(color: warm.opacity(0.18), radius: 15, x: 10, y: 10)
                .shadow(color: Color.white.opacity(0.95), radius: 15, x: -10, y: -10)
        }
    }
}

struct SoftShadow: ViewModifier {
    enum Size { case base, lg, pill }
    let size: Size

    func body(content: Content) -> some View {
        let amber = Color(red: 180/255, green: 140/255, blue: 80/255)
        let copper = Color(red: 200/255, green: 149/255, blue: 109/255)
        switch size {
        case .base: content.shadow(color: amber.opacity(0.10), radius: 10, x: 0, y: 6)
        case .lg:   content.shadow(color: amber.opacity(0.18), radius: 25, x: 0, y: 16)
        case .pill: content.shadow(color: copper.opacity(0.25), radius: 6, x: 0, y: 4)
        }
    }
}

extension View {
    func neuoShadow(_ size: NeuoShadow.Size = .sm) -> some View {
        modifier(NeuoShadow(size: size))
    }

    func softShadow(_ size: SoftShadow.Size = .base) -> some View {
        modifier(SoftShadow(size: size))
    }
}
