import SwiftUI
import UserNotifications

/// HomeView gear → sheet. 끼니별 Toggle + 시각 picker.
/// 변경 시마다 UserDefaults save + UNUserNotificationCenter 재스케줄.
struct MealReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var settings: MealReminderSettings = .default
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if permissionStatus == .denied {
                        deniedBanner
                    }
                    mealCard(title: "아침", icon: .sunrise, tint: .butter600, slot: $settings.breakfast)
                    mealCard(title: "점심", icon: .utensils, tint: .sage600, slot: $settings.lunch)
                    mealCard(title: "저녁", icon: .moonStar, tint: .blush500, slot: $settings.dinner)
                    mealCard(title: "추가 1", icon: .utensils, tint: .acorn600, slot: $settings.extra1)
                    mealCard(title: "추가 2", icon: .moonStar, tint: .acorn700, slot: $settings.extra2)
                    footerHint
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("끼니 알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Color.acorn600)
                        .font(.appFont(.semibold, size: 15))
                }
            }
        }
        .task {
            settings = MealReminderSettings.load()
            permissionStatus = await MealNotificationService.authorizationStatus()
        }
        .onChange(of: settings) { _, new in
            new.save()
            // 서버/로컬 전환은 조정자가 정책에 맞게 처리(로그인·권한·토큰 상태 기준).
            Task { await appState.mealPushCoordinator.apply(new) }
        }
    }

    // MARK: - Subviews

    private var deniedBanner: some View {
        VStack(spacing: 4) {
            Text("알림 권한이 꺼져 있어요")
                .font(.appFont(.bold, size: 14))
                .foregroundStyle(Color.textPrimary)
            Text("iOS 설정 → Ododok → 알림 켜기.")
                .font(.appFont(.semibold, size: 14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.blush100, in: RoundedRectangle(cornerRadius: 14))
    }

    private var footerHint: some View {
        Text("설정한 시각에 다람이가 식사 알림을 보내줘요.\n끄면 해당 끼니는 알림이 안 와요.")
            .font(.appFont(.semibold, size: 14))
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    private func mealCard(title: String, icon: OpenIcon, tint: Color, slot: Binding<MealSlot>) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 9) {
                    OpenIconView(icon: icon, color: tint, lineWidth: 2.1)
                        .frame(width: 20, height: 20)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                    Text(title)
                        .font(.appFont(.bold, size: 17))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Toggle("", isOn: toggleBinding(slot))
                    .labelsHidden()
                    .tint(Color.acorn600)
            }

            if slot.wrappedValue.enabled {
                HStack {
                    Text("알림 시각")
                        .font(.appFont(.semibold, size: 15))
                        .foregroundStyle(Color.textSecondary)
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
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
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
