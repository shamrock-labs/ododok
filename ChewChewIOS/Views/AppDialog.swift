import SwiftUI

/// 시스템 `.alert` / `.confirmationDialog` 대신 사용하는 통일 다이얼로그.
/// iOS 네이티브 alert 스타일(컴팩트, 가로 버튼, 헤어라인 디바이더) + 앱 컬러 토큰.
struct AppDialog: View {
    let title: String
    let message: String?
    let primary: Action
    let secondary: Action?
    let onDismiss: () -> Void

    struct Action {
        let label: String
        let role: ButtonRole?
        let perform: () -> Void

        init(_ label: String, role: ButtonRole? = nil, perform: @escaping () -> Void) {
            self.label = label
            self.role = role
            self.perform = perform
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            buttonRow
        }
        .frame(maxWidth: 320)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.appFont(.bold, size: 17))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            if let message {
                Text(message)
                    .font(.appFont(.semibold, size: 15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
    }

    private var divider: some View {
        Color.hairline.frame(height: 0.5)
    }

    @ViewBuilder
    private var buttonRow: some View {
        Group {
            if let secondary {
                HStack(spacing: 0) {
                    button(secondary, emphasis: .secondary)
                    Color.hairline.frame(width: 0.5)
                    button(primary, emphasis: .primary)
                }
            } else {
                button(primary, emphasis: .primary)
            }
        }
        .frame(height: 44)
        .padding(.bottom, 8)
    }

    private enum Emphasis { case primary, secondary }

    private func button(_ action: Action, emphasis: Emphasis) -> some View {
        Button {
            action.perform()
            onDismiss()
        } label: {
            Text(action.label)
                .font(.appFont(emphasis == .primary ? .bold : .medium, size: 16))
                .foregroundStyle(color(for: action.role))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func color(for role: ButtonRole?) -> Color {
        switch role {
        case .destructive: Color.blush500
        case .cancel:      Color.textSecondary
        default:           Color.acorn700
        }
    }
}

/// `isPresented` 바인딩으로 띄우는 모달 다이얼로그. backdrop 탭으로 닫기.
private struct AppDialogOverlay: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let primary: AppDialog.Action
    let secondary: AppDialog.Action?

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        // backdrop tap = cancel 의도. secondary가 있으면 그 핸들러를 실행.
                        if let secondary { secondary.perform() }
                        isPresented = false
                    }
                AppDialog(
                    title: title,
                    message: message,
                    primary: primary,
                    secondary: secondary,
                    onDismiss: { isPresented = false }
                )
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isPresented)
    }
}

extension View {
    func appDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        primary: AppDialog.Action,
        secondary: AppDialog.Action? = nil
    ) -> some View {
        modifier(AppDialogOverlay(
            isPresented: isPresented,
            title: title,
            message: message,
            primary: primary,
            secondary: secondary
        ))
    }
}

#Preview("Destructive") {
    ZStack {
        Color.pageBackground.ignoresSafeArea()
        Color.black.opacity(0.32).ignoresSafeArea()
        AppDialog(
            title: "계정을 삭제할까요?",
            message: "오도독 계정과 씹기 기록, 도토리, 스트릭이 모두 삭제돼요. 이 작업은 되돌릴 수 없어요.",
            primary: .init("계정 삭제", role: .destructive) {},
            secondary: .init("취소", role: .cancel) {},
            onDismiss: {}
        )
        .padding(.horizontal, 40)
    }
}

#Preview("Single button") {
    ZStack {
        Color.pageBackground.ignoresSafeArea()
        Color.black.opacity(0.32).ignoresSafeArea()
        AppDialog(
            title: "AirPods를 연결해 주세요",
            message: "씹기 분석을 위해 AirPods Pro · AirPods 3/4세대 · AirPods Max 중 하나를 연결하고 착용한 뒤 다시 시도해 주세요.",
            primary: .init("확인") {},
            secondary: nil,
            onDismiss: {}
        )
        .padding(.horizontal, 40)
    }
}
