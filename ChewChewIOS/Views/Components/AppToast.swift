import SwiftUI

struct AppToastMessage: Identifiable, Equatable {
    enum Kind {
        case success
        case warning
        case danger
        case info
    }

    let id = UUID()
    let text: String
    let kind: Kind

    init(_ text: String, kind: Kind = .info) {
        self.text = text
        self.kind = kind
    }
}

struct AppToast: View {
    let message: AppToastMessage

    var body: some View {
        HStack(spacing: AppSpacing.two) {
            Image(systemName: message.kind.systemImage)
                .font(.appFont(.boldCallout))
                .frame(width: AppSize.toastIcon, height: AppSize.toastIcon)

            Text(message.text)
                .font(.appFont(.boldCallout))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.textActionInverse)
        .padding(.horizontal, AppSpacing.toastH)
        .padding(.vertical, AppSpacing.toastV)
        .background(message.kind.background, in: RoundedRectangle(cornerRadius: AppRadius.elementLarge))
        .softShadow(.lg)
    }
}

private struct AppToastModifier: ViewModifier {
    @Binding var toast: AppToastMessage?
    var bottomPadding: CGFloat
    var duration: TimeInterval

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    AppToast(message: toast)
                        .padding(.bottom, bottomPadding)
                        .padding(.horizontal, AppSpacing.page)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(
                .spring(response: AppMotion.springToastResponse, dampingFraction: AppMotion.springToastDampingFraction),
                value: toast?.id
            )
            .onChange(of: toast?.id) { _, _ in
                scheduleDismiss()
            }
            .onDisappear {
                dismissTask?.cancel()
            }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard toast != nil else { return }

        dismissTask = Task {
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                toast = nil
            }
        }
    }
}

extension View {
    func appToast(
        _ toast: Binding<AppToastMessage?>,
        bottomPadding: CGFloat = AppSpacing.overlayBottom,
        duration: TimeInterval = AppMotion.durationToast
    ) -> some View {
        modifier(AppToastModifier(toast: toast, bottomPadding: bottomPadding, duration: duration))
    }
}

private extension AppToastMessage.Kind {
    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var background: Color {
        switch self {
        case .success: Color.statusSuccess
        case .warning: Color.statusWarning
        case .danger: Color.statusDanger
        case .info: Color.textDefault
        }
    }
}
