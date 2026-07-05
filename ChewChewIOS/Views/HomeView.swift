import SwiftUI
import CoreMotion
import AVFoundation

struct HomeView: View {
    @Environment(AppState.self) private var state

    // MARK: - 측정 시작 햅틱 trigger
    @State private var hapticTrigger = false

    // MARK: - 끼니 알림 설정 sheet
    @State private var showMealReminderSettings = false

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
        .onChange(of: state.pendingMealStartRequest) { _, requested in
            // 끼니 리마인더 알림의 "식사 시작" 액션 — 시작 가드를 그대로 태운다.
            guard requested else { return }
            state.pendingMealStartRequest = false
            if !state.isEating { handleMealToggle() }
        }
        .onAppear {
            // 콜드스타트로 열려 onChange를 놓친 경우 보완.
            if state.pendingMealStartRequest {
                state.pendingMealStartRequest = false
                if !state.isEating { handleMealToggle() }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .sheet(isPresented: $showMealReminderSettings) {
            MealReminderSettingsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - 식사 시작 가드

    private func handleMealToggle() {
        if state.isEating {
            // 60초 미만이면 분석 불가 — 사용자에게 "더 측정할까요?" 확인 후 처리.
            let duration = Date().timeIntervalSince(state.eatingStartedAt ?? Date())
            if duration < 60 {
                state.showShortSessionConfirm = true
                return
            }
            state.toggleEating()
            return
        }

        // 시뮬레이터에선 가드 없이 바로 시작 (데모 흐름 유지)
        #if !targetEnvironment(simulator)
        let service = CMHeadphoneMotionManager()
        let status = CMHeadphoneMotionManager.authorizationStatus()
        let available = service.isDeviceMotionAvailable

        // 모션 권한·기기 호환·실제 오디오 라우트(에어팟/헤드폰 등) 셋 다 확인.
        // isDeviceMotionAvailable이 기기 호환만 보고 연결을 확신하지 못하는 케이스를
        // 라우트 체크로 보완 — 시작 자체를 막아 silent 빈 세션을 차단한다.
        if status == .denied || status == .restricted || !available || !hasHeadphoneAudioRoute {
            state.showAirPodsConnectionPrompt = true
            return
        }

        // REQ-01: notDetermined이면 즉시 시작하지 않고 권한 요청 → 결과에 따라 분기.
        if !AppState.shouldStartImmediately(status: status, available: available) {
            state.requestMotionPermission {
                // 권한 허용됨 — 햅틱 + 측정 시작
                hapticTrigger.toggle()
                state.startEating()
            } onDenied: {
                state.showAirPodsConnectionPrompt = true
            }
            return
        }
        #endif

        // 차단 안 됐을 때만 햅틱 + 시작
        hapticTrigger.toggle()
        state.toggleEating()
    }

    /// 현재 오디오 출력 라우트에 AirPods/Bluetooth/유선 헤드폰이 포함되어 있는지.
    /// CMHeadphoneMotionManager.isDeviceMotionAvailable이 미연결 상태에서도 true를
    /// 반환하는 케이스를 보완한다.
    private var hasHeadphoneAudioRoute: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones, .headsetMic:
                return true
            default:
                return false
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        AppHeaderView(eyebrow: todayLabel, title: "오도독", subtitle: homeHeaderSubtitle) {
            HStack(spacing: 7) {
                HeaderMetricPill(icon: .flame, value: "\(state.currentStreak)", tint: .statusWarning)
                HeaderMetricPill(icon: .acorn, value: state.points.koLocale, tint: .rewardAcorn)
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
        if state.isEating {
            return state.imuWaveformSource.usesRealMotion ? "식사 중 · AirPods LIVE" : "식사 중 · MVP 모드"
        }
        // 오늘 저작 횟수는 화면 중앙 표시와 중복이라 헤더 서브타이틀에서 제외.
        return nil
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "오늘 · M월 d일"
        return f.string(from: Date())
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
                label: state.freezeInventory > 0 ? "연속 출석 · 🛡️\(state.freezeInventory)" : "연속 출석",
                value: "\(state.currentStreak)일째",
                iconBG: Color.statusDangerMuted
            ) {
                OpenIconView(icon: .flame, color: .statusDanger, lineWidth: 2.2)
                    .frame(width: Metrics.statIcon, height: Metrics.statIcon)
            }

            statCard(
                label: "보유 도토리",
                value: state.points.koLocale,
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
        .appElevation(.medium)
    }

    // MARK: Squirrel card + IMU waveform

    private var squirrelCard: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            ZStack {
                if !state.isEating {
                    Circle()
                        .stroke(Color.borderDefault, lineWidth: 5)
                        .frame(width: Metrics.progressRing, height: Metrics.progressRing)
                    Circle()
                        .trim(from: 0, to: state.todayProgress)
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
                    isEating: state.isEating,
                    isNight: isNightTime
                )
                .scaleEffect(1.5)
            }
            .frame(height: Metrics.squirrelAreaHeight)

            VStack(spacing: 4) {
                Text(state.isEating ? "맛있게 먹는 중이에요" : state.status.title)
                    .font(.appFont(.boldTitleCompact))
                    .foregroundStyle(Color.textDefault)
                if !state.isEating {
                    Text("오늘 \(state.todayRealChewCount.koLocale) / \(Constants.dailyGoal.koLocale)회")
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            }

            imuWaveformCard
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.four)
        .padding(.vertical, AppSpacing.four)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Metrics.squirrelCardMinHeight)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: Metrics.squirrelCardRadius))
        .appElevation(.low)
    }

    private var imuWaveformCard: some View {
        IMUWaveformView(samples: state.imuWaveformSamples, isLive: state.isIMUWaveformLive)
            .frame(height: Metrics.imuWaveformHeight)
            .padding(AppSpacing.gap)
            .background(Color.controlOnSurface, in: RoundedRectangle(cornerRadius: AppRadius.elementLarge))
    }

    // MARK: Meal toggle button

    private var mealToggleButton: some View {
        Button {
            handleMealToggle()
        } label: {
            HStack(spacing: AppSpacing.gap) {
                Image(systemName: state.isEating ? "stop.fill" : "fork.knife")
                    .font(.appFont(.boldTitleLarge))
                Text(state.isEating ? "식사 종료" : "식사 시작")
                    .font(.appFont(.boldTitle))
            }
            .foregroundStyle(Color.controlOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.actionV)
            .background(
                LinearGradient(
                    colors: state.isEating
                        ? Color.mealStopGradient
                        : Color.mealStartGradient,
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Metrics.mealButtonRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.mealButtonRadius)
                    .strokeBorder(Color.controlOnAccent.opacity(state.startButtonHighlighted ? 0.9 : 0), lineWidth: Metrics.mealButtonHighlightBorder)
            )
        }
        .accessibilityIdentifier("MealToggle")
        .accessibilityLabel(state.isEating ? "식사 종료" : "식사 시작")
        .buttonStyle(PressableButtonStyle())
        .scaleEffect(state.startButtonHighlighted ? 1.04 : 1.0)
        .shadow(color: Color.highlightShadow.opacity(state.startButtonHighlighted ? 0.55 : 0), radius: 14, x: 0, y: 4)
        .animation(.easeInOut(duration: AppMotion.durationStateChange), value: state.isEating)
        .animation(.spring(response: AppMotion.springPlayfulResponse, dampingFraction: AppMotion.springPlayfulDamping), value: state.startButtonHighlighted)
    }
}

private enum Metrics {
    static let circleButton = AppSize.controlXXLarge
    static let statIcon = AppSize.iconXXLarge
    static let statIconBg: CGFloat = 42
    static let statIconRadius: CGFloat = 13
    static let progressRing: CGFloat = 220
    static let squirrelAreaHeight: CGFloat = 246
    static let squirrelCardMinHeight: CGFloat = 390
    static let squirrelCardRadius: CGFloat = 26
    static let imuWaveformHeight = AppSize.visualMedium
    static let mealButtonRadius = AppSize.controlTiny
    static let mealButtonHighlightBorder = AppSize.indicatorTiny
}

private extension HomeView {
    /// 야간 시간대(22:00~06:00). 다람쥐를 잠자는 일러스트로 교체하는 데 사용.
    var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: nowTick)
        return hour >= 22 || hour < 6
    }
}
