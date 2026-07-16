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

struct AppSheetTextActionButton: View {
    let title: String
    var isProcessing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(isProcessing ? 0 : 1)
                if isProcessing {
                    ProgressView()
                        .tint(Color.tintInteractive)
                }
            }
            .font(.appFont(.semiboldBody))
            .foregroundStyle(Color.tintInteractive)
            .padding(.horizontal, AppSpacing.four)
            .frame(height: AppSize.dialogActionHeight)
            .background(Color.controlOnSurface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}

/// 기록과 스트릭 캘린더가 공유하는 날짜 상태 링.
/// 식사 기록은 분할 링을, 하루 단위 스트릭은 연속 링을 같은 시각 토큰으로 표현한다.
struct CalendarStatusRingStyle: Equatable {
    let baseLineWidth: CGFloat
    let progressLineWidth: CGFloat

    static let standard = Self(baseLineWidth: 3, progressLineWidth: 3.2)
    static let streak = Self(baseLineWidth: 1.5, progressLineWidth: 2)
}

struct CalendarStatusRing: View {
    let completedSegments: Int
    let totalSegments: Int
    let accent: Color
    var fill: Color = .clear
    var style: CalendarStatusRingStyle = .standard

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            Circle()
                .stroke(Color.hairline, lineWidth: style.baseLineWidth)

            if totalSegments == 1, completedSegments > 0 {
                Circle()
                    .stroke(
                        accent,
                        style: StrokeStyle(
                            lineWidth: style.progressLineWidth,
                            lineCap: .round
                        )
                    )
            } else if totalSegments > 1 {
                ForEach(0..<totalSegments, id: \.self) { index in
                    Circle()
                        .trim(
                            from: CGFloat(index) / CGFloat(totalSegments) + RingMetrics.segmentGap,
                            to: CGFloat(index + 1) / CGFloat(totalSegments) - RingMetrics.segmentGap
                        )
                        .stroke(
                            index < completedSegments ? accent : Color.clear,
                            style: StrokeStyle(
                                lineWidth: style.progressLineWidth,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }
}

private enum RingMetrics {
    static let segmentGap: CGFloat = 0.018
}
