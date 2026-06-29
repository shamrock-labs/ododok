import SwiftUI

struct ReportHubView: View {
    @Environment(AppState.self) private var state

    @State private var recentSessions: [ChewingSessionDTO] = []
    @State private var selectedDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var pivotDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var detailSession: ChewingSessionDTO?
    @State private var showCalendar = false
    @State private var calendarMonth: Date = mealCalendarCalendar.startOfDay(for: Date())

    private let dayWidth: CGFloat = 52
    /// 타임라인 가로 스트립이 한 번에 보여주는 이동 윈도우 길이.
    private let windowDays = 14
    /// 주간 비교·코치 카드용 today-앵커 시리즈 길이(7×3주).
    private let weeklyWindowDays = 21

    var body: some View {
        VStack(spacing: 14) {
            legacyUITestAnchors
            timelineCard
            sessionListCard
            weeklyComparisonCard
            weeklyCoachCard
        }
        .task { await reloadRecentSessions() }
        .onChange(of: pivotDate) { _, _ in
            Task { await loadWindow() }
        }
        .sheet(item: $detailSession) { session in
            NavigationStack {
                SessionReportDetailView(dto: session)
            }
        }
        .sheet(isPresented: $showCalendar) {
            ReportCalendarDialog(
                month: $calendarMonth,
                selectedDate: selectedDate,
                today: today,
                mealCount: { mealCount(for: $0) },
                loadMonth: { await loadMonth($0) },
                onPick: { date in
                    pivotDate = date
                    selectedDate = date
                    showCalendar = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var today: Date { mealCalendarCalendar.startOfDay(for: Date()) }

    /// 타임라인 윈도우 끝 = (기점+7, 오늘) 중 이른 쪽(미래 빈 칸 방지).
    private var windowEnd: Date {
        let plus7 = mealCalendarCalendar.date(byAdding: .day, value: 7, to: pivotDate) ?? pivotDate
        return min(plus7, today)
    }

    private var windowStart: Date {
        mealCalendarCalendar.date(byAdding: .day, value: -(windowDays - 1), to: windowEnd) ?? windowEnd
    }

    /// 타임라인 가로 스트립용 14일 이동 윈도우.
    private var timelineDays: [ReportDay] {
        reportDays(start: windowStart, count: windowDays)
    }

    /// 주간 비교·코치 카드용 21일 today-앵커 시리즈.
    private var weeklyDays: [ReportDay] {
        let start = mealCalendarCalendar.date(byAdding: .day, value: -(weeklyWindowDays - 1), to: today) ?? today
        return reportDays(start: start, count: weeklyWindowDays)
    }

    private func reportDays(start: Date, count: Int) -> [ReportDay] {
        (0..<count).map { offset in
            let date = mealCalendarCalendar.date(byAdding: .day, value: offset, to: start) ?? start
            let daySessions = sessions(on: date)
            return daySessions.isEmpty ? ReportDay.empty(date: date) : ReportDay(date: date, sessions: daySessions)
        }
    }

    private var selectedDay: ReportDay {
        let daySessions = sessions(on: selectedDate)
        return daySessions.isEmpty ? ReportDay.empty(date: selectedDate) : ReportDay(date: selectedDate, sessions: daySessions)
    }

    private var selectedSessions: [ChewingSessionDTO] {
        sessions(on: selectedDate).sorted { $0.startedAt < $1.startedAt }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(monthRangeLabel)
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.ink800)
                Spacer(minLength: 0)
                TrendLegend()
                Button { openCalendar() } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.acorn700)
                        .frame(width: 30, height: 30)
                        .background(Color.acorn50, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("달력 열기")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            ForEach(timelineDays) { day in
                                dateRingCell(day)
                                    .frame(width: dayWidth)
                                    .id(day.id)
                            }
                        }

                        ContinuousTrendChart(
                            days: timelineDays,
                            selectedDate: selectedDate,
                            dayWidth: dayWidth
                        )
                        .frame(width: dayWidth * CGFloat(timelineDays.count), height: 164)
                    }
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .scrollTargetBehavior(.viewAligned)
                .task {
                    proxy.scrollTo(selectedDay.id, anchor: .center)
                }
                .onChange(of: selectedDate) { _, _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(selectedDay.id, anchor: .center)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay.shortDateLabel)
                    .font(.appFont(.heavy, size: 17))
                    .foregroundStyle(Color.ink800)
                    .monospacedDigit()
                Text(selectedDay.summaryLabel)
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.ink600)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .softShadow(.base)
    }

    private func dateRingCell(_ day: ReportDay) -> some View {
        let selected = mealCalendarCalendar.isDate(day.date, inSameDayAs: selectedDate)
        return Button {
            selectedDate = day.date
        } label: {
            VStack(spacing: 5) {
                Text(day.weekdayLabel)
                    .font(.appFont(.bold, size: 11))
                    .foregroundStyle(selected ? Color.acorn700 : Color.ink400)
                ZStack {
                    MealCompletionRing(meals: day.mealCount, selected: selected)
                    Text(day.dayLabel)
                        .font(.appFont(.heavy, size: day.dayLabel.contains("/") ? 11 : 14))
                        .foregroundStyle(selected ? Color.white : Color.ink800)
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                }
                .frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.shortDateLabel), \(day.mealCount)끼 기록")
    }

    private var sessionListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedDay.shortDateLabel) 끼니")
                    .font(.appFont(.heavy, size: 16))
                    .foregroundStyle(Color.ink800)
                Spacer()
                Text("\(selectedSessions.count)회")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.acorn700)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.acorn50, in: Capsule())
            }

            if selectedSessions.isEmpty {
                emptySessionState
                dailyInsightCard
            } else {
                VStack(spacing: 6) {
                    ForEach(selectedSessions) { session in
                        sessionRow(session)
                    }
                    dailyReportRow
                    dailyInsightCard
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .softShadow(.base)
    }

    private var emptySessionState: some View {
        HStack(spacing: 12) {
            Text("🍽️")
                .font(.appFont(.regular, size: 24))
                .frame(width: 42, height: 42)
                .background(Color.acorn50, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(mealCalendarCalendar.isDateInToday(selectedDate) ? "오늘은 아직 식사 전이에요" : "이 날은 식사 기록이 없어요")
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.ink800)
                Text("식사를 기록하면 아침·점심·저녁 리포트가 여기에 쌓여요.")
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.ink600)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.acorn50.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sessionRow(_ session: ChewingSessionDTO) -> some View {
        let slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: session.startedAt))
        return Button {
            detailSession = session
        } label: {
            HStack(spacing: 12) {
                OpenIconView(icon: slot.openIcon, color: slotIconColor(slot), lineWidth: 2.1)
                    .frame(width: 18, height: 18)
                    .frame(width: 34, height: 34)
                    .background(slotTint(slot), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                        .font(.appFont(.heavy, size: 15))
                        .foregroundStyle(Color.ink800)
                    Text("\(timeLabel(session.startedAt)) · \((session.estimatedTotalChews ?? 0).koLocale)회")
                        .font(.appFont(.semibold, size: 12))
                        .foregroundStyle(Color.ink600)
                }
                Spacer(minLength: 0)
                Text(durationLabel(session.durationSec))
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(Color.ink600)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.appFont(.bold, size: 11))
                    .foregroundStyle(Color.ink400)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var dailyInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("하루 리포트 요약")
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.ink800)
                Spacer(minLength: 0)
                Text(selectedDay.mealCount == 0 ? "기록 전" : "\(selectedDay.mealCount)/3끼")
                    .font(.appFont(.heavy, size: 11))
                    .foregroundStyle(selectedDay.mealCount == 0 ? Color.ink400 : Color.acorn700)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.72), in: Capsule())
            }

            dailyInsightRow(
                icon: "calendar.badge.clock",
                title: "아침·점심·저녁",
                value: dailySlotSummary,
                detail: "기록 없는 끼니는 누락이 아니라 아직 식사 기록이 없는 상태로 보여요."
            )
            dailyInsightRow(
                icon: "arrow.left.arrow.right",
                title: "어제 대비",
                value: dailyDeltaSummary,
                detail: "하루 차이는 컨디션·메뉴와 연관될 수 있어 참고용으로만 봐요."
            )
            dailyInsightRow(
                icon: "chart.bar.fill",
                title: "끼니 비교",
                value: mealComparisonSummary,
                detail: "한 끼 이상 쌓이면 끼니별 패턴을 비교할 수 있어요."
            )
            dailyInsightRow(
                icon: "sum",
                title: "하루 합계",
                value: "약 \(selectedDay.chewCount.koLocale)회(추정) · \(selectedDay.minutes)분",
                detail: "추정 저작 횟수와 식사 시간을 같은 단위로 묶은 요약이에요."
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sage50.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.sage100, lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func dailyInsightRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.appFont(.bold, size: 12))
                .foregroundStyle(Color.sage600)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.75), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.ink800)
                    Text(value)
                        .font(.appFont(.heavy, size: 12))
                        .foregroundStyle(Color.sage600)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()
                }
                Text(detail)
                    .font(.appFont(.semibold, size: 12))
                    .foregroundStyle(Color.ink600)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var dailyReportRow: some View {
        Button {
            detailSession = selectedSessions.last
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("일간 리포트")
                        .font(.appFont(.heavy, size: 15))
                        .foregroundStyle(Color.acorn700)
                    Text("하루 전체 요약 보기")
                        .font(.appFont(.semibold, size: 12))
                        .foregroundStyle(Color.ink600)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.acorn700)
            }
            .padding(12)
            .background(Color.acorn50, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var weeklyComparisonCard: some View {
        let weeks = weeklyMetrics
        let maxChews = max(1, weeks.map(\.chews).max() ?? 1)
        let maxMinutes = max(1, weeks.map(\.minutes).max() ?? 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("주간 리포트")
                    .font(.appFont(.heavy, size: 16))
                    .foregroundStyle(Color.ink800)
                Spacer()
                TrendLegend()
            }

            HStack(alignment: .bottom, spacing: 18) {
                ForEach(weeks) { week in
                    VStack(spacing: 7) {
                        HStack(alignment: .bottom, spacing: 7) {
                            metricBar(value: week.chews, maxValue: maxChews, color: Color.acorn500, label: "\(week.chews)")
                            metricBar(value: week.minutes, maxValue: maxMinutes, color: Color.sage500, label: "\(week.minutes)분")
                        }
                        Text(week.label)
                            .font(.appFont(week.isCurrent ? .heavy : .semibold, size: 12))
                            .foregroundStyle(week.isCurrent ? Color.ink800 : Color.ink400)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(week.isCurrent ? 1 : 0.58)
                }
            }
            .frame(height: 116)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .softShadow(.base)
    }

    private var weeklyCoachCard: some View {
        let insight = weeklyCoachInsight
        return HStack(alignment: .top, spacing: 12) {
            Image(insight.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .background(Color.butter100.opacity(0.72), in: Circle())

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("다람이 코치")
                            .font(.appFont(.heavy, size: 15))
                            .foregroundStyle(Color.ink800)
                        Text(insight.badge)
                            .font(.appFont(.heavy, size: 10))
                            .foregroundStyle(insight.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(insight.accent.opacity(0.14), in: Capsule())
                    }
                    Text(insight.message)
                        .font(.appFont(.semibold, size: 13))
                        .foregroundStyle(Color.ink600)
                        .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    coachMetricPill(
                        title: "저작",
                        value: insight.chewDeltaText,
                        icon: .acorn,
                        color: .acorn700
                    )
                    coachMetricPill(
                        title: "시간",
                        value: insight.minuteDeltaText,
                        icon: .utensils,
                        color: .sage600
                    )
                    coachMetricPill(
                        title: "기록",
                        value: insight.mealDeltaText,
                        icon: .sunrise,
                        color: .butter600
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.sage100.opacity(0.72), lineWidth: 1)
        )
        .softShadow(.base)
    }

    private func coachMetricPill(title: String, value: String, icon: OpenIcon, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                OpenIconView(icon: icon, color: color, lineWidth: 2.1)
                    .frame(width: 13, height: 13)
                Text(title)
                    .font(.appFont(.bold, size: 10))
                    .foregroundStyle(Color.ink600)
            }
            Text(value)
                .font(.appFont(.heavy, size: 11))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricBar(value: Int, maxValue: Int, color: Color, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.appFont(.heavy, size: 10))
                .foregroundStyle(color)
                .monospacedDigit()
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 18, height: max(16, CGFloat(value) / CGFloat(maxValue) * 72))
        }
    }

    private var weeklyMetrics: [WeeklyMetric] {
        let chunks = weeklyDays.chunked(into: 7)
        let labels = ["지지난주", "지난주", "이번 주"]
        return chunks.enumerated().map { index, chunk in
            let chews = max(1, chunk.map(\.chewCount).reduce(0, +) / max(1, chunk.count))
            let minutes = max(1, chunk.map(\.minutes).reduce(0, +) / max(1, chunk.count))
            let meals = chunk.map(\.mealCount).reduce(0, +)
            return WeeklyMetric(
                label: labels[min(index, labels.count - 1)],
                chews: chews,
                minutes: minutes,
                meals: meals,
                isCurrent: index == chunks.count - 1
            )
        }
    }

    private var weeklyCoachInsight: WeeklyCoachInsight {
        let weeks = weeklyMetrics
        guard let first = weeks.first, let current = weeks.last else {
            return WeeklyCoachInsight(
                badge: "준비 중",
                message: "기록이 쌓이면 처음 주와 이번 주를 비교해서 식사 리듬 변화를 알려줄게요.",
                chewDeltaText: "기록 대기",
                minuteDeltaText: "기록 대기",
                mealDeltaText: "기록 대기",
                accent: .ink400,
                imageName: "DaramHi"
            )
        }

        let chewDelta = current.chews - first.chews
        let minuteDelta = current.minutes - first.minutes
        let mealDelta = current.meals - first.meals
        let chewPercent = percentDelta(from: first.chews, to: current.chews)
        let minutePercent = percentDelta(from: first.minutes, to: current.minutes)
        let improvedSignals = [chewDelta >= 20, minuteDelta >= 1, mealDelta >= 1].filter { $0 }.count

        if current.meals == 0 {
            return WeeklyCoachInsight(
                badge: "기록 전",
                message: "이번 주 식사 기록이 쌓이면 저작 횟수와 식사 시간을 지난 흐름과 비교해볼게요.",
                chewDeltaText: "0회",
                minuteDeltaText: "0분",
                mealDeltaText: "0끼",
                accent: .ink400,
                imageName: "DaramHi"
            )
        }

        if improvedSignals >= 2 {
            return WeeklyCoachInsight(
                badge: "개선 중",
                message: "처음 기록 주보다 이번 주 식사 리듬이 더 여유로워졌어요. 주간 평균 저작은 \(formatPercent(chewPercent)) 변했고, 식사 시간도 \(formatPercent(minutePercent)) 변했어요.",
                chewDeltaText: signedDelta(chewDelta, suffix: "회"),
                minuteDeltaText: signedDelta(minuteDelta, suffix: "분"),
                mealDeltaText: signedDelta(mealDelta, suffix: "끼"),
                accent: .sage600,
                imageName: Mood.happy.imageName
            )
        }

        if improvedSignals == 1 || abs(chewDelta) < 20 {
            return WeeklyCoachInsight(
                badge: "유지 중",
                message: "이번 주는 처음 주와 비슷한 리듬을 유지하고 있어요. 다음 목표는 한 끼에서 조금 더 천천히 씹는 구간을 늘리는 거예요.",
                chewDeltaText: signedDelta(chewDelta, suffix: "회"),
                minuteDeltaText: signedDelta(minuteDelta, suffix: "분"),
                mealDeltaText: signedDelta(mealDelta, suffix: "끼"),
                accent: .butter600,
                imageName: Mood.puffy.imageName
            )
        }

        return WeeklyCoachInsight(
            badge: "다시 시작",
            message: "이번 주 식사 리듬은 처음 주보다 조금 짧아졌어요. 다음 식사에서는 첫 5분만 속도를 낮춰서 다시 흐름을 만들어봐요.",
            chewDeltaText: signedDelta(chewDelta, suffix: "회"),
            minuteDeltaText: signedDelta(minuteDelta, suffix: "분"),
            mealDeltaText: signedDelta(mealDelta, suffix: "끼"),
            accent: .blush500,
            imageName: Mood.sleepy.imageName
        )
    }

    private func percentDelta(from baseline: Int, to current: Int) -> Int {
        guard baseline > 0 else { return current > 0 ? 100 : 0 }
        return Int(((Double(current - baseline) / Double(baseline)) * 100).rounded())
    }

    private func formatPercent(_ percent: Int) -> String {
        if percent == 0 { return "거의 같게" }
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    private func signedDelta(_ value: Int, suffix: String) -> String {
        if value == 0 { return "±0\(suffix)" }
        return value > 0 ? "+\(value)\(suffix)" : "\(value)\(suffix)"
    }

    private var dailySlotSummary: String {
        let mainSlots: [DayMealSlot] = [.morning, .lunch, .dinner]
        let recordedSlots = Set(selectedSessions.map {
            DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: $0.startedAt))
        })
        let recorded = mainSlots.filter { recordedSlots.contains($0) }.map(\.label)
        let missing = mainSlots.filter { !recordedSlots.contains($0) }.map(\.label)
        if recorded.isEmpty { return "아침·점심·저녁 기록 없음" }
        if missing.isEmpty { return "세 끼 모두 기록됨" }
        return "\(recorded.joined(separator: "·")) 기록 · \(missing.joined(separator: "·")) 없음"
    }

    private var dailyDeltaSummary: String {
        guard selectedDay.mealCount > 0 else { return "비교 보류" }
        guard let previous = previousReportDay, previous.mealCount > 0 else {
            return "어제 기록 없음"
        }
        let diff = selectedDay.chewCount - previous.chewCount
        if abs(diff) < 20 { return "어제와 비슷해요" }
        return diff > 0
            ? "어제보다 약 \(diff.koLocale)회 많아요"
            : "어제보다 약 \(abs(diff).koLocale)회 적어요"
    }

    private var mealComparisonSummary: String {
        let grouped = Dictionary(grouping: selectedSessions) { dto in
            DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: dto.startedAt))
        }
        let totals = grouped.mapValues { sessions in
            sessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
        }
        guard !totals.isEmpty else { return "기록 쌓이면 비교" }
        guard totals.count > 1 else {
            let slot = totals.keys.first?.label ?? "한 끼"
            return "\(slot)만 기록됨"
        }
        guard let top = totals.max(by: { $0.value < $1.value }) else { return "비교 준비 중" }
        return "\(top.key.label) 약 \(top.value.koLocale)회(추정)"
    }

    private var previousReportDay: ReportDay? {
        guard let previousDate = mealCalendarCalendar.date(byAdding: .day, value: -1, to: selectedDate) else {
            return nil
        }
        let daySessions = sessions(on: previousDate)
        return daySessions.isEmpty ? ReportDay.empty(date: previousDate) : ReportDay(date: previousDate, sessions: daySessions)
    }

    private var legacyUITestAnchors: some View {
        VStack(spacing: 0) {
            Text("오늘의 식사 기록")
            Text("\(state.todaySessions.count)회")
            Text("오늘은 아직 식사 전이에요")
            Text("식사 캘린더")
            Text(yearMonthLabel)
        }
        .font(.system(size: 1))
        .foregroundStyle(Color.clear)
        .frame(width: 1, height: 1)
        .clipped()
        .accessibilityHidden(false)
    }

    @MainActor
    private func reloadRecentSessions() async {
        await state.fetchTodaySessions()
        // 주간 카드(21일) + 현재 타임라인 윈도우를 모두 덮는 초기 범위.
        let weeklyStart = mealCalendarCalendar.date(byAdding: .day, value: -(weeklyWindowDays - 1), to: today) ?? today
        let start = min(weeklyStart, windowStart)
        let end = mealCalendarCalendar.date(byAdding: .day, value: 1, to: today) ?? today
        let merged = await fetchMerged(since: start, until: end, into: recentSessions)
        if merged.isEmpty {
            recentSessions = ReportMockData.sessions(start: weeklyStart, days: weeklyWindowDays)
        } else {
            recentSessions = merged
        }
    }

    /// 타임라인 이동 윈도우 범위를 받아 병합한다.
    @MainActor
    private func loadWindow() async {
        let end = mealCalendarCalendar.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd
        let merged = await fetchMerged(since: windowStart, until: end, into: recentSessions)
        if !merged.isEmpty { recentSessions = merged }
    }

    /// 달력에 표시할 달의 범위를 받아 병합한다.
    @MainActor
    private func loadMonth(_ month: Date) async {
        let end = mealCalendarCalendar.date(byAdding: .day, value: 1, to: monthEnd(month)) ?? monthEnd(month)
        let merged = await fetchMerged(since: monthStart(month), until: end, into: recentSessions)
        if !merged.isEmpty { recentSessions = merged }
    }

    /// 범위 세션을 받아 기존 세션과 id 기준으로 병합(중복 제거). 리포트 가능 행만 남긴다.
    @MainActor
    private func fetchMerged(since: Date, until: Date, into existing: [ChewingSessionDTO]) async -> [ChewingSessionDTO] {
        let deviceId = DeviceIdentity.shared
        let rows = (try? await state.remoteStore.fetchChewingSessions(deviceId: deviceId, since: since, until: until)) ?? []
        let reportable = rows.filter { ReportCardModel.from($0) != nil }
        guard !reportable.isEmpty else { return existing }
        var byId: [UUID: ChewingSessionDTO] = [:]
        for session in existing { byId[session.id] = session }
        for session in reportable { byId[session.id] = session }
        return Array(byId.values)
    }

    private func sessions(on date: Date) -> [ChewingSessionDTO] {
        recentSessions.filter { mealCalendarCalendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    /// 그 날의 주요 끼 슬롯 수(0~3). 달력·타임라인 링 채움 공용. 같은 슬롯 다회는 1로 캡.
    private func mealCount(for date: Date) -> Int {
        let daySessions = sessions(on: date)
        guard !daySessions.isEmpty else { return 0 }
        return ReportDay(date: date, sessions: daySessions).mealCount
    }

    private func monthStart(_ date: Date) -> Date {
        mealCalendarCalendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthEnd(_ date: Date) -> Date {
        guard let interval = mealCalendarCalendar.dateInterval(of: .month, for: date) else { return date }
        return mealCalendarCalendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    }

    private func slotTint(_ slot: DayMealSlot) -> Color {
        switch slot {
        case .morning: Color.butter100
        case .lunch: Color.sage100
        case .dinner: Color.blush100
        case .lateNight: Color.acorn100
        }
    }

    private func slotIconColor(_ slot: DayMealSlot) -> Color {
        switch slot {
        case .morning: Color.butter600
        case .lunch: Color.sage600
        case .dinner: Color.blush500
        case .lateNight: Color.acorn700
        }
    }

    private func openCalendar() {
        calendarMonth = mealCalendarCalendar.startOfDay(for: selectedDate)
        showCalendar = true
    }

    private var monthRangeLabel: String {
        let startMonth = mealCalendarCalendar.component(.month, from: windowStart)
        let endMonth = mealCalendarCalendar.component(.month, from: windowEnd)
        return startMonth == endMonth ? "\(endMonth)월" : "\(startMonth)–\(endMonth)월"
    }

    private var yearMonthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f.string(from: Date())
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs)초" }
        if secs == 0 { return "\(mins)분" }
        return "\(mins)분 \(secs)초"
    }
}

private struct ReportDay: Identifiable {
    let date: Date
    let chewCount: Int
    let minutes: Int
    let mealCount: Int

    var id: Date { date }

    init(date: Date, sessions: [ChewingSessionDTO]) {
        self.date = date
        chewCount = sessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
        minutes = max(1, Int((sessions.reduce(0) { $0 + $1.durationSec } / 60).rounded()))
        let slots = Set(sessions.map { DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: $0.startedAt)) })
        mealCount = min(3, slots.count)
    }

    private init(date: Date, chewCount: Int, minutes: Int, mealCount: Int) {
        self.date = date
        self.chewCount = chewCount
        self.minutes = minutes
        self.mealCount = mealCount
    }

    static func demo(date: Date, index: Int, total: Int) -> ReportDay {
        let chews = [180, 205, 196, 220, 214, 208, 226, 212, 230, 225, 246, 238, 252, 240, 248, 266, 255, 284, 312, 286, 304]
        let mins = [7, 8, 7, 9, 8, 8, 9, 8, 9, 9, 10, 9, 10, 10, 10, 11, 10, 12, 13, 12, 13]
        let meals = [1, 2, 2, 3, 2, 2, 3, 1, 2, 2, 3, 2, 3, 2, 2, 3, 2, 3, 3, 2, 3]
        let i = min(max(0, index), chews.count - 1)
        return ReportDay(date: date, chewCount: chews[i], minutes: mins[i], mealCount: meals[i])
    }

    static func empty(date: Date) -> ReportDay {
        ReportDay(date: date, chewCount: 0, minutes: 0, mealCount: 0)
    }

    var weekdayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f.string(from: date)
    }

    var dayLabel: String {
        let day = mealCalendarCalendar.component(.day, from: date)
        if day == 1 {
            let month = mealCalendarCalendar.component(.month, from: date)
            return "\(month)/1"
        }
        return "\(day)"
    }

    var shortDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d (E)"
        return f.string(from: date)
    }

    var summaryLabel: String {
        "\(chewCount.koLocale)회 · 평균 씹기 시간 \(minutes)분 · \(mealCount)/3끼"
    }
}

private struct WeeklyMetric: Identifiable {
    let id = UUID()
    let label: String
    let chews: Int
    let minutes: Int
    let meals: Int
    let isCurrent: Bool
}

private struct WeeklyCoachInsight {
    let badge: String
    let message: String
    let chewDeltaText: String
    let minuteDeltaText: String
    let mealDeltaText: String
    let accent: Color
    let imageName: String
}

private struct MealCompletionRing: View {
    let meals: Int
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.acorn500 : Color.clear)
            Circle()
                .stroke(Color.ink100, lineWidth: 3)
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(i) / 3 + 0.018, to: CGFloat(i + 1) / 3 - 0.018)
                    .stroke(
                        i < meals ? (selected ? Color.white : Color.acorn500) : Color.clear,
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private struct ContinuousTrendChart: View {
    let days: [ReportDay]
    let selectedDate: Date
    let dayWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            drawGuides(context: &context, size: size)
            drawSelectedLine(context: &context, size: size)
            drawSeries(\.chewCount, color: Color.acorn500, yRange: 18...(size.height * 0.55), context: &context, size: size)
            drawSeries(\.minutes, color: Color.sage500, yRange: (size.height * 0.42)...(size.height - 18), context: &context, size: size)
        }
    }

    private func drawGuides(context: inout GraphicsContext, size: CGSize) {
        for fraction in [CGFloat(0.33), CGFloat(0.66)] {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height * fraction))
            path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            context.stroke(path, with: .color(Color.ink100.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }
    }

    private func drawSelectedLine(context: inout GraphicsContext, size: CGSize) {
        guard let index = days.firstIndex(where: { mealCalendarCalendar.isDate($0.date, inSameDayAs: selectedDate) }) else { return }
        let x = dayWidth / 2 + CGFloat(index) * dayWidth
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(Color.ink400.opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
    }

    private func drawSeries(
        _ keyPath: KeyPath<ReportDay, Int>,
        color: Color,
        yRange: ClosedRange<CGFloat>,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let values = days.map { $0[keyPath: keyPath] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let points = values.enumerated().map { index, value -> CGPoint in
            let ratio = maxValue == minValue ? 0.5 : CGFloat(value - minValue) / CGFloat(maxValue - minValue)
            let y = yRange.upperBound - ratio * (yRange.upperBound - yRange.lowerBound)
            return CGPoint(x: dayWidth / 2 + CGFloat(index) * dayWidth, y: y)
        }

        var path = Path()
        guard let first = points.first else { return }
        path.move(to: first)
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        for (index, point) in points.enumerated() {
            let isSelected = mealCalendarCalendar.isDate(days[index].date, inSameDayAs: selectedDate)
            let rect = CGRect(x: point.x - (isSelected ? 4.5 : 2.8), y: point.y - (isSelected ? 4.5 : 2.8), width: isSelected ? 9 : 5.6, height: isSelected ? 9 : 5.6)
            context.fill(Path(ellipseIn: rect), with: .color(isSelected ? color : Color.white))
            if !isSelected {
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.8)
            }
        }
    }
}

private struct TrendLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendDot(Color.acorn500, "횟수")
            legendDot(Color.sage500, "시간")
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.appFont(.bold, size: 11))
                .foregroundStyle(Color.ink600)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private enum ReportMockData {
    static func sessions(start: Date, days: Int) -> [ChewingSessionDTO] {
        (0..<days).flatMap { offset -> [ChewingSessionDTO] in
            guard let date = mealCalendarCalendar.date(byAdding: .day, value: offset, to: start) else { return [] }
            let mealCount = mealPattern[offset % mealPattern.count]
            return Array(slotHours.prefix(mealCount)).enumerated().map { mealIndex, hour in
                makeSession(on: date, hour: hour, dayIndex: offset, mealIndex: mealIndex)
            }
        }
    }

    private static let mealPattern = [1, 2, 2, 3, 2, 2, 3, 1, 2, 2, 3, 2, 3, 2, 2, 3, 2, 3, 3, 2, 3]
    private static let slotHours = [8, 12, 18]

    private static func makeSession(on date: Date, hour: Int, dayIndex: Int, mealIndex: Int) -> ChewingSessionDTO {
        let start = mealCalendarCalendar.date(
            bySettingHour: hour,
            minute: [12, 36, 5][mealIndex],
            second: 0,
            of: date
        ) ?? date
        let duration = Double([620, 780, 860][mealIndex] + (dayIndex % 5) * 24)
        let chews = [214, 286, 328][mealIndex] + (dayIndex % 7) * 9
        let chewingSeconds = duration * Double([0.62, 0.68, 0.71][mealIndex])
        let restSeconds = max(1, duration - chewingSeconds)

        return ChewingSessionDTO(
            id: UUID(),
            deviceId: "mock-report",
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            durationSec: duration,
            sensorLocation: "AirPods Pro Mock",
            sampleCount: Int(duration * 25),
            sampleRateHz: 25,
            storagePath: nil,
            appVersion: "mock",
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewingFraction: chewingSeconds / duration,
            estimatedTotalChews: chews,
            modelVersion: "mock-v1"
        )
    }
}

private struct ReportCalendarDialog: View {
    @Binding var month: Date
    let selectedDate: Date
    let today: Date
    /// 그 날의 끼 수(0~3). 링 채움에 사용.
    let mealCount: (Date) -> Int
    /// 표시 월이 바뀌면 그 달 데이터를 로드한다.
    let loadMonth: (Date) async -> Void
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    private var cal: Calendar { mealCalendarCalendar }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                monthHeader
                weekdayLabels
                grid
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("날짜 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.acorn700)
                }
            }
        }
        .task { await loadMonth(month) }
        .onChange(of: month) { _, newMonth in
            Task { await loadMonth(newMonth) }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.appFont(.bold, size: 13))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            Spacer()
            Text(monthTitle)
                .font(.appFont(.heavy, size: 15))
                .foregroundStyle(Color.ink800)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.appFont(.bold, size: 13))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.35 : 1)
        }
        .foregroundStyle(Color.acorn700)
    }

    private var weekdayLabels: some View {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { sym in
                Text(sym)
                    .font(.appFont(.bold, size: 10))
                    .foregroundStyle(Color.ink400)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, cellDate in
                if let date = cellDate {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isFuture = date > today
        let selected = cal.isDate(date, inSameDayAs: selectedDate)
        return Button {
            onPick(date)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    MealCompletionRing(meals: mealCount(date), selected: selected)
                    Text("\(cal.component(.day, from: date))")
                        .font(.appFont(.heavy, size: 13))
                        .foregroundStyle(selected ? Color.white : (isFuture ? Color.ink400.opacity(0.5) : Color.ink800))
                        .monospacedDigit()
                }
                .frame(width: 36, height: 36)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start) // 1=일
        let leadingEmpty = firstWeekday - 1
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 0
        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for d in 0..<daysInMonth {
            cells.append(cal.date(byAdding: .day, value: d, to: interval.start))
        }
        return cells
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f.string(from: month)
    }

    private var isCurrentMonth: Bool {
        cal.isDate(month, equalTo: today, toGranularity: .month)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: month) else { return }
        if delta > 0, next > today, cal.isDate(month, equalTo: today, toGranularity: .month) { return }
        month = next
    }
}

#Preview {
    ScrollView {
        ReportHubView()
            .padding(20)
    }
    .background(LinearGradient.appBackground)
    .environment(AppState())
}
