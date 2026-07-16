import SwiftUI

/// AirPods 미연결 시 표시하는 커스텀 팝업.
struct AirPodsPromptDialogView: View {
    let isPreparing: Bool
    let showsDismissAction: Bool
    let onDismissTapped: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: AppSpacing.cell) {
                Image("RealDaram")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.image, height: Metrics.image)
                    .scaleEffect(AppArtwork.daramContentScale)

                Text(title)
                    .font(.appFont(.heavyHeadlineLarge))
                    .foregroundStyle(Color.textDefault)
                    .multilineTextAlignment(.center)

                Text(message)
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

            if showsDismissAction {
                skipButton
            }
        }
    }

    private var title: String {
        isPreparing ? "AirPods를 준비하고 있어요" : "에어팟을 착용해주세요!"
    }

    private var message: String {
        if isPreparing {
            return "준비음이 들리면 자동으로 식사가 시작돼요"
        }
        return "AirPods Pro 또는 AirPods 3, 4세대를 연결하면 자동으로 측정이 시작돼요"
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
        AirPodsPromptDialogView(isPreparing: false, showsDismissAction: true, onDismissTapped: {})
            .padding(.horizontal, AppSpacing.overlayH)
    }
}

private enum Metrics {
    static let image: CGFloat = 110
    static let contentTopPadding: CGFloat = 40
}
