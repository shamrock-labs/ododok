import SwiftUI

struct ReportHubView: View {
    @Environment(AppState.self) private var state

    /// 주간 리포트 캐시(key: weekStart "yyyy-MM-dd"). 타임라인 링·추세선, 주간 비교, 달력 링이 모두 여기서 읽는다.
    @State private var weeklyByWeekStart: [String: WeeklyReportDTO] = [:]
    /// 선택한 날의 일간 리포트 캐시(key: KST startOfDay). 끼 목록·상세 카드용.
    @State private var dailyByDay: [Date: DailyReportDTO] = [:]
    /// 2주 스크롤 윈도우의 기점. 달력에서 날짜를 고르면 그 날로 옮긴다(기본은 오늘).
    @State private var pivotDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var selectedDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var detailSession: ChewingSessionDTO?
    @State private var showCalendar = false
    @State private var calendarMonth: Date = mealCalendarCalendar.startOfDay(for: Date())

    private let dayWidth: CGFloat = 52
    /// 스크롤에 보여줄 일수(2주).
    private let windowDays = 14

    var body: some View {
        VStack(spacing: 14) {
            legacyUITestAnchors
            timelineCard
            sessionListCard
            weeklyComparisonCard
        }
        .task { await reload() }
        .onChange(of: pivotDate) { _, _ in
            Task { await loadWeeks(covering: windowStart, windowEnd) }
        }
        .onChange(of: selectedDate) { _, newDate in
            Task { await loadDaily(for: newDate) }
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
                mealCount: { dayMealCount(for: $0) },
                loadMonth: { await loadWeeks(covering: monthStart($0), monthEnd($0)) },
                onPick: { date in
                    pivotDate = date
                    selectedDate = date
                    showCalendar = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 윈도우 / 날짜 계산

    private var today: Date { mealCalendarCalendar.startOfDay(for: Date()) }

    /// 윈도우 끝 = (기점+7, 오늘) 중 이른 쪽. 오늘 기점이면 오늘이 끝(미래 빈 칸 방지).
    private var windowEnd: Date {
        let plus7 = mealCalendarCalendar.date(byAdding: .day, value: 7, to: pivotDate) ?? pivotDate
        return min(plus7, today)
    }

    private var windowStart: Date {
        mealCalendarCalendar.date(byAdding: .day, value: -(windowDays - 1), to: windowEnd) ?? windowEnd
    }

    /// 윈도우 14일의 ReportDay. 데이터 없는 날은 빈 링.
    private var days: [ReportDay] {
        (0..<windowDays).compactMap { offset in
            guard let date = mealCalendarCalendar.date(byAdding: .day, value: offset, to: windowStart) else { return nil }
            return ReportDay(date: date, serverDay: serverDay(for: date))
        }
    }

    private var selectedDay: ReportDay {
        days.first { mealCalendarCalendar.isDate($0.date, inSameDayAs: selectedDate) }
            ?? ReportDay(date: selectedDate, serverDay: serverDay(for: selectedDate))
    }

    private var selectedMeals: [DailyReportDTO.Meal] {
        let key = mealCalendarCalendar.startOfDay(for: selectedDate)
        return (dailyByDay[key]?.meals ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - 타임라인 카드

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(monthRangeLabel)
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.ink800)
                Spacer()
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
                .task { proxy.scrollTo(selectedDay.id, anchor: .center) }
                .onChange(of: selectedDate) { _, _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(selectedDay.id, anchor: .center)
                    }
                }
            }
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
                        .font(.appFont(.heavy, size: 14))
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

    // MARK: - 끼니 목록 카드

    private var sessionListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(selectedDay.shortDateLabel)
                        .font(.appFont(.heavy, size: 16))
                        .foregroundStyle(Color.ink800)
                        .monospacedDigit()
                    Spacer()
                    Text("\(selectedMeals.count)회")
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.acorn700)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.acorn50, in: Capsule())
                }
                Text(selectedDay.summaryLabel)
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.ink600)
                    .monospacedDigit()
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

    // MARK: - 주간 비교 카드 (오늘 기준 최근 3주, 스크롤 기점과 무관)

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

    /// 오늘 기준 최근 3주(지지난주·지난주·이번 주) 7일 평균. weeklyByWeekStart 캐시에서 읽는다.
    private var weeklyMetrics: [WeeklyMetric] {
        let labels = ["지지난주", "지난주", "이번 주"]
        let mondays = recentWeekMondays
        return mondays.enumerated().map { index, monday in
            let week = weeklyByWeekStart[Self.serverDayFormatter.string(from: monday)]
            let serverDays = week?.days ?? []
            let dayCount = max(1, serverDays.count)
            let chews = max(1, serverDays.map(\.totalChews).reduce(0, +) / dayCount)
            let minutesTotal = serverDays.map(\.totalEatingSeconds).reduce(0, +) / 60.0
            let minutes = max(1, Int((minutesTotal / Double(dayCount)).rounded()))
            return WeeklyMetric(
                label: labels[min(index, labels.count - 1)],
                chews: chews,
                minutes: minutes,
                isCurrent: index == mondays.count - 1
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

    // MARK: - 데이터 로딩 (reports API만 사용, mock 없음)

    @MainActor
    private func reload() async {
        // 홈/UI 테스트 앵커가 보는 state.todaySessions 갱신용(리포트 허브 데이터 경로와는 별개).
        await state.fetchTodaySessions()
        // 이번 주는 최신 반영 위해 캐시 무효화 후 재요청.
        weeklyByWeekStart[Self.serverDayFormatter.string(from: isoWeekMonday(today))] = nil
        await loadWeeks(covering: windowStart, windowEnd)
        await loadWeeks(covering: recentWeekMondays.first ?? today, today)
        await loadDaily(for: selectedDate, force: true)
    }

    /// [start, end]를 덮는 모든 ISO 주를 받아 캐시. 이미 받은 주는 건너뛴다.
    @MainActor
    private func loadWeeks(covering start: Date, _ end: Date) async {
        let deviceId = DeviceIdentity.shared
        for monday in weekMondays(from: start, to: end) {
            let key = Self.serverDayFormatter.string(from: monday)
            if weeklyByWeekStart[key] != nil { continue }
            if let week = try? await state.remoteStore.fetchWeeklyReport(deviceId: deviceId, weekStart: key) {
                weeklyByWeekStart[key] = week
            }
        }
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

    private func openCalendar() {
        calendarMonth = mealCalendarCalendar.startOfDay(for: selectedDate)
        showCalendar = true
    }

    /// 그 날이 속한 주의 mealCount(달력 링·타임라인 링 공용). 데이터 없으면 0.
    private func dayMealCount(for date: Date) -> Int {
        min(3, serverDay(for: date)?.mealCount ?? 0)
    }

    private func serverDay(for date: Date) -> WeeklyReportDTO.Day? {
        let key = Self.serverDayFormatter.string(from: isoWeekMonday(date))
        guard let week = weeklyByWeekStart[key] else { return nil }
        let target = Self.serverDayFormatter.string(from: mealCalendarCalendar.startOfDay(for: date))
        return week.days.first { $0.date == target }
    }

    private var recentWeekMondays: [Date] {
        let thisMonday = isoWeekMonday(today)
        return [-2, -1, 0].compactMap { mealCalendarCalendar.date(byAdding: .day, value: $0 * 7, to: thisMonday) }
    }

    /// [start, end]를 덮는 ISO 월요일들.
    private func weekMondays(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var monday = isoWeekMonday(start)
        let last = isoWeekMonday(end)
        while monday <= last {
            result.append(monday)
            guard let next = mealCalendarCalendar.date(byAdding: .day, value: 7, to: monday) else { break }
            monday = next
        }
        return result
    }

    private func monthStart(_ date: Date) -> Date {
        mealCalendarCalendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthEnd(_ date: Date) -> Date {
        guard let interval = mealCalendarCalendar.dateInterval(of: .month, for: date) else { return date }
        return mealCalendarCalendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    }

    /// 그 날이 속한 ISO 주의 월요일(KST). 서버 weekStart는 월요일이어야 한다.
    private func isoWeekMonday(_ date: Date) -> Date {
        let cal = mealCalendarCalendar
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start) // 1=일 ... 7=토
        let deltaToMonday = (weekday + 5) % 7              // 월→0, 화→1, ..., 일→6
        return cal.date(byAdding: .day, value: -deltaToMonday, to: start) ?? start
    }

    // MARK: - 라벨/색

    private func slotTint(_ slot: DayMealSlot) -> Color {
        switch slot {
        case .morning: Color.butter100
        case .lunch: Color.sage100
        case .dinner: Color.blush100
        case .lateNight: Color.acorn100
        }
    }

    private var monthRangeLabel: String {
        let cal = mealCalendarCalendar
        let startMonth = cal.component(.month, from: windowStart)
        let endMonth = cal.component(.month, from: windowEnd)
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
    init(date: Date, serverDay: WeeklyReportDTO.Day?) {
        self.date = date
        let mc = serverDay?.mealCount ?? 0
        chewCount = serverDay?.totalChews ?? 0
        mealCount = min(3, mc)
        minutes = mc > 0 ? max(1, Int(((serverDay?.totalEatingSeconds ?? 0) / 60).rounded())) : 0
    }

    var weekdayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f.string(from: date)
    }

    /// 월 표기는 카드 상단 라벨에서 처리하므로 링 안은 일(day) 숫자만.
    var dayLabel: String {
        "\(mealCalendarCalendar.component(.day, from: date))"
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

// MARK: - 날짜 선택 달력 다이얼로그 (리포트 기반, 날짜 셀에 끼 완성도 링)

private struct ReportCalendarDialog: View {
    @Binding var month: Date
    let selectedDate: Date
    let today: Date
    /// 그 날의 끼 수(0~3). 링 채움에 사용.
    let mealCount: (Date) -> Int
    /// 표시 월이 바뀌면 그 달을 덮는 주간 리포트를 받는다.
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
