import SwiftUI

struct TabBarView: View {
    @Binding var selection: ContentView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                let active = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: AppSpacing.microGap) {
                        Image(systemName: tab.systemImage)
                            .font(.appFont(active ? .bold : .regular, size: Metrics.icon))
                            .foregroundStyle(active ? Color.textActionStrong : Color.textSubtle)
                        Text(tab.label)
                            .font(.appFont(.boldMicroTiny))
                            .foregroundStyle(active ? Color.textAction : Color.textSubtle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.oneHalf)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, AppSpacing.gapTight)
        .padding(.bottom, AppSpacing.gapTight)
        .padding(.horizontal, AppSpacing.four)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.borderSelected.opacity(0.6))
                .frame(height: AppSize.border)
        }
    }
}

private enum Metrics {
    static let icon: CGFloat = 22
}
