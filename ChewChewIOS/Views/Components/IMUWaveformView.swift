import SwiftUI

struct IMUWaveformView: View {
    let samples: [Double]
    let isLive: Bool

    var body: some View {
        Canvas { context, size in
            var context = context
            drawGrid(in: &context, size: size)
            drawWaveform(in: &context, size: size)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.sage50.opacity(isLive ? 0.8 : 0.45),
                    Color.acorn50.opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
        }
        .animation(.linear(duration: 0.07), value: samples)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let midY = size.height / 2
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: 0, y: midY))
        centerLine.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(centerLine, with: .color(Color.textTertiary.opacity(0.18)), lineWidth: 1)

        for fraction in [CGFloat(0.25), CGFloat(0.75)] {
            var guide = Path()
            let y = size.height * fraction
            guide.move(to: CGPoint(x: 0, y: y))
            guide.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(guide, with: .color(Color.white.opacity(0.45)), lineWidth: 1)
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        guard samples.count > 1 else { return }

        let visualGain = isLive ? 1.45 : 1.2
        let clampedSamples = samples.map { min(1.0, max(0.0, $0 * visualGain)) }
        let stepX = size.width / CGFloat(clampedSamples.count - 1)
        let midY = size.height / 2
        let amplitude = size.height * 0.49

        // 샘플을 (x, y) 점으로 변환한 뒤 Catmull-Rom 형식의 cubic Bezier로 보간해
        // 각진 polyline 대신 부드러운 곡선으로 렌더.
        let points: [CGPoint] = clampedSamples.indices.map { i in
            let x = CGFloat(i) * stepX
            let phase = Double(i) * 0.58
            // 연속 sine — 부호 점프 없이 부드러운 파형. Catmull-Rom 보간과 결합되어
            // 자연스럽게 흐르는 곡선이 된다.
            let y = midY - CGFloat(clampedSamples[i] * sin(phase)) * amplitude
            return CGPoint(x: x, y: y)
        }

        var fillPath = Path()
        var linePath = Path()
        linePath.move(to: points[0])
        fillPath.move(to: CGPoint(x: points[0].x, y: midY))
        fillPath.addLine(to: points[0])

        for i in 1..<points.count {
            let p1 = points[i - 1]
            let p2 = points[i]
            let p0 = i - 2 >= 0 ? points[i - 2] : p1
            let p3 = i + 1 < points.count ? points[i + 1] : p2

            // Catmull-Rom → cubic Bezier 변환. 텐션 1/6이 표준.
            let c1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let c2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            linePath.addCurve(to: p2, control1: c1, control2: c2)
            fillPath.addCurve(to: p2, control1: c1, control2: c2)
        }

        fillPath.addLine(to: CGPoint(x: size.width, y: midY))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color.sage400.opacity(isLive ? 0.24 : 0.12),
                    Color.acorn300.opacity(isLive ? 0.12 : 0.06)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )

        context.stroke(
            linePath,
            with: .linearGradient(
                Gradient(colors: [
                    isLive ? Color.sage600 : Color.textTertiary.opacity(0.42),
                    isLive ? Color.acorn500 : Color.textTertiary.opacity(0.28)
                ]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            ),
            style: StrokeStyle(lineWidth: isLive ? 3.6 : 3, lineCap: .round, lineJoin: .round)
        )
    }
}

#Preview {
    IMUWaveformView(
        samples: (0..<54).map { i in
            0.12 + pow(max(0, sin(Double(i) * 0.4)), 2.4) * 0.75
        },
        isLive: true
    )
    .frame(width: 320, height: 76)
    .padding()
}
