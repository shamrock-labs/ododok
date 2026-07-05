import SwiftUI

struct TrackingView: View {
    @Environment(AppState.self) private var state

    @State private var feedback: FeedbackLine?
    @State private var fbTimer: Timer?

    /// 식사 중 여부 — 식사 세션은 AppState가 관리하고 이 화면은 관찰만.
    private var isEating: Bool { state.isEating }

    var body: some View {
        VStack(spacing: AppSpacing.reportCell) {
            // 라이브 IMU 진단 카드(AirPods 수신 상태 + FG 샘플 카운터)는 UI에서 제외(로직 유지).
            ReportHubView()
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.homeVertical)
        .padding(.bottom, AppSpacing.seven)
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
        HStack(spacing: AppSpacing.reportCell) {
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
                Text(state.imuWaveformStatusText)
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
                Text(state.imuWaveformSource.usesRealMotion ? "LIVE" : "MVP")
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(state.imuWaveformSource.usesRealMotion ? Color.statusSuccess : Color.textSubtle)
            }
        }
        .padding(AppSpacing.reportCard)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.medium)
    }

    private var imuDebugPanel: some View {
        HStack(spacing: AppSpacing.oneHalf) {
            Circle()
                .fill(state.isInForeground ? Color.statusSuccess : Color.statusDanger)
                .frame(width: AppSize.statusDotTiny, height: AppSize.statusDotTiny)
            Text(state.isInForeground ? "FG" : "BG")
                .fontWeight(.semibold)
            dotSeparator
            Text("샘플 \(state.imuSampleCount.koLocale)")
                .monospacedDigit()
            dotSeparator
            if let last = state.lastIMUSampleAt {
                Text(last, style: .relative)
                    .monospacedDigit()
            } else {
                Text("샘플 없음")
            }
            Spacer(minLength: 0)
        }
        .font(.appFont(.semiboldCallout))
        .foregroundStyle(Color.textMuted)
        .padding(.horizontal, AppSpacing.reportCell)
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
        if state.lastIMUSampleAt != nil {
            return "센서 진단: \(phase), 샘플 \(state.imuSampleCount)개 수신"
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
