import SwiftUI

enum OpenIcon {
    case flame
    case acorn
    case sunrise
    case utensils
    case moonStar
    case people
}

struct OpenIconView: View {
    let icon: OpenIcon
    var color: Color
    var lineWidth: CGFloat = 2.1

    var body: some View {
        OpenIconShape(icon: icon)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .aspectRatio(1, contentMode: .fit)
    }
}

private struct OpenIconShape: Shape {
    let icon: OpenIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let origin = CGPoint(
            x: rect.midX - 12 * scale,
            y: rect.midY - 12 * scale
        )

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()

        switch icon {
        case .flame:
            path.move(to: p(12, 3))
            path.addQuadCurve(to: p(16, 9.5), control: p(13, 7))
            path.addQuadCurve(to: p(19, 15), control: p(19, 12))
            path.addCurve(to: p(12, 22), control1: p(19, 18.9), control2: p(15.8, 22))
            path.addCurve(to: p(5, 15), control1: p(8.2, 22), control2: p(5, 18.9))
            path.addQuadCurve(to: p(6, 12), control: p(5, 13))
            path.addQuadCurve(to: p(10, 15), control: p(7.3, 15))
            path.addQuadCurve(to: p(12.5, 12), control: p(12.5, 14.5))
            path.addQuadCurve(to: p(10.5, 7.5), control: p(12.5, 9.8))
            path.addQuadCurve(to: p(12, 3), control: p(10.2, 5))

        case .acorn:
            path.move(to: p(12, 2))
            path.addLine(to: p(12, 4))

            path.move(to: p(5, 10))
            path.addLine(to: p(5, 14))
            path.addCurve(to: p(10.3, 20.8), control1: p(5, 17.25), control2: p(7.2, 20.1))
            path.addCurve(to: p(11.38, 21.38), control1: p(10.7, 20.9), control2: p(11.08, 21.08))
            path.addLine(to: p(12, 22))
            path.addLine(to: p(12.62, 21.38))
            path.addCurve(to: p(13.72, 20.8), control1: p(12.92, 21.08), control2: p(13.3, 20.9))
            path.addCurve(to: p(19, 14), control1: p(16.8, 20.1), control2: p(19, 17.25))
            path.addLine(to: p(19, 10))

            path.move(to: p(12, 4))
            path.addCurve(to: p(4, 8), control1: p(8, 4), control2: p(4.5, 6))
            path.addCurve(to: p(2, 11), control1: p(3.75, 9), control2: p(3.05, 10.05))
            path.addCurve(to: p(5, 10), control1: p(3.3, 11.1), control2: p(4.05, 10.75))
            path.addCurve(to: p(7, 12), control1: p(5.55, 10.95), control2: p(6.0, 11.4))
            path.addCurve(to: p(9.5, 10), control1: p(8.4, 11.4), control2: p(8.95, 10.95))
            path.addCurve(to: p(12, 12), control1: p(10.1, 11), control2: p(10.7, 11.45))
            path.addCurve(to: p(14.5, 10), control1: p(13.3, 11.45), control2: p(13.9, 11))
            path.addCurve(to: p(17, 12), control1: p(15.05, 10.95), control2: p(15.6, 11.4))
            path.addCurve(to: p(19, 10), control1: p(18.2, 11.45), control2: p(18.7, 11.05))
            path.addCurve(to: p(22, 11), control1: p(20.0, 10.75), control2: p(20.7, 11.1))
            path.addCurve(to: p(20, 8), control1: p(20.95, 10.05), control2: p(20.25, 9))
            path.addCurve(to: p(12, 4), control1: p(19.5, 6), control2: p(16, 4))

        case .sunrise:
            path.move(to: p(12, 2))
            path.addLine(to: p(12, 10))
            path.move(to: p(4.93, 10.93))
            path.addLine(to: p(6.34, 12.34))
            path.move(to: p(2, 18))
            path.addLine(to: p(4, 18))
            path.move(to: p(20, 18))
            path.addLine(to: p(22, 18))
            path.move(to: p(19.07, 10.93))
            path.addLine(to: p(17.66, 12.34))
            path.move(to: p(2, 22))
            path.addLine(to: p(22, 22))
            path.move(to: p(8, 6))
            path.addLine(to: p(12, 2))
            path.addLine(to: p(16, 6))
            path.move(to: p(8, 18))
            path.addQuadCurve(to: p(16, 18), control: p(12, 10.8))

        case .utensils:
            path.move(to: p(3, 2))
            path.addLine(to: p(3, 9))
            path.addCurve(to: p(5, 11), control1: p(3, 10.1), control2: p(3.9, 11))
            path.addLine(to: p(9, 11))
            path.addCurve(to: p(11, 9), control1: p(10.1, 11), control2: p(11, 10.1))
            path.addLine(to: p(11, 2))
            path.move(to: p(7, 2))
            path.addLine(to: p(7, 22))
            path.move(to: p(21, 15))
            path.addLine(to: p(21, 2))
            path.addCurve(to: p(16, 7), control1: p(18.24, 2), control2: p(16, 4.24))
            path.addLine(to: p(16, 13))
            path.addCurve(to: p(18, 15), control1: p(16, 14.1), control2: p(16.9, 15))
            path.addLine(to: p(21, 15))
            path.addLine(to: p(21, 22))

        case .moonStar:
            path.move(to: p(18, 5))
            path.addLine(to: p(22, 5))
            path.move(to: p(20, 3))
            path.addLine(to: p(20, 7))
            path.move(to: p(20.5, 12.4))
            path.addCurve(to: p(10.1, 20.5), control1: p(19.8, 17.5), control2: p(15.4, 21.2))
            path.addCurve(to: p(2.5, 10.4), control1: p(5.2, 19.9), control2: p(1.7, 15.4))
            path.addCurve(to: p(11.5, 3), control1: p(3.1, 6.1), control2: p(6.5, 2.8))
            path.addCurve(to: p(14.7, 14.5), control1: p(8.9, 7.1), control2: p(10.1, 12.5))
            path.addCurve(to: p(20.5, 12.4), control1: p(16.6, 15.3), control2: p(18.8, 14.8))

        case .people:
            path.addEllipse(in: CGRect(x: origin.x + 5 * scale, y: origin.y + 3 * scale, width: 8 * scale, height: 8 * scale))
            path.move(to: p(16, 21))
            path.addLine(to: p(16, 19))
            path.addCurve(to: p(12, 15), control1: p(16, 16.8), control2: p(14.2, 15))
            path.addLine(to: p(6, 15))
            path.addCurve(to: p(2, 19), control1: p(3.8, 15), control2: p(2, 16.8))
            path.addLine(to: p(2, 21))
            path.move(to: p(16, 3.1))
            path.addCurve(to: p(16, 10.9), control1: p(18.35, 3.55), control2: p(18.35, 10.45))
            path.move(to: p(22, 21))
            path.addLine(to: p(22, 19))
            path.addCurve(to: p(19, 15.1), control1: p(22, 17.1), control2: p(20.8, 15.5))
        }

        return path
    }
}
