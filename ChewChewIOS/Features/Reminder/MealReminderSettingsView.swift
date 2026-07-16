import SwiftUI
import UIKit
import UserNotifications

/// HomeView gear → sheet. 끼니별 Toggle + 시각 picker.
/// 변경은 draft에만 보관하고, 완료 버튼을 눌렀을 때만 서버/로컬 알림에 저장한다.
struct MealReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @State private var showDiscardConfirmation = false

    private var store: ReminderStore { appState.reminders }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.four) {
                    if store.permissionStatus == .denied {
                        deniedBanner
                    }
                    mealCard(title: "아침", icon: .sunrise, tint: .butter600, slot: .breakfast)
                    mealCard(title: "점심", icon: .utensils, tint: .sage600, slot: .lunch)
                    mealCard(title: "저녁", icon: .moonStar, tint: .blush500, slot: .dinner)
                    footerHint
                    Spacer(minLength: AppSpacing.six)
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.three)
            }
            .background(Color.bgPage.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppSheetTitleText(title: "끼니 알림")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetTextActionButton(
                        title: "완료",
                        isProcessing: store.saveState.isSaving
                    ) {
                        saveAndDismiss()
                    }
                }
            }
        }
        .task {
            await store.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshPermissionStatus() }
        }
        .interactiveDismissDisabled(store.hasUnsavedChanges)
        .background {
            SheetDismissAttemptReporter(isEnabled: store.hasUnsavedChanges) {
                showDiscardConfirmation = true
            }
        }
        .appDialog(
            isPresented: saveFailedBinding,
            title: "저장에 실패했어요",
            message: "\(saveErrorReason)\n취소하면 변경 전 시간으로 돌아가요.",
            primary: .init("다시 시도") { saveAndDismiss() },
            secondary: .init("취소", role: .cancel) { revertEdit() }
        )
        .appDialog(
            isPresented: $showDiscardConfirmation,
            title: "알림 설정을 완료하지 않았어요",
            message: "완료 버튼을 누르지 않으면 변경사항이 저장되지 않아요.",
            primary: .init("저장하지 않기", role: .destructive) { discardAndDismiss() },
            secondary: .init("계속 편집", role: .cancel) {}
        )
    }

    // MARK: - 저장

    private func saveAndDismiss() {
        Task { @MainActor in
            if await store.saveAndFinish() {
                dismiss()
            }
        }
    }

    /// 저장 실패 다이얼로그의 "취소"/배경 탭 — 마지막 저장값으로 화면·로컬을 되돌린다.
    private func revertEdit() {
        store.revertEdit()
    }

    private func discardAndDismiss() {
        store.discardChanges()
        dismiss()
    }

    // MARK: - Subviews

    private var deniedBanner: some View {
        VStack(spacing: AppSpacing.one) {
            Text("알림 권한이 꺼져 있어요")
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textDefault)
            Text("iOS 설정 → Ododok → 알림 켜기.")
                .font(.appFont(.semiboldLabel))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.cell)
        .background(Color.statusDangerMuted, in: RoundedRectangle(cornerRadius: AppRadius.element))
    }

    private var footerHint: some View {
        Text("설정한 시각에 다람이가 식사 알림을 보내줘요.\n끄면 해당 끼니는 알림이 안 와요.")
            .font(.appFont(.semiboldLabel))
            .foregroundStyle(Color.textMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    private func mealCard(title: String, icon: OpenIcon, tint: Color, slot: ReminderSlot) -> some View {
        let mealSlot = store.slot(slot)
        return VStack(spacing: AppSpacing.three) {
            HStack {
                HStack(spacing: AppSpacing.iconGap) {
                    OpenIconView(icon: icon, color: tint, lineWidth: 2.1)
                        .frame(width: AppSpacing.five, height: AppSpacing.five)
                        .frame(width: AppSize.iconContainer, height: AppSize.iconContainer)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: AppRadius.iconContainer))
                    Text(title)
                        .font(.appFont(.boldHeadline))
                        .foregroundStyle(Color.textDefault)
                }
                Spacer()
                Toggle("", isOn: toggleBinding(slot))
                    .labelsHidden()
                    .tint(Color.acorn600)
                    .disabled(store.permissionStatus == .denied || store.saveState.isSaving)
            }

            if mealSlot.enabled && store.permissionStatus != .denied {
                HStack {
                    Text("알림 시각")
                        .font(.appFont(.semiboldBody))
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    DatePicker(
                        "",
                        selection: timeBinding(slot),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color.acorn600)
                    .disabled(store.permissionStatus == .denied || store.saveState.isSaving)
                }
            }
        }
        .padding(AppSpacing.cardContent)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.flat)
    }

    // MARK: - Bindings

    /// Toggle ON 시 권한 미결정이면 다이얼로그를 띄우고, 권한 거부 상태면 토글이 켜지지 않도록 가드.
    private func toggleBinding(_ slot: ReminderSlot) -> Binding<Bool> {
        Binding(
            get: { store.slot(slot).enabled && store.permissionStatus != .denied },
            set: { newValue in
                Task {
                    await store.toggleSlot(slot, isEnabled: newValue)
                }
            }
        )
    }

    /// hour/minute → Date 양방향 변환.
    private func timeBinding(_ slot: ReminderSlot) -> Binding<Date> {
        Binding(
            get: {
                store.date(for: slot)
            },
            set: { newDate in
                store.updateTime(slot, to: newDate)
            }
        )
    }

    private var saveFailedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = store.saveState { return true }
                return false
            },
            set: { _ in }
        )
    }

    private var saveErrorReason: String {
        if case .failed(let reason) = store.saveState {
            return reason
        }
        return ""
    }
}

private struct SheetDismissAttemptReporter: UIViewControllerRepresentable {
    let isEnabled: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onAttempt = onAttempt
        DispatchQueue.main.async {
            uiViewController.parent?.presentationController?.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onAttempt: onAttempt)
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isEnabled: Bool
        var onAttempt: () -> Void

        init(isEnabled: Bool, onAttempt: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onAttempt = onAttempt
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if isEnabled {
                onAttempt()
            }
        }
    }
}
