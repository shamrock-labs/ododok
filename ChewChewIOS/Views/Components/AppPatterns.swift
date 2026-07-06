import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: AppMotion.durationButtonPress), value: configuration.isPressed)
    }
}

struct AppActionButton<Label: View>: View {
    let action: () -> Void
    var foreground: Color = Color.controlOnAccent
    var background: AnyShapeStyle = AnyShapeStyle(Color.textActionStrong)
    var radius: CGFloat = AppRadius.elementLarge
    var verticalPadding: CGFloat = AppSpacing.inputVLarge
    var horizontalPadding: CGFloat = AppSpacing.none
    var isFullWidth = true
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(foreground)
                .frame(maxWidth: isFullWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(background, in: RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct AppTextActionButton: View {
    let title: String
    var icon: String?
    var font: Font.Role = .boldTitle
    var spacing: CGFloat = AppSpacing.gap
    var foreground: Color = Color.controlOnAccent
    var background: AnyShapeStyle = AnyShapeStyle(Color.textActionStrong)
    var radius: CGFloat = AppRadius.elementLarge
    var verticalPadding: CGFloat = AppSpacing.inputVLarge
    let action: () -> Void

    var body: some View {
        AppActionButton(
            action: action,
            foreground: foreground,
            background: background,
            radius: radius,
            verticalPadding: verticalPadding
        ) {
            HStack(spacing: spacing) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.appFont(font))
        }
    }
}

struct AppBadge: View {
    let text: String
    var foreground: Color = Color.textAction
    var background: Color = Color.bgSunken
    var font: Font.Role = .boldMicro
    var horizontalPadding: CGFloat = AppSpacing.oneHalf
    var verticalPadding: CGFloat = AppSpacing.half

    var body: some View {
        Text(text)
            .font(.appFont(font))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background, in: Capsule())
    }
}

struct AppEmptyState<Visual: View>: View {
    var spacing: CGFloat = AppSpacing.gap
    var title: String
    var message: String?
    var titleFont: Font.Role = .heavyHeadline
    var messageFont: Font.Role = .semiboldCallout
    var titleColor: Color = Color.textDefault
    var messageColor: Color = Color.textMuted
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        VStack(spacing: spacing) {
            visual()
            VStack(spacing: AppSpacing.oneHalf) {
                Text(title)
                    .font(.appFont(titleFont))
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.appFont(messageFont))
                        .foregroundStyle(messageColor)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct AppSheetTitleText: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.appFont(.boldHeadline))
            .foregroundStyle(Color.textDefault)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

struct AppSheetHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            AppSheetTitleText(title: title)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                trailing()
            }
        }
        .frame(height: AppSize.dialogActionHeight)
    }
}

struct AppSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.appFont(.semibold, size: AppSize.iconCompact))
                .foregroundStyle(Color.textMuted)
                .frame(width: AppSize.controlXLarge, height: AppSize.controlXLarge)
                .background(Color.controlOnSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("닫기")
    }
}

struct AppSheetTextActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.appFont(.semiboldBody))
            .foregroundStyle(Color.tintInteractive)
            .padding(.horizontal, AppSpacing.four)
            .frame(height: AppSize.dialogActionHeight)
            .background(Color.controlOnSurface, in: Capsule())
    }
}
