import SwiftUI

/// AirPods 연결 감지 후 자동 측정 시작 전 3-2-1 카운트다운 오버레이.
struct StartCountdownView: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.bgPopover)
                .frame(width: Metrics.circle, height: Metrics.circle)
                .appElevation(.floating)

            Text("\(value)")
                .font(.appFont(.heavyDisplay))
                .foregroundStyle(Color.textActionStrong)
                .monospacedDigit()
                .id(value)
                .transition(.scale(scale: 1.3).combined(with: .opacity))
        }
        .animation(
            .spring(response: AppMotion.springResponse, dampingFraction: AppMotion.springDampingFraction),
            value: value
        )
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        StartCountdownView(value: 3)
    }
}

private enum Metrics {
    static let circle: CGFloat = 120
}
