import SwiftUI

/// `.sheet(item:)`이 `Date`를 그대로 못 받아 Identifiable wrapper로 감싼다.
private struct InlineSelectedDay: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

struct TrackingView: View {
    @Environment(AppState.self) private var state

    @State private var feedback: FeedbackLine?
    @State private var fbTimer: Timer?
    @State private var inlineMonth: Date = .now
    @State private var inlineMonthSessions: [ChewingSessionDTO] = []
    @State private var inlineSelectedDay: InlineSelectedDay?
    @State private var inlineSheetPath = NavigationPath()

    /// 식사 중 여부 — 식사 세션은 AppState가 관리하고 이 화면은 관찰만.
    private var isEating: Bool { state.isEating }

    var body: some View {
        VStack(spacing: 14) {
            header
            // 라이브 IMU 진단(AirPods 상태 + 샘플 카운터)은 식사 중에만 노출.
            if isEating {
                airpodsCard
                imuDebugPanel
            }
            todaySessionsCard
            calendarSection
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
        .task { await state.fetchTodaySessions() }
        .sheet(item: $inlineSelectedDay, onDismiss: { inlineSheetPath = NavigationPath() }) { day in
            NavigationStack(path: $inlineSheetPath) {
                DaySessionsView(
                    date: day.date,
                    monthSessions: $inlineMonthSessions,
                    onDelete: { session in
                        Task {
                            await state.deleteSession(session)
                            inlineMonthSessions.removeAll { $0.id == session.id }
                        }
                    },
                    onTapSession: { session in
                        inlineSheetPath.append(session.id)
                    }
                )
                .navigationDestination(for: UUID.self) { sessionId in
                    if let session = inlineMonthSessions.first(where: { $0.id == sessionId }) {
                        SessionReportDetailView(dto: session)
                    }
                }
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
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                Text("트래킹")
                    .font(.appFont(.bold, size: 24))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
        }
    }

    // MARK: AirPods + IMU diagnostics (식사 중에만)

    private var airpodsCard: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "airpodspro")
                    .font(.appFont(.regular, size: 28))
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
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                Text(state.imuWaveformStatusText)
                    .font(.appFont(.bold, size: 15))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("모드")
                    .font(.appFont(.regular, size: 10))
                    .foregroundStyle(Color.ink400)
                Text(state.imuWaveformSource.usesRealMotion ? "LIVE" : "MVP")
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(state.imuWaveformSource.usesRealMotion ? Color.sage600 : Color.ink400)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

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
                Text(last, style: .relative)
                    .monospacedDigit()
            } else {
                Text("샘플 없음")
            }
            Spacer(minLength: 0)
        }
        .font(.appFont(.medium, size: 11))
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

    // MARK: Today sessions — 최신 1개 카드만 표시

    private var todaySessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trackingDateLabel)
                        .font(.appFont(.medium, size: 11))
                        .foregroundStyle(Color.ink400)
                    Text("오늘의 식사 기록")
                        .font(.appFont(.bold, size: 18))
                        .foregroundStyle(Color.ink800)
                }
                Spacer()
                Text("\(state.todaySessions.count)회")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.acorn700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.8), in: Capsule())
            }
            .padding(.horizontal, 4)

            latestSessionView
        }
    }

    @ViewBuilder
    private var latestSessionView: some View {
        if let latest = state.todaySessions.last {
            if let model = ReportCardModel.from(latest) {
                ReportCardView(model: model)
            } else {
                EmptyReportCardView()
            }
        } else {
            EmptyReportCardView(
                emoji: "🍽️",
                title: "오늘은 아직 식사 전이에요",
                subtitle: "홈에서 식사를 시작하면 여기에 기록돼요"
            )
        }
    }

    // MARK: Inline calendar (구 scoreCard 자리)

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("식사 캘린더")
                    .font(.appFont(.heavy, size: 14))
                    .foregroundStyle(Color.ink800)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            MealCalendarGrid(
                displayedMonth: $inlineMonth,
                monthSessions: $inlineMonthSessions,
                onTapDay: { date in
                    inlineSelectedDay = InlineSelectedDay(date: date)
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.acorn50, .cream, Color.sage50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .neuoShadow(.sm)
    }

    private var trackingDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: Date())
    }

    // MARK: Tip card

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.appFont(.medium, size: 18))
                .foregroundStyle(Color.butter600)
                .frame(width: 40, height: 40)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .neuoShadow(.sm)
            VStack(alignment: .leading, spacing: 2) {
                Text("씹기 팁")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.ink800)
                Text("저녁엔 한 입에 30번씩 씹어보세요. 포만감이 빨리 와요.")
                    .font(.appFont(.regular, size: 11))
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
            Text(fb.emoji).font(.appFont(.regular, size: 20))
            Text(fb.text)
                .font(.appFont(.bold, size: 14))
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
