import SwiftUI

struct TrackingView: View {
    @Environment(AppState.self) private var state

    @State private var feedback: FeedbackLine?
    @State private var fbTimer: Timer?

    /// 식사 중 여부 — 식사 세션은 AppState가 관리하고 이 화면은 관찰/조작만.
    private var isEating: Bool { state.isEating }

    var body: some View {
        VStack(spacing: 16) {
            header
            airpodsCard
            liveCard
            scoreCard
            tipCard
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
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

    // MARK: AirPods status

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
                Text("AirPods Pro 2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text("연결됨 · IMU 활성")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink800)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("배터리")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink400)
                Text("87%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.sage600)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    // MARK: Live tracking card

    private var liveCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("분당 저작 횟수")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ink400)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(isEating ? state.chewRatePerMinute : 0)")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(Color.ink800)
                        Text("회/분")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink400)
                    }
                }
                Spacer()
                Button {
                    state.toggleEating()
                } label: {
                    Image(systemName: isEating ? "stop.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            LinearGradient(
                                colors: isEating
                                    ? [Color.blush400, Color.blush500]
                                    : [Color.sage400, Color.sage500],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .softShadow(.pill)
            }

            waveform

            HStack(spacing: 8) {
                statPill("한 입당", "28회", Color.ink800)
                statPill("속도", "적정", Color.sage600)
                statPill("리듬", "안정", Color.butter600)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.acorn50, .cream, Color.sage50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<28, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.acorn400, Color.butter400],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    .frame(width: 5, height: barHeight(i))
                    .opacity(isEating ? 1 : 0.3)
                    .animation(
                        isEating
                            ? .easeInOut(duration: 0.9).repeatForever().delay(Double(i) * 0.04)
                            : .default,
                        value: isEating
                    )
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard isEating else { return 6 }
        return CGFloat(20 + sin(Double(i) * 0.6) * 12 + 8)
    }

    private func statPill(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.ink400)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Score card

    private var scoreCard: some View {
        let todayScore = min(100, Int(Double(state.chewCount) / Double(Constants.dailyGoal) * 90))
        let weekAvg = state.weeklyScores.reduce(0, +) / max(1, state.weeklyScores.count)
        let diff = max(0, todayScore - weekAvg)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘의 식사 점수")
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
