import SwiftUI

struct AppCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.reportCard
    var radius: CGFloat = AppRadius.lg
    var background: Color = Color.bgCard
    var elevation: AppElevation = .flat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: radius))
            .appElevation(elevation)
    }
}

struct AppSectionHeader: View {
    let title: String
    var trailing: String?
    var trailingColor: Color = Color.textMuted

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.appFont(.sectionTitle))
                .foregroundStyle(Color.textDefault)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.appFont(.heavyCaption))
                    .foregroundStyle(trailingColor)
                    .monospacedDigit()
            }
        }
    }
}
