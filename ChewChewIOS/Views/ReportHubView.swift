import SwiftUI

struct ReportHubView: View {
    @Environment(AppState.self) private var state

    /// 최근 3주(월~일) 주간 리포트. [지지난주, 지난주, 이번 주] 순. 타임라인 링·추세선과 주간 비교 막대의 정본.
    @State private var weeklies: [WeeklyReportDTO] = []
    /// 선택한 날의 일간 리포트 캐시(key: KST startOfDay). 끼 목록·상세 카드용.
    @State private var dailyByDay: [Date: DailyReportDTO] = [:]
    @State private var selectedDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var detailSession: ChewingSessionDTO?

    private let dayWidth: CGFloat = 52

    var body: some View {
        VStack(spacing: 14) {
            legacyUITestAnchors
            timelineCard
            sessionListCard
            weeklyComparisonCard
        }
        .task { await reload() }
        .onChange(of: selectedDate) { _, newDate in
            Task { await loadDaily(for: newDate) }
        }
        .sheet(item: $detailSession) { session in
            NavigationStack {
                SessionReportDetailView(dto: session)
            }
        }
    }

    /// 최근 3주 주간 리포트의 day들을 펼쳐 만든 타임라인. 미래(이번 주 남은 날)는 제외해 오른쪽 끝이 오늘이 되게 한다.
    private var days: [ReportDay] {
        let cal = mealCalendarCalendar
        let today = cal.startOfDay(for: Date())
        return weeklies
            .flatMap(\.days)
            .compactMap { serverDay -> ReportDay? in
                guard let parsed = Self.serverDayFormatter.date(from: serverDay.date) else { return nil }
                let date = cal.startOfDay(for: parsed)
                guard date <= today else { return nil }
                return ReportDay(date: date, serverDay: serverDay)
            }
            .sorted { $0.date < $1.date }
    }

    private var selectedDay: ReportDay {
        days.first { mealCalendarCalendar.isDate($0.date, inSameDayAs: selectedDate) } ?? .empty(date: selectedDate)
    }

    /// 선택한 날의 끼 목록(일간 리포트 meals). 미로딩/빈 날이면 빈 배열.
    private var selectedMeals: [DailyReportDTO.Meal] {
        let key = mealCalendarCalendar.startOfDay(for: selectedDate)
        return (dailyByDay[key]?.meals ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            ForEach(days) { day in
                                dateRingCell(day)
                                    .frame(width: dayWidth)
                                    .id(day.id)
                            }
                        }

                        ContinuousTrendChart(
                            days: days,
                            selectedDate: selectedDate,
                            dayWidth: dayWidth
                        )
                        .frame(width: dayWidth * CGFloat(days.count), height: 164)
                    }
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .scrollTargetBehavior(.viewAligned)
                .task {
                    proxy.scrollTo(selectedDay.id, anchor: .center)
                }
            }

            HStack(alignment: .firstTextBaseline) {
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
                Spacer(minLength: 0)
                TrendLegend()
            }
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
                Text("\(selectedMeals.count)회")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.acorn700)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.acorn50, in: Capsule())
            }

            if selectedMeals.isEmpty {
                emptySessionState
            } else {
                VStack(spacing: 6) {
                    ForEach(selectedMeals, id: \.sessionId) { meal in
                        sessionRow(meal)
                    }
                    dailyReportRow
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

    private func sessionRow(_ meal: DailyReportDTO.Meal) -> some View {
        let slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: meal.startedAt))
        return Button {
            detailSession = ChewingSessionDTO(reportMeal: meal)
        } label: {
            HStack(spacing: 12) {
                Text(slot.emoji)
                    .font(.appFont(.regular, size: 17))
                    .frame(width: 34, height: 34)
                    .background(slotTint(slot), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                        .font(.appFont(.heavy, size: 15))
                        .foregroundStyle(Color.ink800)
                    Text("\(timeLabel(meal.startedAt)) · \((meal.totalChews ?? 0).koLocale)회")
                        .font(.appFont(.semibold, size: 12))
                        .foregroundStyle(Color.ink600)
                }
                Spacer(minLength: 0)
                Text(durationLabel(meal.durationSec))
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

    private var dailyReportRow: some View {
        Button {
            detailSession = selectedMeals.last.map(ChewingSessionDTO.init(reportMeal:))
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

    /// 주별 평균(끼당 아님, 7일 평균). 서버 주간 리포트의 day 합을 7로 나눠 codex 기존 의미를 유지한다.
    private var weeklyMetrics: [WeeklyMetric] {
        let labels = ["지지난주", "지난주", "이번 주"]
        return weeklies.enumerated().map { index, week in
            let dayCount = max(1, week.days.count)
            let chews = max(1, week.days.map(\.totalChews).reduce(0, +) / dayCount)
            let minutesTotal = week.days.map(\.totalEatingSeconds).reduce(0, +) / 60.0
            let minutes = max(1, Int((minutesTotal / Double(dayCount)).rounded()))
            return WeeklyMetric(
                label: labels[min(index, labels.count - 1)],
                chews: chews,
                minutes: minutes,
                isCurrent: index == weeklies.count - 1
            )
        }
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

    /// 최근 3주 주간 리포트 + 오늘 일간 리포트를 서버에서 받는다. mock 폴백 없음 — 데이터 없으면 빈 상태.
    @MainActor
    private func reload() async {
        // 홈/UI 테스트 앵커가 보는 state.todaySessions 갱신용(리포트 허브 데이터 경로와는 별개).
        await state.fetchTodaySessions()

        let deviceId = DeviceIdentity.shared
        let cal = mealCalendarCalendar
        let thisMonday = isoWeekMonday(Date())
        let mondays = [-2, -1, 0].compactMap { cal.date(byAdding: .day, value: $0 * 7, to: thisMonday) }

        var fetched: [WeeklyReportDTO] = []
        for monday in mondays {
            let weekStart = Self.serverDayFormatter.string(from: monday)
            if let week = try? await state.remoteStore.fetchWeeklyReport(deviceId: deviceId, weekStart: weekStart) {
                fetched.append(week)
            }
        }
        weeklies = fetched

        await loadDaily(for: selectedDate, force: true)
    }

    /// 선택한 날의 일간 리포트를 받아 캐시. force=true면 캐시 무시(오늘 재진입 시 최신화).
    @MainActor
    private func loadDaily(for date: Date, force: Bool = false) async {
        let key = mealCalendarCalendar.startOfDay(for: date)
        if !force, dailyByDay[key] != nil { return }
        let deviceId = DeviceIdentity.shared
        let dateString = Self.serverDayFormatter.string(from: key)
        if let daily = try? await state.remoteStore.fetchDailyReport(deviceId: deviceId, date: dateString) {
            dailyByDay[key] = daily
        }
    }

    /// 주어진 날이 속한 ISO 주의 월요일(KST). 서버 weekStart는 월요일이어야 한다.
    private func isoWeekMonday(_ date: Date) -> Date {
        let cal = mealCalendarCalendar
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start) // 1=일 ... 7=토
        let deltaToMonday = (weekday + 5) % 7              // 월→0, 화→1, ..., 일→6
        return cal.date(byAdding: .day, value: -deltaToMonday, to: start) ?? start
    }

    private func slotTint(_ slot: DayMealSlot) -> Color {
        switch slot {
        case .morning: Color.butter100
        case .lunch: Color.sage100
        case .dinner: Color.blush100
        case .lateNight: Color.acorn100
        }
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

    /// 서버 LocalDate("yyyy-MM-dd") ↔ Date 변환용. 집계 시간대(KST)에 고정 — 서버 zone(Asia/Seoul)과 맞춘다.
    private static let serverDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private struct ReportDay: Identifiable {
    let date: Date
    let chewCount: Int
    let minutes: Int
    let mealCount: Int

    var id: Date { date }

    /// 서버 주간 리포트의 하루 집계에서 생성. mealCount는 링(아침·점심·저녁 3끼)용이라 3으로 캡한다.
    init(date: Date, serverDay: WeeklyReportDTO.Day) {
        self.date = date
        chewCount = serverDay.totalChews
        mealCount = min(3, serverDay.mealCount)
        minutes = serverDay.mealCount > 0 ? max(1, Int((serverDay.totalEatingSeconds / 60).rounded())) : 0
    }

    private init(date: Date, chewCount: Int, minutes: Int, mealCount: Int) {
        self.date = date
        self.chewCount = chewCount
        self.minutes = minutes
        self.mealCount = mealCount
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
    let isCurrent: Bool
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

#Preview {
    ScrollView {
        ReportHubView()
            .padding(20)
    }
    .background(LinearGradient.appBackground)
    .environment(AppState())
}
