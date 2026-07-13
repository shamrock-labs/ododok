import SwiftUI

struct ServerPreparingView: View {
    let status: ServerAvailabilityStore.Status
    let retry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sectionGap) {
            Image(systemName: "server.rack")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.tintInteractive)

            VStack(spacing: AppSpacing.gap) {
                Text(status == .checking ? "서버를 확인하고 있어요" : "서버를 준비하고 있어요")
                    .font(.appFont(.boldTitle))
                    .foregroundStyle(Color.textPrimary)

                Text("준비가 끝나면 자동으로 시작할게요.")
                    .font(.appFont(.regularBodyLarge))
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)

            ProgressView()
                .controlSize(.large)
                .tint(Color.tintInteractive)

            AppTextActionButton(
                title: "다시 시도",
                icon: "arrow.clockwise",
                action: retry
            )
        }
        .padding(.horizontal, AppSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground.ignoresSafeArea())
    }
}
