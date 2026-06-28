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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.acorn600)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(title)
                    .font(.appFont(.heavy, size: 24))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let subtitle {
                    Text(subtitle)
                        .font(.appFont(.semibold, size: 13))
                        .foregroundStyle(Color.ink600)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .neuoShadow(.sm)
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
        HStack(spacing: 4) {
            switch icon {
            case .text(let symbol):
                Text(symbol)
                    .font(.appFont(.regular, size: 12))
            case .open(let icon):
                OpenIconView(icon: icon, color: tint, lineWidth: 2.2)
                    .frame(width: 14, height: 14)
            }
            Text(value)
                .font(.appFont(.heavy, size: 13))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink600)
                .frame(width: 32, height: 32)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if showsBadge {
                Circle()
                    .fill(Color.blush500)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.cream, lineWidth: 1.4))
                    .offset(x: -3, y: 4)
            }
        }
    }
}
