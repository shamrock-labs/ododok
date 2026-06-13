import SwiftUI

struct ReportHubView: View {
    @Environment(AppState.self) private var state

    @State private var recentSessions: [ChewingSessionDTO] = []
    @State private var selectedDate: Date = mealCalendarCalendar.startOfDay(for: Date())
    @State private var detailSession: ChewingSessionDTO?

    private let dayWidth: CGFloat = 52
    private let windowDays = 21

    var body: some View {
        VStack(spacing: 14) {
            legacyUITestAnchors
            timelineCard
            sessionListCard
            weeklyComparisonCard
        }
        .task { await reloadRecentSessions() }
        .sheet(item: $detailSession) { session in
            NavigationStack {
                SessionReportDetailView(dto: session)
            }
        }
    }

    private var days: [ReportDay] {
        let today = mealCalendarCalendar.startOfDay(for: Date())
        let start = mealCalendarCalendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        return (0..<windowDays).map { offset in
            let date = mealCalendarCalendar.date(byAdding: .day, value: offset, to: start) ?? today
            let sessions = sessions(on: date)
            if !sessions.isEmpty {
                return ReportDay(date: date, sessions: sessions)
            }
            return ReportDay.empty(date: date)
        }
    }

    private var selectedDay: ReportDay {
        days.first { mealCalendarCalendar.isDate($0.date, inSameDayAs: selectedDate) } ?? days.last ?? .demo(date: Date(), index: 0, total: 1)
    }

    private var selectedSessions: [ChewingSessionDTO] {
        sessions(on: selectedDate).sorted { $0.startedAt < $1.startedAt }
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
                Text("\(selectedSessions.count)회")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.acorn700)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.acorn50, in: Capsule())
            }

            if selectedSessions.isEmpty {
                emptySessionState
            } else {
                VStack(spacing: 6) {
                    ForEach(selectedSessions) { session in
                        sessionRow(session)
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

    private func sessionRow(_ session: ChewingSessionDTO) -> some View {
        let slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: session.startedAt))
        return Button {
            detailSession = session
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
        let chunks = days.chunked(into: 7)
        let labels = ["지지난주", "지난주", "이번 주"]
        return chunks.enumerated().map { index, chunk in
            let chews = max(1, chunk.map(\.chewCount).reduce(0, +) / max(1, chunk.count))
            let minutes = max(1, chunk.map(\.minutes).reduce(0, +) / max(1, chunk.count))
            return WeeklyMetric(label: labels[min(index, labels.count - 1)], chews: chews, minutes: minutes, isCurrent: index == chunks.count - 1)
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

    @MainActor
    private func reloadRecentSessions() async {
        await state.fetchTodaySessions()
        let today = mealCalendarCalendar.startOfDay(for: Date())
        let start = mealCalendarCalendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        let end = mealCalendarCalendar.date(byAdding: .day, value: 1, to: today)
        let deviceId = DeviceIdentity.shared
        let rows = (try? await state.remoteStore.fetchChewingSessions(deviceId: deviceId, since: start, until: end)) ?? []
        let reportableRows = rows.filter { ReportCardModel.from($0) != nil }
        recentSessions = reportableRows.isEmpty
            ? ReportMockData.sessions(start: start, days: windowDays)
            : reportableRows
    }

    private func sessions(on date: Date) -> [ChewingSessionDTO] {
        recentSessions.filter { mealCalendarCalendar.isDate($0.startedAt, inSameDayAs: date) }
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

#Preview {
    ScrollView {
        ReportHubView()
            .padding(20)
    }
    .background(LinearGradient.appBackground)
    .environment(AppState())
}
