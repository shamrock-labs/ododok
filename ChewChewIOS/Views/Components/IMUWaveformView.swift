import SwiftUI

/// 오디오 비주얼라이저식 IMU 파형. 중앙선을 기준으로 위아래로 뻗는 세로 막대들이
/// 샘플 에너지에 따라 높이를 바꾼다. 샘플 배열(`imuWaveformSamples`)이 좌→우로
/// 흐르며 갱신되고, 0.07초 선형 애니메이션이 높이 변화를 이어 붙여 막대가
/// 흐르듯 움직인다. 양 끝은 스무스스텝으로 줄여 가장자리에서 뚝 끊기지 않게 한다.
struct IMUWaveformView: View {
    let samples: [Double]
    let isLive: Bool

    var body: some View {
        Canvas { context, size in
            drawBars(context, size: size)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.acorn50.opacity(isLive ? 0.8 : 0.45),
                    Color.acorn50.opacity(0.55),
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

    private func drawBars(_ context: GraphicsContext, size: CGSize) {
        guard samples.count > 1 else { return }

        let visualGain = isLive ? 1.5 : 1.15
        let clamped = samples.map { min(1.0, max(0.0, $0 * visualGain)) }
        let count = clamped.count
        let slot = size.width / CGFloat(count)
        let barWidth = min(slot * 0.5, 3.5)
        let midY = size.height / 2
        let maxAmp = size.height * 0.46   // 중앙선 기준 한쪽 최대 진폭

        var bars = Path()
        for i in 0..<count {
            let xCenter = slot * (CGFloat(i) + 0.5)
            let value = clamped[i] * edgeWindow(index: i, count: count)
            let half = max(1.0, CGFloat(value) * maxAmp)
            let rect = CGRect(
                x: xCenter - barWidth / 2,
                y: midY - half,
                width: barWidth,
                height: half * 2
            )
            bars.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }

        context.fill(
            bars,
            with: .linearGradient(
                Gradient(colors: isLive
                    ? [Color.acorn300, Color.acorn500, Color.acorn700]
                    : [Color.textTertiary.opacity(0.45), Color.textTertiary.opacity(0.3)]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            )
        )
    }

    /// 양 끝 16% 구간을 스무스스텝으로 0→1 줄여 막대 높이를 가장자리에서 부드럽게 감쇠.
    private func edgeWindow(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 1 }
        let t = CGFloat(index) / CGFloat(count - 1)
        let fade: CGFloat = 0.16
        let e = min(min(t, 1 - t) / fade, 1)
        return e * e * (3 - 2 * e)
    }
}

#Preview {
    IMUWaveformView(
        samples: (0..<54).map { i in
            let envelope = pow(max(0, sin(Double(i) * 0.12 + 0.6)), 1.6)
            let detail = pow(max(0, sin(Double(i) * 0.9)), 2.0)
            return 0.06 + envelope * detail * 0.9
        },
        isLive: true
    )
    .frame(width: 320, height: 64)
    .padding()
    .background(Color.pageBackground)
}
