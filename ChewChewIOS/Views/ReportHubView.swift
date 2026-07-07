import SwiftUI

struct ReportHubView: View {
    @Environment(AppState.self) private var state

    @State private var recentSessions: [ChewingSessionDTO] = []
    @State private var selectedDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var pivotDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var detailSession: ChewingSessionDTO?
    @State private var showDailyReport = false
    @State private var showCalendar = false
    @State private var calendarMonth: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var hasTrackedReportTabView = false

    private let dayWidth: CGFloat = 52
    /// 타임라인 가로 스트립이 한 번에 보여주는 이동 윈도우 길이.
    private let windowDays = 14
    /// 주간 비교·코치 카드용 today-앵커 시리즈 길이(7×3주).
    private let weeklyWindowDays = 21

    var body: some View {
        VStack(spacing: AppSpacing.gap) {
            timelineCard
            weeklyComparisonCard
            // 다람이 코치 카드는 UI에서 임시 제외(로직 유지, 추후 수정 예정).
            // weeklyCoachCard
        }
        .task {
            await reloadRecentSessions()
            trackReportTabViewIfNeeded()
        }
        .onChange(of: pivotDate) { _, _ in
            Task { await loadWindow() }
        }
        .sheet(item: $detailSession) { session in
            NavigationStack {
                SessionReportDetailView(dto: session)
            }
        }
        .sheet(isPresented: $showDailyReport) {
            DailyReportView(
                date: selectedDate,
                sessions: selectedSessions,
                previousSessions: previousDaySessions
            )
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
                    selectDate(date, source: "calendar")
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
        let scale = ChartScale(days: timelineDays)
        let ringRowHeight: CGFloat = 58   // 날짜행 강제 높이(축 스페이서와 동일값으로 세로 정렬 못박음)
        let yAxisWidth: CGFloat = 34
        let bandSpacing: CGFloat = 8      // 날짜행↔차트 간격(축 스페이서와 동일값)

        return VStack(alignment: .leading, spacing: AppSpacing.three) {
            HStack(spacing: AppSpacing.inner) {
                Text(monthRangeLabel)
                    .font(.appFont(.heavyHeadline))
                    .foregroundStyle(Color.textDefault)
                Spacer(minLength: 0)
                Button { openCalendar() } label: {
                    Image(systemName: "calendar")
                        .font(.appFont(.semiboldHeadline))
                        .foregroundStyle(Color.textAction)
                        .frame(width: AppSize.iconContainerCompact, height: AppSize.iconContainerCompact)
                        .background(Color.bgSunken, in: RoundedRectangle(cornerRadius: AppRadius.inner))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("달력 열기")
            }

            // 좌측 고정 Y축 + 스크롤(날짜+차트). 축은 ScrollView 밖이라 가로 스크롤에 안 흘러가고,
            // HStack 좌측 컬럼이라 데이터 점을 가리지 않는다.
            HStack(alignment: .top, spacing: 0) {
                YAxisColumn(scale: scale, ringRowHeight: ringRowHeight, bandSpacing: bandSpacing)
                    .frame(width: yAxisWidth)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: bandSpacing) {
                            HStack(spacing: 0) {
                                ForEach(timelineDays) { day in
                                    dateRingCell(day)
                                        .frame(width: dayWidth)
                                        .id(day.id)
                                }
                            }
                            .frame(height: ringRowHeight)   // 날짜행 높이 강제 → 폰트 메트릭 변동이 정렬을 못 깬다

                            ContinuousTrendChart(
                                days: timelineDays,
                                selectedDate: selectedDate,
                                dayWidth: dayWidth,
                                scale: scale,
                                onSelectDate: { selectDate($0, source: "trend_chart") }
                            )
                            .frame(width: dayWidth * CGFloat(timelineDays.count), height: scale.height)
                        }
                        .padding(.vertical, 2)
                        .padding(.trailing, 4)
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
            }

            // 날짜만 — 평균/시간/끼니 요약·횟수 뱃지는 제거.
            Text(selectedDay.shortDateLabel)
                .font(.appFont(.heavyHeadline))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppSpacing.half)

            if !selectedSessions.isEmpty {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: Metrics.chartHairline)
                    .padding(.vertical, AppSpacing.half)

                // 끼니 목록 — 날짜 헤더는 위와 중복이라 뺀다(그래프 카드와 합쳐진 한 카드).
                VStack(spacing: 6) {
                    ForEach(selectedSessions) { session in
                        sessionRow(session)
                    }
                    dailyReportRow
                }
            } else {
                emptySessionState
            }
        }
        .padding(.horizontal, AppSpacing.cardContent)
        .padding(.vertical, AppSpacing.three)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var emptySessionState: some View {
        HStack(spacing: AppSpacing.three) {
            Text("🍽️")
                .font(.appFont(.regularDisplaySmall))
                .frame(width: Metrics.emptyIcon, height: Metrics.emptyIcon)
            VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                Text(mealCalendarCalendar.isDateInToday(selectedDate) ? "오늘은 아직 식사 전이에요" : "이 날은 식사 기록이 없어요")
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textPrimary)
                Text("식사를 기록하면 아침·점심·저녁 리포트가 여기에 쌓여요.")
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, AppSpacing.half)
    }

    private func dateRingCell(_ day: ReportDay) -> some View {
        let selected = mealCalendarCalendar.isDate(day.date, inSameDayAs: selectedDate)
        return Button {
            selectDate(day.date, source: "date_ring")
        } label: {
            VStack(spacing: AppSpacing.oneHalf) {
                Text(day.weekdayLabel)
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(selected ? Color.acorn700 : Color.textMuted)
                ZStack {
                    MealCompletionRing(meals: day.mealCount, selected: selected)
                    Text(day.dayLabel)
                        .font(.appFont(day.dayLabel.contains("/") ? .heavyCaption : .heavyLabel))
                        .foregroundStyle(selected ? Color.white : Color.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                }
                .frame(width: Metrics.dateRing, height: Metrics.dateRing)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.shortDateLabel), \(day.mealCount)끼 기록")
    }

    private func sessionRow(_ session: ChewingSessionDTO) -> some View {
        let slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: session.startedAt))
        return Button {
            trackMealReportOpened(session, source: "report_hub")
            detailSession = session
        } label: {
            HStack(spacing: AppSpacing.three) {
                OpenIconView(icon: slot.openIcon, color: slotIconColor(slot), lineWidth: 2.1)
                    .frame(width: AppSize.iconSmall, height: AppSize.iconSmall)
                    .frame(width: AppSize.iconContainer, height: AppSize.iconContainer)
                    .background(slotTint(slot), in: RoundedRectangle(cornerRadius: AppRadius.iconContainer))
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                        .font(.appFont(.heavyBody))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(timeLabel(session.startedAt)) · \((session.estimatedTotalChews ?? 0).koLocale)회")
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                Text(durationLabel(session.durationSec))
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.appFont(.boldMicro))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, AppSpacing.two)
        }
        .buttonStyle(.plain)
    }

    private var dailyInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("하루 리포트 요약")
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
                Text(selectedDay.mealCount == 0 ? "기록 전" : "\(selectedDay.mealCount)/3끼")
                    .font(.appFont(.heavyMicro))
                    .foregroundStyle(selectedDay.mealCount == 0 ? Color.textTertiary : Color.acorn700)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.72), in: Capsule())
            }

            dailyInsightRow(
                icon: "calendar.badge.clock",
                title: "아침·점심·저녁",
                value: dailySlotSummary,
                detail: "기록된 끼니만 집계해요."
            )
            dailyInsightRow(
                icon: "arrow.left.arrow.right",
                title: "어제 대비",
                value: dailyDeltaSummary,
                detail: "어제와 같은 기준으로 저작 횟수를 비교한 값이에요."
            )
            dailyInsightRow(
                icon: "chart.bar.fill",
                title: "끼니 비교",
                value: mealComparisonSummary,
                detail: "가장 많이 씹은 끼를 짚어줘요."
            )
            dailyInsightRow(
                icon: "fork.knife",
                title: "한 끼 평균",
                value: "약 \(selectedDay.avgChewCount.koLocale)회 · \(selectedDay.minutes)분",
                detail: "한 끼 기준 평균 저작 횟수와 식사 시간이에요."
            )
        }
        .padding(AppSpacing.cell)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusSuccessMuted.opacity(0.72), in: RoundedRectangle(cornerRadius: AppRadius.container))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.container)
                .stroke(Color.statusSuccessBorder, lineWidth: AppSize.border)
        )
        .padding(.top, AppSpacing.one)
    }

    private func dailyInsightRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.inner) {
            Image(systemName: icon)
                .font(.appFont(.boldCaption))
                .foregroundStyle(Color.statusSuccess)
                .frame(width: AppSpacing.six, height: AppSpacing.six)
                .background(Color.bgSurface.opacity(0.75), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.half) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.oneHalf) {
                    Text(title)
                        .font(.appFont(.boldCaption))
                        .foregroundStyle(Color.textDefault)
                    Text(value)
                        .font(.appFont(.heavyCaption))
                        .foregroundStyle(Color.statusSuccess)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()
                }
                Text(detail)
                    .font(.appFont(.semiboldCaption))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }

    /// 어제(선택일 직전 날) 세션 — 일간 리포트의 "어제 대비" 비교 입력.
    private var previousDaySessions: [ChewingSessionDTO] {
        guard let previousDate = mealCalendarCalendar.date(byAdding: .day, value: -1, to: selectedDate) else {
            return []
        }
        return sessions(on: previousDate)
    }

    private var dailyReportRow: some View {
        Button {
            showDailyReport = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("일간 리포트")
                        .font(.appFont(.heavyBody))
                        .foregroundStyle(Color.acorn700)
                    Text("하루 전체 요약 보기")
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.acorn700)
            }
            .padding(AppSpacing.three)
            .background(Color.bgSunken, in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }

    private var weeklyComparisonCard: some View {
        let weeks = weeklyMetrics
        let hasData = weeks.contains { $0.meals > 0 }
        let maxChews = max(1, weeks.map(\.chews).max() ?? 1)
        let maxMinutes = max(1, weeks.map(\.minutes).max() ?? 1)

        return AppCard(padding: AppSpacing.three) {
            VStack(alignment: .leading, spacing: AppSpacing.two) {
            HStack {
                Text("주간 리포트")
                    .font(.appFont(.heavyBodyLarge))
                    .foregroundStyle(Color.textDefault)
                Spacer()
                if hasData { TrendLegend() }
            }

            if hasData {
                HStack(alignment: .bottom, spacing: AppSpacing.four) {
                    ForEach(weeks) { week in
                        VStack(spacing: 7) {
                            HStack(alignment: .bottom, spacing: 7) {
                                metricBar(value: week.chews, maxValue: maxChews, color: Color.acorn500, label: "\(week.chews)")
                                metricBar(value: week.minutes, maxValue: maxMinutes, color: Color.sage500, label: "\(week.minutes)분")
                            }
                            // 현재 주만 라벨 weight/색으로 표시 — 막대는 비교를 위해 모두 같은 농도로 둔다
                            // (이전엔 opacity 0.58 + ink400 + 약한 weight 삼중 인코딩으로 과거 주가 안 보였다).
                            Text(week.label)
                                .font(.appFont(week.isCurrent ? .heavyLabel : .semiboldLabel))
                                .foregroundStyle(week.isCurrent ? Color.textPrimary : Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Metrics.weeklyChartHeight)
            } else {
                Text("이번 주 식사 기록이 쌓이면 지난 흐름과 비교해서 보여줄게요.")
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.five)
            }
            }
        }
    }

    private var weeklyCoachCard: some View {
        let insight = weeklyCoachInsight
        return AppCard(padding: AppSpacing.cell) {
            HStack(alignment: .top, spacing: AppSpacing.three) {
            Image(insight.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.weeklyCoachAvatar, height: Metrics.weeklyCoachAvatar)
                .background(Color.statusWarningMuted.opacity(0.72), in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.inner) {
                VStack(alignment: .leading, spacing: AppSpacing.one) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.oneHalf) {
                        Text("다람이 코치")
                            .font(.appFont(.heavyBody))
                            .foregroundStyle(Color.textDefault)
                        Text(insight.badge)
                            .font(.appFont(.heavyMicro))
                            .foregroundStyle(insight.accent)
                            .padding(.horizontal, AppSpacing.badgeH)
                            .padding(.vertical, AppSpacing.badgeV)
                            .background(insight.accent.opacity(0.14), in: Capsule())
                    }
                    Text(insight.message)
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textMuted)
                        .lineSpacing(2)
                }

                HStack(spacing: AppSpacing.two) {
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
        }
    }

    private func coachMetricPill(title: String, value: String, icon: OpenIcon, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.microLabelGap) {
            HStack(spacing: AppSpacing.one) {
                OpenIconView(icon: icon, color: color, lineWidth: 2.1)
                    .frame(width: Metrics.legendIcon, height: Metrics.legendIcon)
                Text(title)
                    .font(.appFont(.boldMicro))
                    .foregroundStyle(Color.textMuted)
            }
            Text(value)
                .font(.appFont(.heavyMicro))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.iconGap)
        .padding(.vertical, AppSpacing.two)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: AppSpacing.three))
    }

    private func metricBar(value: Int, maxValue: Int, color: Color, label: String) -> some View {
        VStack(spacing: AppSpacing.one) {
            Text(label)
                .font(.appFont(.heavyCallout))
                .foregroundStyle(color)
                .monospacedDigit()
            RoundedRectangle(cornerRadius: AppSpacing.oneHalf)
                .fill(color)
                .frame(width: Metrics.chartBarWidth, height: max(Metrics.chartBarMinHeight, CGFloat(value) / CGFloat(maxValue) * Metrics.chartBarMaxHeight))
        }
    }

    private var weeklyMetrics: [WeeklyMetric] {
        let chunks = weeklyDays.chunked(into: 7)
        let labels = ["지지난주", "지난주", "이번 주"]
        return chunks.enumerated().map { index, chunk in
            // 데이터 있는 날 수로만 나눈다(7로 고정 나눗셈 + max(1,…) 가짜 클램프 제거).
            // 기록 없는 주는 진짜 0으로 둔다.
            let daysWithData = chunk.filter { $0.mealCount > 0 }.count
            let chews = daysWithData == 0 ? 0 : chunk.map(\.avgChewCount).reduce(0, +) / daysWithData
            let minutes = daysWithData == 0 ? 0 : chunk.map(\.minutes).reduce(0, +) / daysWithData
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
                message: "기록이 쌓이면 지지난주와 이번 주를 비교해서 식사 리듬 변화를 알려줄게요.",
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
                message: "지지난주보다 이번 주 식사 리듬이 더 여유로워졌어요. 주간 평균 저작은 \(formatPercent(chewPercent)) 변했고, 식사 시간도 \(formatPercent(minutePercent)) 변했어요.",
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
                message: "이번 주는 지지난주와 비슷한 리듬을 유지하고 있어요. 다음 목표는 한 끼에서 조금 더 천천히 씹는 구간을 늘리는 거예요.",
                chewDeltaText: signedDelta(chewDelta, suffix: "회"),
                minuteDeltaText: signedDelta(minuteDelta, suffix: "분"),
                mealDeltaText: signedDelta(mealDelta, suffix: "끼"),
                accent: .butter600,
                imageName: Mood.puffy.imageName
            )
        }

        return WeeklyCoachInsight(
            badge: "다시 시작",
            message: "이번 주 식사 리듬은 지지난주보다 조금 짧아졌어요. 다음 식사에서는 첫 5분만 속도를 낮춰서 다시 흐름을 만들어봐요.",
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
        let diff = selectedDay.avgChewCount - previous.avgChewCount
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
        return "\(top.key.label) 약 \(top.value.koLocale)회"
    }

    private var previousReportDay: ReportDay? {
        guard let previousDate = mealCalendarCalendar.date(byAdding: .day, value: -1, to: selectedDate) else {
            return nil
        }
        let daySessions = sessions(on: previousDate)
        return daySessions.isEmpty ? ReportDay.empty(date: previousDate) : ReportDay(date: previousDate, sessions: daySessions)
    }

    @MainActor
    private func reloadRecentSessions() async {
        await state.mealResults.fetchTodaySessions()
        // 주간 카드(21일) + 현재 타임라인 윈도우를 모두 덮는 초기 범위.
        let weeklyStart = mealCalendarCalendar.date(byAdding: .day, value: -(weeklyWindowDays - 1), to: today) ?? today
        let start = min(weeklyStart, windowStart)
        let end = mealCalendarCalendar.date(byAdding: .day, value: 1, to: today) ?? today
        // 빈 결과면 진짜 빈 상태를 보여준다. 가짜 세션 주입 금지 — 사용자가 안 한 식사를 보면 안 된다.
        recentSessions = await fetchMerged(since: start, until: end, into: recentSessions)
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
        state.analytics.track(.reportCalendarOpened(
            selectedDate: analyticsDateString(selectedDate),
            daysFromToday: daysFromToday(selectedDate),
            mealCount: selectedDay.mealCount
        ))
        calendarMonth = mealCalendarCalendar.startOfDay(for: selectedDate)
        showCalendar = true
    }

    private func selectDate(_ date: Date, source: String) {
        let normalizedDate = mealCalendarCalendar.startOfDay(for: date)
        selectedDate = normalizedDate
        state.analytics.track(.reportDateSelected(
            source: source,
            selectedDate: analyticsDateString(normalizedDate),
            daysFromToday: daysFromToday(normalizedDate),
            mealCount: mealCount(for: normalizedDate)
        ))
    }

    private func trackReportTabViewIfNeeded() {
        guard !hasTrackedReportTabView else { return }
        hasTrackedReportTabView = true
        state.analytics.track(.reportTabViewed(
            selectedDate: analyticsDateString(selectedDate),
            daysFromToday: daysFromToday(selectedDate),
            mealCount: selectedDay.mealCount
        ))
    }

    private func trackMealReportOpened(_ session: ChewingSessionDTO, source: String) {
        let date = mealCalendarCalendar.startOfDay(for: session.startedAt)
        let slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: session.startedAt))
        let score = ReportCardModel.from(session)?.score
        state.analytics.track(.mealReportOpened(
            source: source,
            selectedDate: analyticsDateString(date),
            daysFromToday: daysFromToday(date),
            mealSlot: slot.analyticsValue,
            score: score,
            estimatedTotalChews: session.estimatedTotalChews,
            durationSec: Int(session.durationSec.rounded())
        ))
    }

    private func analyticsDateString(_ date: Date) -> String {
        KoDate.string(date, "yyyy-MM-dd")
    }

    private func daysFromToday(_ date: Date) -> Int {
        let normalizedDate = mealCalendarCalendar.startOfDay(for: date)
        return mealCalendarCalendar.dateComponents([.day], from: today, to: normalizedDate).day ?? 0
    }

    private var monthRangeLabel: String {
        let startMonth = mealCalendarCalendar.component(.month, from: windowStart)
        let endMonth = mealCalendarCalendar.component(.month, from: windowEnd)
        return startMonth == endMonth ? "\(endMonth)월" : "\(startMonth)–\(endMonth)월"
    }

    private func timeLabel(_ date: Date) -> String {
        return KoDate.clockTime(date)
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
    /// 하루 저작 횟수 합계(원자료). 화면 표시는 한 끼 평균(avgChewCount)을 쓴다.
    let chewCount: Int
    /// 하루 세션 시간의 "세션당 평균"(분). "한 끼에 보통 몇 분 씹었나".
    let minutes: Int
    /// 하루 저작 횟수의 "세션당 평균"(회). "한 끼에 보통 몇 번 씹었나".
    let avgChewCount: Int
    let mealCount: Int

    var id: Date { date }

    init(date: Date, sessions: [ChewingSessionDTO]) {
        self.date = date
        let count = sessions.count
        let totalChews = sessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
        let totalSec = sessions.reduce(0.0) { $0 + $1.durationSec }
        chewCount = totalChews
        avgChewCount = count == 0 ? 0 : Int((Double(totalChews) / Double(count)).rounded())
        minutes = count == 0 ? 0 : max(1, Int((totalSec / Double(count) / 60).rounded()))
        let slots = Set(sessions.map { DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: $0.startedAt)) })
        mealCount = min(3, slots.count)
    }

    private init(date: Date, chewCount: Int, minutes: Int, avgChewCount: Int, mealCount: Int) {
        self.date = date
        self.chewCount = chewCount
        self.minutes = minutes
        self.avgChewCount = avgChewCount
        self.mealCount = mealCount
    }

    static func empty(date: Date) -> ReportDay {
        ReportDay(date: date, chewCount: 0, minutes: 0, avgChewCount: 0, mealCount: 0)
    }

    var weekdayLabel: String {
        return KoDate.string(date, "E")
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
        return KoDate.string(date, "M/d (E)")
    }

    var summaryLabel: String {
        "\(avgChewCount.koLocale)회 · 씹은 시간 \(minutes)분 · \(mealCount)/3끼"
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
                .stroke(Color.hairline, lineWidth: 3)
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

/// 차트와 좌측 고정 Y축이 공유하는 스케일. y매핑과 보기 좋은 눈금값을 한 곳에서 계산해
/// Canvas 점/그리드라인과 거터 눈금이 픽셀 단위로 정렬되게 한다.
private struct ChartScale {
    let maxValue: Int
    let topPad: CGFloat
    let bottomPad: CGFloat
    let height: CGFloat

    init(days: [ReportDay], topPad: CGFloat = 16, bottomPad: CGFloat = 14, height: CGFloat = 132) {
        self.maxValue = max(days.map(\.avgChewCount).max() ?? 1, 1)
        self.topPad = topPad
        self.bottomPad = bottomPad
        self.height = height
    }

    /// 값 → 밴드 height 안의 y좌표. Canvas와 Y축 거터가 동일하게 쓴다.
    func y(_ value: Int) -> CGFloat {
        let bottom = height - bottomPad
        return bottom - CGFloat(value) / CGFloat(max(maxValue, 1)) * (bottom - topPad)
    }

    /// 0~maxValue를 1/2/5×10ⁿ 간격으로 끊은 눈금값(0 포함, 실제 최댓값 항상 포함).
    var tickValues: [Int] {
        let m = max(maxValue, 1)
        let rawStep = Double(m) / 4.0
        let mag = pow(10.0, floor(log10(max(rawStep, 1.0))))
        let norm = rawStep / mag
        let niceNorm: Double = norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))
        let step = max(1, Int(niceNorm * mag))
        var ticks: [Int] = []
        var v = 0
        while v < m { ticks.append(v); v += step }
        ticks.append(m)
        return ticks
    }
}

/// 한 끼 평균 저작 횟수 단일 시리즈 스파크라인 + 가로 그리드라인. 스케일을 `ChartScale`로 주입받아
/// 좌측 고정 Y축 거터(`YAxisColumn`)와 눈금이 정확히 정렬된다. 탭하면 가장 가까운 날을 선택한다.
private struct ContinuousTrendChart: View {
    let days: [ReportDay]
    let selectedDate: Date
    let dayWidth: CGFloat
    let scale: ChartScale
    let onSelectDate: (Date) -> Void

    var body: some View {
        Canvas { context, size in
            let values = days.map(\.avgChewCount)
            func y(_ value: Int) -> CGFloat { scale.y(value) }
            func x(_ index: Int) -> CGFloat { dayWidth / 2 + CGFloat(index) * dayWidth }

            // 가로 그리드라인 — 좌측 Y축 눈금과 1:1. 0은 실선(바닥), 그 외 점선.
            for tick in scale.tickValues {
                let gy = y(tick)
                let isBaseline = tick == 0
                var line = Path()
                line.move(to: CGPoint(x: 0, y: gy))
                line.addLine(to: CGPoint(x: size.width, y: gy))
                context.stroke(
                    line,
                    with: .color(Color.textTertiary.opacity(isBaseline ? 0.4 : 0.18)),
                    style: StrokeStyle(lineWidth: isBaseline ? 1 : 0.75, dash: isBaseline ? [] : [3, 4])
                )
            }

            // 평소(데이터 있는 날 평균) 기준선.
            let withData = values.filter { $0 > 0 }
            if !withData.isEmpty {
                let mean = withData.reduce(0, +) / withData.count
                let my = y(mean)
                var guideLine = Path()
                guideLine.move(to: CGPoint(x: 0, y: my))
                guideLine.addLine(to: CGPoint(x: size.width, y: my))
                context.stroke(guideLine, with: .color(Color.accentChew.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                context.draw(
                    Text("평소 \(mean)회").font(.appFont(.boldMicro)).foregroundColor(Color.tintPrimary),
                    at: CGPoint(x: 4, y: my - 4), anchor: .bottomLeading
                )
            }

            // 선택일 세로선 — x() 불변 → 날짜 동그라미 밑 정렬 유지.
            if let index = days.firstIndex(where: { mealCalendarCalendar.isDate($0.date, inSameDayAs: selectedDate) }) {
                var sel = Path()
                sel.move(to: CGPoint(x: x(index), y: 0))
                sel.addLine(to: CGPoint(x: x(index), y: size.height))
                context.stroke(sel, with: .color(Color.textTertiary.opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
            }

            // 저작 횟수 단일 라인 + 점
            let points = values.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) }
            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for i in 1..<points.count { path.addLine(to: points[i]) }
                context.stroke(path, with: .color(Color.accentChew), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            for (index, point) in points.enumerated() {
                let isSelected = mealCalendarCalendar.isDate(days[index].date, inSameDayAs: selectedDate)
                let r: CGFloat = isSelected ? 4.5 : 2.8
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(isSelected ? Color.accentChew : Color.surface))
                if !isSelected {
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.accentChew), lineWidth: 1.8)
                }
            }
        }
        .contentShape(Rectangle())
        // 그래프를 탭하면 가장 가까운 날짜로 이동 — 날짜 동그라미 탭과 동일.
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard !days.isEmpty else { return }
                let raw = (value.location.x - dayWidth / 2) / dayWidth
                let idx = max(0, min(days.count - 1, Int(raw.rounded())))
                onSelectDate(days[idx].date)
            }
        )
    }
}

/// 차트 좌측에 화면 고정되는 Y축 컬럼. 데이터를 가리지 않게 HStack 좌측으로 분리돼 있고,
/// 날짜행 높이 + 밴드 간격만큼 비운 뒤 차트 밴드와 같은 스케일로 눈금을 그린다.
private struct YAxisColumn: View {
    let scale: ChartScale
    let ringRowHeight: CGFloat
    let bandSpacing: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // 날짜행 + 밴드 간격 + 상단 padding(4)만큼 비워 차트 밴드 상단에 정렬.
            Color.clear.frame(height: ringRowHeight + bandSpacing + 2)
            Canvas { context, size in
                for tick in scale.tickValues {
                    let yy = scale.y(tick)
                    var t = Path()
                    t.move(to: CGPoint(x: size.width - 5, y: yy))
                    t.addLine(to: CGPoint(x: size.width, y: yy))
                    context.stroke(t, with: .color(Color.textTertiary.opacity(0.5)), lineWidth: 1)
                    if tick > 0 {
                        context.draw(
                            Text("\(tick)").font(.appFont(.boldMicro)).foregroundColor(Color.textMuted),
                            at: CGPoint(x: size.width - 7, y: yy), anchor: .trailing
                        )
                    }
                }
            }
            .frame(height: scale.height)
        }
        .frame(height: ringRowHeight + bandSpacing + 2 + scale.height)
        .accessibilityHidden(true)
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
        HStack(spacing: AppSpacing.microLabelGap) {
            Circle().fill(color).frame(width: Metrics.legendDot, height: Metrics.legendDot)
            Text(label)
                .font(.appFont(.boldCallout))
                .foregroundStyle(Color.textMuted)
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
            VStack(spacing: AppSpacing.three) {
                monthHeader
                weekdayLabels
                grid
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.page)
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppSheetTitleText(title: "날짜 선택")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetTextActionButton(title: "닫기") { dismiss() }
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
                    .font(.appFont(.boldCallout))
                    .frame(width: Metrics.calendarButton, height: Metrics.calendarButton)
                    .background(Color.bgSurface.opacity(0.7), in: Circle())
            }
            Spacer()
            Text(monthTitle)
                .font(.appFont(.heavyBody))
                .foregroundStyle(Color.textDefault)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.appFont(.boldCallout))
                    .frame(width: Metrics.calendarButton, height: Metrics.calendarButton)
                    .background(Color.bgSurface.opacity(0.7), in: Circle())
            }
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.35 : 1)
        }
        .foregroundStyle(Color.textAction)
    }

    private var weekdayLabels: some View {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return HStack(spacing: AppSpacing.one) {
            ForEach(symbols, id: \.self) { sym in
                Text(sym)
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.one), count: 7), spacing: AppSpacing.two) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, cellDate in
                if let date = cellDate {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: Metrics.calendarCellHeight)
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
                        .font(.appFont(.heavyCallout))
                        .foregroundStyle(selected ? Color.textActionInverse : (isFuture ? Color.textSubtle.opacity(0.5) : Color.textDefault))
                        .monospacedDigit()
                }
                .frame(width: Metrics.calendarRing, height: Metrics.calendarRing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.calendarCellHeight)
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
        return KoDate.string(month, "yyyy년 M월")
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

#Preview("Light") {
    ScrollView {
        ReportHubView()
            .padding(AppSpacing.page)
    }
    .background(LinearGradient.appBackground)
    .environment(AppState())
}

#Preview("Dark") {
    ScrollView {
        ReportHubView()
            .padding(AppSpacing.page)
    }
    .background(LinearGradient.appBackground)
    .environment(AppState())
    .preferredColorScheme(.dark)
}

private enum Metrics {
    static let chartHairline = AppSize.border
    static let dateRing = AppSize.controlXLarge
    static let emptyIcon: CGFloat = 42
    static let weeklyChartHeight: CGFloat = 104
    static let weeklyCoachAvatar: CGFloat = 66
    static let legendIcon: CGFloat = 13
    static let legendDot = AppSize.indicatorMedium
    static let chartBarWidth: CGFloat = 18
    static let chartBarMinHeight: CGFloat = 16
    static let chartBarMaxHeight: CGFloat = 64
    static let calendarButton = AppSize.controlLarge
    static let calendarCellHeight: CGFloat = 46
    static let calendarRing = AppSize.iconContainerLarge
}
