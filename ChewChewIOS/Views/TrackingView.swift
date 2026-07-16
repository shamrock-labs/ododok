import SwiftUI

struct TrackingView: View {
    @Environment(AppState.self) private var state

    @State private var feedback: FeedbackLine?
    @State private var fbTimer: Timer?

    private var mealSession: MealSessionRuntimeStore { state.mealSession }

    /// 식사 중 여부 — 식사 세션은 AppState가 관리하고 이 화면은 관찰만.
    private var isEating: Bool { mealSession.isEating }

    var body: some View {
        VStack(spacing: AppSpacing.gap) {
            // 홈·친구·상점과 같은 헤더 컴포넌트 — 안내 문구는 여기로 올리고
            // 월 제목·캘린더 버튼은 아래 기록 카드가 담당한다.
            AppHeaderView(title: "기록", subtitle: "하루 평균 씹기 횟수를 확인할 수 있어요")
            // 라이브 IMU 진단 카드(AirPods 수신 상태 + FG 샘플 카운터)는 UI에서 제외(로직 유지).
            ReportHubView()
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.gap)
        .padding(.bottom, AppSpacing.four)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if let fb = feedback {
                feedbackPopup(fb)
                    .padding(.bottom, AppSpacing.overlayBottom)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: isEating) { _, isOn in
            if isOn { startFeedbackLoop() } else { stopFeedbackLoop() }
        }
        .onDisappear { stopFeedbackLoop() }
    }

    // MARK: AirPods + IMU diagnostics (식사 중에만)

    private var airpodsCard: some View {
        HStack(spacing: AppSpacing.cell) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "airpodspro")
                    .font(.appFont(.regularEmojiMedium))
                    .foregroundStyle(Color.statusSuccess)
                    .frame(width: AppSize.iconContainerXL, height: AppSize.iconContainerXL)
                    .background(Color.statusSuccessBorder, in: RoundedRectangle(cornerRadius: AppRadius.elementLarge))

                Circle()
                    .fill(Color.statusSuccess)
                    .frame(width: AppSize.statusDot, height: AppSize.statusDot)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: 4, y: -4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AirPods 센서")
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                Text(mealSession.imuWaveformStatusText)
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textDefault)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("모드")
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                Text(mealSession.imuWaveformSource.usesRealMotion ? "LIVE" : "MVP")
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(mealSession.imuWaveformSource.usesRealMotion ? Color.statusSuccess : Color.textSubtle)
            }
        }
        .padding(AppSpacing.cardContent)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.flat)
    }

    private var imuDebugPanel: some View {
        HStack(spacing: AppSpacing.oneHalf) {
            Circle()
                .fill(state.isInForeground ? Color.statusSuccess : Color.statusDanger)
                .frame(width: AppSize.statusDotTiny, height: AppSize.statusDotTiny)
            Text(state.isInForeground ? "FG" : "BG")
                .fontWeight(.semibold)
            dotSeparator
            Text("샘플 \(mealSession.imuSampleCount.koLocale)")
                .monospacedDigit()
            dotSeparator
            if let last = mealSession.lastIMUSampleAt {
                Text(last, style: .relative)
                    .monospacedDigit()
            } else {
                Text("샘플 없음")
            }
            Spacer(minLength: 0)
        }
        .font(.appFont(.semiboldCallout))
        .foregroundStyle(Color.textMuted)
        .padding(.horizontal, AppSpacing.cell)
        .padding(.vertical, AppSpacing.two)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.55), in: Capsule())
        .accessibilityLabel(imuDebugAccessibilityLabel)
    }

    private var dotSeparator: some View {
        Text("·").foregroundStyle(Color.textSubtle.opacity(0.6))
    }

    private var imuDebugAccessibilityLabel: String {
        let phase = state.isInForeground ? "foreground" : "background"
        if mealSession.lastIMUSampleAt != nil {
            return "센서 진단: \(phase), 샘플 \(mealSession.imuSampleCount)개 수신"
        }
        return "센서 진단: \(phase), 샘플 수신 안 됨"
    }

    // MARK: Feedback popup

    private func feedbackPopup(_ fb: FeedbackLine) -> some View {
        HStack(spacing: AppSpacing.inner) {
            Text(fb.emoji).font(.appFont(.regularTitle))
            Text(fb.text)
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textActionInverse)
        }
        .padding(.horizontal, AppSpacing.five)
        .padding(.vertical, AppSpacing.three)
        .background(bg(for: fb.kind), in: RoundedRectangle(cornerRadius: AppRadius.container))
        .softShadow(.lg)
    }

    private func bg(for kind: FeedbackLine.Kind) -> Color {
        switch kind {
        case .good:  Color.statusSuccess
        case .warn:  Color.statusDanger
        case .cheer: Color.statusWarning
        }
    }

    // MARK: Feedback loop (식사 중일 때만 랜덤 멘트)

    private func startFeedbackLoop() {
        fbTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { _ in
            withAnimation { feedback = FeedbackLine.all.randomElement() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation { feedback = nil }
            }
        }
    }

    private func stopFeedbackLoop() {
        fbTimer?.invalidate(); fbTimer = nil
        feedback = nil
    }
}
