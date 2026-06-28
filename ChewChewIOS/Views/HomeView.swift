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
        VStack(spacing: 14) {
            topBar
            squirrelCard
                .frame(maxHeight: .infinity)
            mealToggleButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
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
                HeaderMetricPill(icon: .flame, value: "\(state.currentStreak)", tint: .butter600)
                HeaderMetricPill(icon: .acorn, value: state.points.koLocale, tint: .acorn700)
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

    private var homeHeaderSubtitle: String {
        if state.isEating {
            return state.imuWaveformSource.usesRealMotion ? "식사 중 · AirPods LIVE" : "식사 중 · MVP 모드"
        }
        return "오늘 \(state.todayRealChewCount.koLocale) / \(Constants.dailyGoal.koLocale)회"
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
                .font(.appFont(.medium, size: 18))
                .foregroundStyle(Color.ink600)
                .frame(width: 46, height: 46)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .neuoShadow(.sm)
    }

    // MARK: Streak + Points

    private var statRow: some View {
        HStack(spacing: 14) {
            statCard(
                label: state.freezeInventory > 0 ? "연속 출석 · 🛡️\(state.freezeInventory)" : "연속 출석",
                value: "\(state.currentStreak)일째",
                iconBG: Color.blush100
            ) {
                OpenIconView(icon: .flame, color: .blush500, lineWidth: 2.2)
                    .frame(width: 24, height: 24)
            }

            statCard(
                label: "보유 도토리",
                value: state.points.koLocale,
                iconBG: Color.butter100
            ) {
                OpenIconView(icon: .acorn, color: .acorn700, lineWidth: 2.1)
                    .frame(width: 24, height: 24)
            }
        }
    }

    private func statCard<I: View>(
        label: String,
        value: String,
        iconBG: Color,
        @ViewBuilder icon: () -> I
    ) -> some View {
        HStack(spacing: 10) {
            iconBG
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay { icon() }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.ink600)
                    .lineLimit(1)
                Text(value)
                    .font(.appFont(.bold, size: 17))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    // MARK: Squirrel card + IMU waveform

    private var squirrelCard: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            ZStack {
                if !state.isEating {
                    Circle()
                        .stroke(Color.ink100, lineWidth: 5)
                        .frame(width: 220, height: 220)
                    Circle()
                        .trim(from: 0, to: state.todayProgress)
                        .stroke(
                            Color.acorn500,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
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
            .frame(height: 246)

            VStack(spacing: 4) {
                Text(state.isEating ? "맛있게 먹는 중이에요" : state.status.title)
                    .font(.appFont(.bold, size: 19))
                    .foregroundStyle(Color.ink800)
                if !state.isEating {
                    Text("오늘 \(state.todayRealChewCount.koLocale) / \(Constants.dailyGoal.koLocale)회")
                        .font(.appFont(.semibold, size: 13))
                        .foregroundStyle(Color.ink600)
                        .monospacedDigit()
                }
            }

            imuWaveformCard
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 390)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26))
        .softShadow(.base)
    }

    private var imuWaveformCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IMU 파형")
                        .font(.appFont(.bold, size: 13))
                        .foregroundStyle(Color.ink800)
                    Text(state.imuWaveformStatusText)
                        .font(.appFont(.semibold, size: 13))
                        .foregroundStyle(state.isIMUWaveformLive ? Color.sage600 : Color.ink400)
                }

                Spacer()

                Image(systemName: "waveform.path.ecg")
                    .font(.appFont(.bold, size: 15))
                    .foregroundStyle(state.isIMUWaveformLive ? Color.sage600 : Color.ink400)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            }

            IMUWaveformView(samples: state.imuWaveformSamples, isLive: state.isIMUWaveformLive)
                .frame(height: 44)
        }
        .padding(12)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Meal toggle button

    private var mealToggleButton: some View {
        Button {
            handleMealToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: state.isEating ? "stop.fill" : "fork.knife")
                    .font(.appFont(.bold, size: 22))
                Text(state.isEating ? "식사 종료" : "식사 시작")
                    .font(.appFont(.bold, size: 20))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: state.isEating
                        ? [Color.blush400, Color.blush500]
                        : [Color.acorn400, Color.acorn600],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(state.startButtonHighlighted ? 0.9 : 0), lineWidth: 3)
            )
        }
        .accessibilityIdentifier("MealToggle")
        .accessibilityLabel(state.isEating ? "식사 종료" : "식사 시작")
        .buttonStyle(PressableButtonStyle())
        .softShadow(.pill)
        .scaleEffect(state.startButtonHighlighted ? 1.04 : 1.0)
        .shadow(color: Color.acorn400.opacity(state.startButtonHighlighted ? 0.55 : 0), radius: 14, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.22), value: state.isEating)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: state.startButtonHighlighted)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension HomeView {
    /// 야간 시간대(22:00~06:00). 다람쥐를 잠자는 일러스트로 교체하는 데 사용.
    var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: nowTick)
        return hour >= 22 || hour < 6
    }
}
