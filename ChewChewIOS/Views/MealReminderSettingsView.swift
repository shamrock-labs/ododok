import SwiftUI
import UIKit
import UserNotifications

/// HomeView gear → sheet. 끼니별 Toggle + 시각 picker.
/// 변경은 draft에만 보관하고, 완료 버튼을 눌렀을 때만 서버/로컬 알림에 저장한다.
struct MealReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @State private var settings: MealReminderSettings = .default
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    /// 서버에 저장된 마지막 값 — 저장 실패 시 "취소"로 이 값으로 되돌린다(변경 무성유실 방지, ODO-103).
    @State private var lastSaved: MealReminderSettings = .default
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var saveErrorReason = ""
    @State private var showDiscardConfirmation = false

    private var draft: MealReminderDraft {
        MealReminderDraft(settings: settings, lastSaved: lastSaved)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.four) {
                    if permissionStatus == .denied {
                        deniedBanner
                    }
                    mealCard(title: "아침", icon: .sunrise, tint: .butter600, slot: $settings.breakfast)
                    mealCard(title: "점심", icon: .utensils, tint: .sage600, slot: $settings.lunch)
                    mealCard(title: "저녁", icon: .moonStar, tint: .blush500, slot: $settings.dinner)
                    mealCard(title: "추가 1", icon: .utensils, tint: .acorn600, slot: $settings.extra1)
                    mealCard(title: "추가 2", icon: .moonStar, tint: .acorn700, slot: $settings.extra2)
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
                    AppSheetTextActionButton(title: "완료") { saveAndDismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .task {
            settings = MealReminderSettings.load()
            lastSaved = settings
            await refreshPermissionStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshPermissionStatus() }
        }
        .interactiveDismissDisabled(draft.hasUnsavedChanges)
        .background {
            SheetDismissAttemptReporter(isEnabled: draft.hasUnsavedChanges) {
                showDiscardConfirmation = true
            }
        }
        .appDialog(
            isPresented: $saveFailed,
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

    // MARK: - 저장 (서버 정본)

    private func saveAndDismiss() {
        guard !isSaving else { return }
        isSaving = true
        let draft = settings
        Task { @MainActor in
            let outcome = await appState.mealPushCoordinator.apply(draft)
            isSaving = false
            switch outcome {
            case .saved, .skipped:
                draft.save()
                lastSaved = draft
                dismiss()
            case .saveFailed(let reason):
                saveErrorReason = reason
                saveFailed = true
            case .sessionExpired:
                break
            }
        }
    }

    /// 저장 실패 다이얼로그의 "취소"/배경 탭 — 마지막 저장값으로 화면·로컬을 되돌린다.
    private func revertEdit() {
        guard settings != lastSaved else { return }
        settings = lastSaved
        lastSaved.save()
    }

    private func discardAndDismiss() {
        settings = lastSaved
        dismiss()
    }

    @MainActor
    private func refreshPermissionStatus() async {
        permissionStatus = await MealNotificationService.authorizationStatus()
        if permissionStatus == .denied {
            settings.disableAll()
        }
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

    private func mealCard(title: String, icon: OpenIcon, tint: Color, slot: Binding<MealSlot>) -> some View {
        VStack(spacing: AppSpacing.three) {
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
                    .disabled(permissionStatus == .denied || isSaving)
            }

            if slot.wrappedValue.enabled && permissionStatus != .denied {
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
                    .disabled(permissionStatus == .denied || isSaving)
                }
            }
        }
        .padding(AppSpacing.cardContent)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.flat)
    }

    // MARK: - Bindings

    /// Toggle ON 시 권한 미결정이면 다이얼로그를 띄우고, 권한 거부 상태면 토글이 켜지지 않도록 가드.
    private func toggleBinding(_ slot: Binding<MealSlot>) -> Binding<Bool> {
        Binding(
            get: { slot.wrappedValue.enabled && permissionStatus != .denied },
            set: { newValue in
                if newValue {
                    // 이미 denied면 다이얼로그 못 띄움 — banner로 안내만.
                    guard permissionStatus != .denied else { return }
                    Task {
                        let ok = await MealNotificationService.requestAuthorizationIfNeeded()
                        let status = await MealNotificationService.authorizationStatus()
                        await MainActor.run {
                            permissionStatus = status
                            if ok {
                                slot.wrappedValue.enabled = true
                            }
                        }
                    }
                } else {
                    slot.wrappedValue.enabled = false
                }
            }
        )
    }

    /// hour/minute → Date 양방향 변환.
    private func timeBinding(_ slot: Binding<MealSlot>) -> Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = slot.wrappedValue.hour
                comps.minute = slot.wrappedValue.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                slot.wrappedValue.hour = comps.hour ?? slot.wrappedValue.hour
                slot.wrappedValue.minute = comps.minute ?? slot.wrappedValue.minute
            }
        )
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
