import SwiftUI

struct TrackingView: View {
    @Environment(AppState.self) private var state

    @State private var feedback: FeedbackLine?
    @State private var fbTimer: Timer?

    /// 식사 중 여부 — 식사 세션은 AppState가 관리하고 이 화면은 관찰만.
    private var isEating: Bool { state.isEating }

    var body: some View {
        VStack(spacing: 14) {
            header
            airpodsCard
            imuDebugPanel
            dailySummaryCard
                .frame(maxHeight: .infinity)
            scoreCard
            tipCard
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if let fb = feedback {
                feedbackPopup(fb)
                    .padding(.bottom, 110)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: isEating) { _, isOn in
            if isOn { startFeedbackLoop() } else { stopFeedbackLoop() }
        }
        .onDisappear { stopFeedbackLoop() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("실시간")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text("트래킹")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
        }
    }

    // MARK: Demo sensor status

    private var airpodsCard: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.sage600)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.sage100, Color.sage50],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                Circle()
                    .fill(Color.sage500)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: 4, y: -4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AirPods IMU")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text(state.imuWaveformStatusText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("모드")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink400)
                Text(state.imuWaveformSource.usesRealMotion ? "LIVE" : "MVP")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(state.imuWaveformSource.usesRealMotion ? Color.sage600 : Color.ink400)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    // MARK: IMU diagnostics (작고 조용한 디버그 라인)

    /// 실기기 + AirPods에서 IMU가 식사 세션 동안, 그리고 background 동안 데이터를
    /// 받고 있는지 한눈에 확인하기 위한 디버그 라인. 원시 IMU 데이터는 저장하지 않음.
    private var imuDebugPanel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isInForeground ? Color.sage500 : Color.blush400)
                .frame(width: 6, height: 6)
            Text(state.isInForeground ? "FG" : "BG")
                .fontWeight(.semibold)
            dotSeparator
            Text("샘플 \(state.imuSampleCount.koLocale)")
                .monospacedDigit()
            dotSeparator
            if let last = state.lastIMUSampleAt {
                // `style: .relative` 는 1초마다 SwiftUI가 자동 갱신 → 폴링 없이 BG 복귀 후
                // 마지막 수신 시각이 얼마나 오래됐는지 보임
                Text(last, style: .relative)
                    .monospacedDigit()
            } else {
                Text("샘플 없음")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.ink400)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.55), in: Capsule())
        .accessibilityLabel(imuDebugAccessibilityLabel)
    }

    private var dotSeparator: some View {
        Text("·").foregroundStyle(Color.ink400.opacity(0.6))
    }

    private var imuDebugAccessibilityLabel: String {
        let phase = state.isInForeground ? "foreground" : "background"
        if state.lastIMUSampleAt != nil {
            return "IMU 진단: \(phase), 샘플 \(state.imuSampleCount)개 수신"
        }
        return "IMU 진단: \(phase), 샘플 수신 안 됨"
    }

    // MARK: Daily summary card

    private var dailySummaryCard: some View {
        let todayScore = min(100, Int(Double(state.chewCount) / Double(Constants.dailyGoal) * 90))

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trackingDateLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ink400)
                    Text("오늘의 식사 기록")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink800)
                }

                Spacer()

                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.acorn600)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 10) {
                summaryMetric(
                    label: "식사 점수",
                    value: "\(todayScore)",
                    unit: "점",
                    color: Color.sage600
                )

                summaryMetric(
                    label: "저작 횟수",
                    value: state.chewCount.koLocale,
                    unit: "회",
                    color: Color.acorn700
                )
            }

            VStack(spacing: 10) {
                HStack {
                    Text("목표 달성률")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink600)
                    Spacer()
                    Text("\(Int(state.progress * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.sage600)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.65))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.butter400, Color.acorn300, Color.sage400],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * state.progress)
                            .animation(.easeOut(duration: 0.5), value: state.progress)
                    }
                }
                .frame(height: 15)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 250)
        .background(
            LinearGradient(
                colors: [Color.acorn50, .cream, Color.sage50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
    }

    private func summaryMetric(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ink400)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }

    private var trackingDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: Date())
    }

    // MARK: Score card

    private var scoreCard: some View {
        let todayScore = min(100, Int(Double(state.chewCount) / Double(Constants.dailyGoal) * 90))
        let weekAvg = state.weeklyScores.reduce(0, +) / max(1, state.weeklyScores.count)
        let diff = max(0, todayScore - weekAvg)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("주간 식사 점수")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ink400)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(todayScore)")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Color.ink800)
                        Text("점")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink400)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("주간 평균 +\(diff)점")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.sage600)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.sage50, in: Capsule())
            }

            weeklyBars
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private var weeklyBars: some View {
        let days = ["월","화","수","목","금","토","일"]
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(state.weeklyScores.indices, id: \.self) { i in
                let isToday = i == state.weeklyScores.count - 1
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isToday
                                ? LinearGradient(
                                    colors: [Color.acorn500, Color.butter400],
                                    startPoint: .bottom, endPoint: .top)
                                : LinearGradient(
                                    colors: [Color.acorn200, Color.acorn100],
                                    startPoint: .bottom, endPoint: .top)
                        )
                        .frame(height: CGFloat(state.weeklyScores[i]) * 0.8)
                    Text(days[i])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Color.acorn600 : Color.ink400)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 110)
    }

    // MARK: Tip card

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("💡")
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .neuoShadow(.sm)
            VStack(alignment: .leading, spacing: 2) {
                Text("오늘의 코치 팁")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink800)
                Text("저녁 식사는 한 입당 30회 씹는 걸 추천해요. 포만감이 빨리 와요!")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink600)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.sage50, Color.butter50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .neuoShadow(.sm)
    }

    // MARK: Feedback popup

    private func feedbackPopup(_ fb: FeedbackLine) -> some View {
        HStack(spacing: 10) {
            Text(fb.emoji).font(.system(size: 20))
            Text(fb.text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(bg(for: fb.kind), in: RoundedRectangle(cornerRadius: 18))
        .softShadow(.lg)
    }

    private func bg(for kind: FeedbackLine.Kind) -> Color {
        switch kind {
        case .good:  Color.sage500
        case .warn:  Color.blush400
        case .cheer: Color.butter500
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
