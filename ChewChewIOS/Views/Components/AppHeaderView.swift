import SwiftUI

struct AppHeaderView<Accessory: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    private let accessory: Accessory

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.gap) {
            VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.appFont(.boldCaption))
                        .foregroundStyle(Color.textActionStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(title)
                    .font(.appFont(.heavyDisplaySmall))
                    .foregroundStyle(Color.textDefault)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let subtitle {
                    Text(subtitle)
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, AppSpacing.cardH)
        .padding(.vertical, AppSpacing.cardV)
        .background(Color.bgSurface.opacity(0.84), in: RoundedRectangle(cornerRadius: AppSpacing.dialogH))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.dialogH)
                .stroke(Color.bgSurface.opacity(0.85), lineWidth: AppSize.border)
        )
        .appElevation(.medium)
    }
}

extension AppHeaderView where Accessory == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct HeaderMetricPill: View {
    private enum MetricIcon {
        case text(String)
        case open(OpenIcon)
    }

    private let icon: MetricIcon
    let value: String
    let tint: Color

    init(icon: String, value: String, tint: Color) {
        self.icon = .text(icon)
        self.value = value
        self.tint = tint
    }

    init(icon: OpenIcon, value: String, tint: Color) {
        self.icon = .open(icon)
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: AppSpacing.one) {
            switch icon {
            case .text(let symbol):
                Text(symbol)
                    .font(.appFont(.regularCaption))
            case .open(let icon):
                OpenIconView(icon: icon, color: tint, lineWidth: 2.2)
                    .frame(width: Metrics.pillIcon, height: Metrics.pillIcon)
            }
            Text(value)
                .font(.appFont(.heavyCallout))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, AppSpacing.iconGap)
        .frame(height: Metrics.pillHeight)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct HeaderIconButton: View {
    let systemName: String
    var showsBadge = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.appFont(.semibold, size: Metrics.icon))
                .foregroundStyle(Color.textMuted)
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .background(Color.bgSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if showsBadge {
                Circle()
                    .fill(Color.statusDanger)
                    .frame(width: Metrics.badge, height: Metrics.badge)
                    .overlay(Circle().stroke(Color.cream, lineWidth: 1.4))
                    .offset(x: -3, y: 4)
            }
        }
    }
}

private enum Metrics {
    static let iconButton = AppSize.controlLarge
    static let icon = AppSize.iconMedium
    static let badge = AppSize.indicatorMedium
    static let pillIcon = AppSize.iconCompact
    static let pillHeight = AppSize.iconContainerCompact
}
