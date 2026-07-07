import SwiftUI

/// AirPods 미연결 시 표시하는 커스텀 팝업.
struct AirPodsPromptDialogView: View {
    let onDismissTapped: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: AppSpacing.cell) {
                Image("DaramHi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.image, height: Metrics.image)

                Text("에어팟을 착용해주세요!")
                    .font(.appFont(.heavyHeadlineLarge))
                    .foregroundStyle(Color.textDefault)
                    .multilineTextAlignment(.center)

                Text("AirPods Pro 또는 AirPods 3, 4세대를 연결하면 자동으로 측정이 시작돼요")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, Metrics.contentTopPadding)
            .padding(.bottom, AppSpacing.dialogContentV)
            .padding(.horizontal, AppSpacing.dialogContentH)
            .frame(maxWidth: AppSize.dialogMaxWidth)
            .background(Color.bgPopover, in: RoundedRectangle(cornerRadius: AppRadius.page))
            .appElevation(.floating)

            skipButton
        }
    }

    private var skipButton: some View {
        Button(action: onDismissTapped) {
            Text("다음에 할게요")
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textMuted)
                .padding(.vertical, AppSpacing.oneHalf)
                .padding(.horizontal, AppSpacing.inner)
        }
        .accessibilityIdentifier("AirPodsPromptSkip")
        .padding(.trailing, AppSpacing.three)
        .padding(.top, AppSpacing.three)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        AirPodsPromptDialogView(onDismissTapped: {})
            .padding(.horizontal, AppSpacing.overlayH)
    }
}

private enum Metrics {
    static let image: CGFloat = 110
    static let contentTopPadding: CGFloat = 40
}
