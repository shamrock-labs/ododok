import SwiftUI

struct AppSettingsSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.appFont(.sectionTitle))
                .foregroundStyle(Color.textDefault)
            Spacer()
        }
        .padding(.bottom, AppSpacing.topInsetCompact)
    }
}

private enum Metrics {
    static let iconWidth: CGFloat = 26
}

struct AppSettingsRow: View {
    let icon: String
    let title: String
    var value: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: AppSpacing.gap) {
            Image(systemName: icon)
                .font(.appFont(.mediumBodyLarge))
                .foregroundStyle(Color.textMuted)
                .frame(width: Metrics.iconWidth)

            Text(title)
                .font(.appFont(.semiboldBodyLarge))
                .foregroundStyle(Color.textDefault)

            Spacer()

            if let value {
                Text(value)
                    .font(.appFont(.semiboldBodyLarge))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(AppSpacing.row)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.medium)
    }
}
