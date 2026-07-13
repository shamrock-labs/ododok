import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state

    private var home: HomeStore { state.home }
    private var mealSession: MealSessionRuntimeStore { state.mealSession }

    // MARK: - 측정 시작 햅틱 trigger
    @State private var hapticTrigger = false
    @State private var chewAcornPulses: [ChewAcornPulse] = []

    // MARK: - 끼니 알림 설정 sheet
    @State private var showMealReminderSettings = false
    @State private var showRewardHistory = false

    // MARK: - 설정 sheet (REQ-05)
    @State private var showSettings = false
    /// 야간 시간대 판정에 쓰는 현재 시각 — 60초마다 갱신해 22:00·06:00 경계에서 stale을 방지.
    @State private var nowTick = Date()

    var body: some View {
        VStack(spacing: AppSpacing.cardH) {
            topBar
            squirrelCard
                .frame(maxHeight: .infinity)
            mealToggleButton
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.verticalLoose)
        .padding(.bottom, AppSpacing.verticalLoose)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { newDate in
            nowTick = newDate
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: mealSession.pendingMealStartRequest) { _, requested in
            // 끼니 리마인더 알림의 "식사 시작" 액션 — 시작 가드를 그대로 태운다.
            guard requested else { return }
            _ = mealSession.consumePendingMealStartRequest()
            if !mealSession.isEating { handleMealToggle() }
        }
        .onAppear {
            // 콜드스타트로 열려 onChange를 놓친 경우 보완.
            if mealSession.consumePendingMealStartRequest() {
                if !mealSession.isEating { handleMealToggle() }
            }
        }
        .onDisappear {
            clearChewAcornPulses()
        }
        .onChange(of: state.animKey) { _, key in
            guard mealSession.phase.showsChewFeedback else {
                clearChewAcornPulses()
                return
            }
            addChewAcornPulse(for: key)
        }
        .onChange(of: mealSession.phase) { _, phase in
            if !phase.showsChewFeedback {
                clearChewAcornPulses()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .sheet(isPresented: $showMealReminderSettings) {
            MealReminderSettingsView()
        }
        .sheet(isPresented: $showRewardHistory) {
            RewardHistorySheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - 식사 시작 가드

    private func handleMealToggle() {
        if mealSession.isEating {
            // 최소 분석 시간 전이면 사용자에게 "더 측정할까요?" 확인 후 처리.
            let duration = Date().timeIntervalSince(mealSession.eatingStartedAt ?? Date())
            if duration < MealSessionReportability.minDurationSec {
                mealSession.requestShortSessionConfirmation()
                return
            }
            mealSession.toggleEating()
            return
        }

        #if targetEnvironment(simulator)
        hapticTrigger.toggle()
        mealSession.toggleEating()
        #else
        mealSession.beginMealStartAfterAirPodsReadiness {
            hapticTrigger.toggle()
        } onFinished: {
            mealSession.toggleEating()
        }
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        AppHeaderView(eyebrow: todayLabel, title: "오도독", subtitle: homeHeaderSubtitle) {
            HStack(spacing: 7) {
                HeaderMetricPill(icon: .flame, value: "\(home.currentStreak)", tint: .statusWarning)
                Button {
                    showRewardHistory = true
                } label: {
                    HeaderMetricPill(icon: .acorn, value: home.points.koLocale, tint: .rewardAcorn)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("RewardHistoryButton")
                HeaderIconButton(systemName: "bell", showsBadge: true) {
                    showMealReminderSettings = true
                }
                HeaderIconButton(systemName: "gearshape") {
                    showSettings = true
                }
            }
            .offset(y: -8)
        }
    }

    private var homeHeaderSubtitle: String? {
        if mealSession.isEating {
            return mealSession.imuWaveformSource.usesRealMotion ? "식사 중 · AirPods LIVE" : "식사 중 · MVP 모드"
        }
        // 오늘 저작 횟수는 화면 중앙 표시와 중복이라 헤더 서브타이틀에서 제외.
        return nil
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "오늘 · M월 d일"
        return formatter.string(from: Date())
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.appFont(.mediumHeadline))
                .foregroundStyle(Color.textMuted)
                .frame(width: Metrics.circleButton, height: Metrics.circleButton)
                .background(Color.bgSurface, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Streak + Points

    private var statRow: some View {
        HStack(spacing: 14) {
            statCard(
                label: home.freezeInventory > 0 ? "연속 출석 · 🛡️\(home.freezeInventory)" : "연속 출석",
                value: "\(home.currentStreak)일째",
                iconBG: Color.statusDangerMuted
            ) {
                OpenIconView(icon: .flame, color: .statusDanger, lineWidth: 2.2)
                    .frame(width: Metrics.statIcon, height: Metrics.statIcon)
            }

            statCard(
                label: "보유 도토리",
                value: home.points.koLocale,
                iconBG: Color.statusWarningMuted
            ) {
                OpenIconView(icon: .acorn, color: .rewardAcorn, lineWidth: 2.1)
                    .frame(width: Metrics.statIcon, height: Metrics.statIcon)
            }
        }
    }

    private func statCard<I: View>(
        label: String,
        value: String,
        iconBG: Color,
        @ViewBuilder icon: () -> I
    ) -> some View {
        HStack(spacing: AppSpacing.inner) {
            iconBG
                .frame(width: Metrics.statIconBg, height: Metrics.statIconBg)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.statIconRadius))
                .overlay { icon() }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
                Text(value)
                    .font(.appFont(.boldHeadline))
                    .foregroundStyle(Color.textDefault)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.flat)
    }

    // MARK: Squirrel card

    private var squirrelCard: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            ZStack {
                if !mealSession.isEating {
                    Circle()
                        .stroke(Color.borderDefault, lineWidth: 5)
                        .frame(width: Metrics.progressRing, height: Metrics.progressRing)
                    Circle()
                        .trim(from: 0, to: home.todayProgress)
                        .stroke(
                            Color.dataChew,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: Metrics.progressRing, height: Metrics.progressRing)
                        .rotationEffect(.degrees(-90))
                }
                SquirrelView(
                    // 식사 중엔 isEating이 다람이를 DaramEating(우물거리는 모습)으로 바꾸고
                    // animKey 펄스가 씹는 모션을 준다. status.mood는 실시간 값이 아니라(완료 세션
                    // 기준) 식사 중엔 0=sleepy로 떨어져 💤이 끼므로, 여기선 happy로 고정한다.
                    mood: .happy,
                    hat: state.equippedHatItem,
                    glasses: state.equippedGlassesItem,
                    acc: state.equippedAccItem,
                    animKey: state.animKey,
                    isEating: mealSession.isEating,
                    isNight: isNightTime
                )
                .scaleEffect(1.5)

                ForEach(chewAcornPulses) { pulse in
                    ChewAcornPulseView(pulse: pulse)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(height: Metrics.squirrelAreaHeight)

            VStack(spacing: 4) {
                Text(mealSession.isEating ? "맛있게 먹는 중이에요" : home.status.title)
                    .font(.appFont(.boldTitleCompact))
                    .foregroundStyle(Color.textDefault)
                if !mealSession.isEating {
                    Text("오늘 \(home.todayRealChewCount.koLocale) / \(Constants.dailyGoal.koLocale)회")
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.four)
        .padding(.vertical, AppSpacing.four)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Metrics.squirrelCardMinHeight)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: Metrics.squirrelCardRadius))
        .appElevation(.flat)
    }

    // MARK: Meal toggle button

    private var mealToggleButton: some View {
        Button {
            handleMealToggle()
        } label: {
            HStack(spacing: AppSpacing.gap) {
                Image(systemName: mealSession.isEating ? "stop.fill" : "fork.knife")
                    .font(.appFont(.boldTitleLarge))
                Text(mealSession.isEating ? "식사 종료" : "식사 시작")
                    .font(.appFont(.boldTitle))
            }
            .foregroundStyle(Color.controlOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.actionV)
            .background(
                LinearGradient(
                    colors: mealSession.isEating
                        ? Color.mealStopGradient
                        : Color.mealStartGradient,
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Metrics.mealButtonRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.mealButtonRadius)
                    .strokeBorder(
                        Color.controlOnAccent.opacity(mealSession.startButtonHighlighted ? 0.9 : 0),
                        lineWidth: Metrics.mealButtonHighlightBorder
                    )
            )
        }
        .accessibilityIdentifier("MealToggle")
        .accessibilityLabel(mealSession.isEating ? "식사 종료" : "식사 시작")
        .buttonStyle(PressableButtonStyle())
        .scaleEffect(mealSession.startButtonHighlighted ? 1.04 : 1.0)
        .shadow(color: Color.highlightShadow.opacity(mealSession.startButtonHighlighted ? 0.55 : 0), radius: 14, x: 0, y: 4)
        .animation(.easeInOut(duration: AppMotion.durationStateChange), value: mealSession.isEating)
        .animation(
            .spring(response: AppMotion.springPlayfulResponse, dampingFraction: AppMotion.springPlayfulDamping),
            value: mealSession.startButtonHighlighted
        )
    }

    private func addChewAcornPulse(for key: Int) {
        let pulse = ChewAcornPulse.make(for: key)
        withAnimation(.spring(response: AppMotion.springFastResponse, dampingFraction: AppMotion.springDampingFraction)) {
            chewAcornPulses.append(pulse)
            if chewAcornPulses.count > Metrics.maxChewAcornPulses {
                chewAcornPulses.removeFirst(chewAcornPulses.count - Metrics.maxChewAcornPulses)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Metrics.chewAcornLifetime))
            withAnimation(.easeOut(duration: AppMotion.durationButtonPress)) {
                chewAcornPulses.removeAll { $0.id == pulse.id }
            }
        }
    }

    private func clearChewAcornPulses() {
        guard !chewAcornPulses.isEmpty else { return }
        chewAcornPulses.removeAll()
    }
}

private struct ChewAcornPulse: Identifiable, Equatable {
    let id = UUID()
    let offset: CGSize

    static func make(for key: Int) -> ChewAcornPulse {
        let positions = [
            CGSize(width: -76, height: -52),
            CGSize(width: 72, height: -62),
            CGSize(width: -58, height: 34),
            CGSize(width: 66, height: 28),
        ]
        let index = ((key % positions.count) + positions.count) % positions.count
        return ChewAcornPulse(offset: positions[index])
    }
}

private struct ChewAcornPulseView: View {
    let pulse: ChewAcornPulse

    @State private var appeared = false
    @State private var disappearing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.acorn100.opacity(0.92))
                .frame(width: Metrics.acornBubbleSize, height: Metrics.acornBubbleSize)
                .overlay {
                    Circle()
                        .stroke(Color.surface.opacity(0.9), lineWidth: AppSize.border)
                }
                .shadow(color: Color.highlightShadow.opacity(0.2), radius: 8, x: 0, y: 5)

            OpenIconView(icon: .acorn, color: .rewardAcorn, lineWidth: 2.1)
                .frame(width: Metrics.acornIconSize, height: Metrics.acornIconSize)
        }
        .scaleEffect(appeared ? (disappearing ? 0.82 : 1.05) : 0.45)
        .opacity(appeared ? (disappearing ? 0 : 1) : 0)
        .offset(
            x: pulse.offset.width,
            y: pulse.offset.height + (appeared ? -18 : 4) + (disappearing ? -16 : 0)
        )
        .animation(.spring(response: AppMotion.springPlayfulResponse, dampingFraction: AppMotion.springPlayfulDamping), value: appeared)
        .animation(.easeOut(duration: AppMotion.durationStateChange), value: disappearing)
        .onAppear {
            appeared = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.68))
                disappearing = true
            }
        }
    }
}

private struct RewardHistorySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var home: HomeStore { state.home }

    var body: some View {
        VStack(spacing: AppSpacing.five) {
            sheetHeader
            content
        }
        .padding(.horizontal, AppSpacing.sheetContent)
        .padding(.top, AppSpacing.four)
        .padding(.bottom, AppSpacing.cardOuterBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgPage.ignoresSafeArea())
        .task {
            await home.fetchRewardHistory()
        }
    }

    private var sheetHeader: some View {
        AppSheetHeader(title: "도토리 적립 내역") {
            AppSheetTextActionButton(title: "닫기") { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch home.rewardHistoryLoadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: AppSpacing.two) {
                Text("내역을 불러오지 못했어요")
                    .font(.appFont(.boldHeadline))
                    .foregroundStyle(Color.textDefault)
                Button("다시 시도") {
                    Task { await home.fetchRewardHistory() }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.four)
                .frame(height: AppSize.dialogActionHeight)
                .background(Color.controlOnSurface, in: Capsule())
                .font(.appFont(.semiboldBody))
                .foregroundStyle(Color.tintInteractive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if home.rewardHistory.isEmpty {
                VStack(spacing: AppSpacing.two) {
                    OpenIconView(icon: .acorn, color: .rewardAcorn, lineWidth: 2.2)
                        .frame(width: AppSize.iconXXLarge, height: AppSize.iconXXLarge)
                    Text("아직 적립 내역이 없어요")
                        .font(.appFont(.boldHeadline))
                        .foregroundStyle(Color.textDefault)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.none) {
                        ForEach(Array(home.rewardHistory.enumerated()), id: \.element.id) { index, entry in
                            RewardHistoryRow(entry: entry)
                            if index < home.rewardHistory.count - 1 {
                                Color.borderDefault
                                    .frame(height: AppSize.hairline)
                                    .padding(.leading, Metrics.rewardSheetSeparatorInset)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RewardHistoryRow: View {
    let entry: RewardHistoryDTO

    var body: some View {
        HStack(spacing: AppSpacing.inner) {
            OpenIconView(icon: .acorn, color: .rewardAcorn, lineWidth: 2.1)
                .frame(width: AppSize.iconMedium, height: AppSize.iconMedium)
                .frame(width: Metrics.rewardSheetIconContainer, height: Metrics.rewardSheetIconContainer)
                .background(Color.rewardAcorn.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.iconContainer))

            VStack(alignment: .leading, spacing: AppSpacing.half) {
                Text(entry.eventType.displayTitle)
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textDefault)
                    .lineLimit(1)
                Text(entry.eventDay)
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }

            Spacer(minLength: AppSpacing.gap)

            Text("+\(entry.grantedPoints)")
                .font(.appFont(.heavyHeadline))
                .foregroundStyle(Color.rewardAcorn)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: Metrics.rewardSheetRowHeight)
        .contentShape(Rectangle())
    }
}

private enum Metrics {
    static let circleButton = AppSize.controlXXLarge
    static let statIcon = AppSize.iconXXLarge
    static let statIconBg: CGFloat = 42
    static let statIconRadius: CGFloat = 13
    static let progressRing: CGFloat = 220
    static let squirrelAreaHeight: CGFloat = 246
    static let squirrelCardMinHeight: CGFloat = 310
    static let squirrelCardRadius: CGFloat = 26
    static let mealButtonRadius = AppSize.controlTiny
    static let mealButtonHighlightBorder = AppSize.indicatorTiny
    static let maxChewAcornPulses = 4
    static let chewAcornLifetime: TimeInterval = 0.95
    static let acornBubbleSize: CGFloat = 30
    static let acornIconSize: CGFloat = 17
    static let rewardSheetIconContainer = AppSize.iconContainer
    static let rewardSheetRowHeight: CGFloat = 76
    static let rewardSheetSeparatorInset = AppSize.iconContainer + AppSpacing.inner
}

private extension HomeView {
    /// 야간 시간대(22:00~06:00). 다람쥐를 잠자는 일러스트로 교체하는 데 사용.
    var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: nowTick)
        return hour >= 22 || hour < 6
    }
}

private extension MealSessionPhase {
    var showsChewFeedback: Bool {
        if case .measuring = self { return true }
        return false
    }
}
