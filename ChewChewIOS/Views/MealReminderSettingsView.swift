import SwiftUI
import UserNotifications

/// HomeView gear → sheet. 끼니별 Toggle + 시각 picker.
/// 변경 시마다 UserDefaults save + UNUserNotificationCenter 재스케줄.
struct MealReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var settings: MealReminderSettings = .default
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    /// 서버에 저장된 마지막 값 — 저장 실패 시 "취소"로 이 값으로 되돌린다(변경 무성유실 방지, ODO-103).
    @State private var lastSaved: MealReminderSettings = .default
    @State private var saveFailed = false
    @State private var saveErrorReason = ""
    /// lastSaved로 되돌리는 중엔 onChange의 저장 재시도를 건너뛰기 위한 가드.
    @State private var isReverting = false
    /// 저장 디바운스 + latest-wins(PR #76 리뷰). 빠른 편집(DatePicker 스크럽)으로 PUT이 겹쳐
    /// 오래된 응답이 최신 값을 덮어쓰는 경합을 막는다 — 매 편집마다 세대를 올리고, 응답이 현재
    /// 세대와 일치할 때만 캐시·lastSaved를 확정한다.
    @State private var saveTask: Task<Void, Never>?
    @State private var saveGeneration = 0

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
            .navigationTitle("끼니 알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Color.acorn600)
                        .font(.appFont(.semiboldBody))
                }
            }
        }
        .task {
            settings = MealReminderSettings.load()
            lastSaved = settings
            permissionStatus = await MealNotificationService.authorizationStatus()
        }
        .onChange(of: settings) { _, new in
            guard !isReverting else {
                isReverting = false
                return
            }
            scheduleSave(new)
        }
        .appDialog(
            isPresented: $saveFailed,
            title: "저장에 실패했어요",
            message: "\(saveErrorReason)\n취소하면 변경 전 시간으로 돌아가요.",
            primary: .init("다시 시도") { saveNow(settings) },
            secondary: .init("취소", role: .cancel) { revertEdit() }
        )
    }

    // MARK: - 저장 (서버 정본)

    /// 편집 디바운스 — 빠른 변경을 묶어 마지막 값만 저장하고, 대기 중이던 직전 저장은 취소한다.
    private func scheduleSave(_ new: MealReminderSettings) {
        saveTask?.cancel()
        saveGeneration &+= 1
        let generation = saveGeneration
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            await attemptSave(new, generation: generation)
        }
    }

    /// 디바운스 없이 즉시 저장(다시 시도 버튼). 세대를 올려 이전 응답이 못 덮게 한다.
    private func saveNow(_ new: MealReminderSettings) {
        saveTask?.cancel()
        saveGeneration &+= 1
        let generation = saveGeneration
        Task { await attemptSave(new, generation: generation) }
    }

    /// 변경을 서버에 저장 시도. 성공해야 로컬 캐시를 확정한다(무성유실 방지). 실패하면 식사 종료 시
    /// 업로드 실패와 같은 다이얼로그를 띄운다 — 오프라인/서버 다운 모두 여기로 들어온다(ODO-103).
    /// `generation`이 현재 세대와 다르면(그 사이 더 최신 편집이 있었음) 응답을 버린다 — latest-wins(PR #76).
    private func attemptSave(_ new: MealReminderSettings, generation: Int) async {
        let outcome = await appState.mealPushCoordinator.apply(new)
        guard generation == saveGeneration else { return }
        switch outcome {
        case .saved, .skipped:
            new.save()
            lastSaved = new
        case .saveFailed(let reason):
            saveErrorReason = reason
            saveFailed = true
        case .sessionExpired:
            break   // 세션 만료 — AppState가 로그인 게이트로 복귀시킨다
        }
    }

    /// 저장 실패 다이얼로그의 "취소"/배경 탭 — 마지막 저장값으로 화면·로컬을 되돌린다.
    private func revertEdit() {
        saveTask?.cancel()
        saveGeneration &+= 1   // 진행 중이던 저장 응답을 무효화(되돌림이 최신)
        guard settings != lastSaved else { return }
        isReverting = true
        settings = lastSaved
        lastSaved.save()
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
            }

            if slot.wrappedValue.enabled {
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
                }
            }
        }
        .padding(AppSpacing.cardContent)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.medium)
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
