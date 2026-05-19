import SwiftUI

/// 월간 식사 캘린더 — 세션 있는 날에 dot 표시. 셀 탭으로 그날 세션 시트를 여는
/// navigation은 commit ④에서 추가. 이번 commit은 그리드 + 월 fetch 까지.
struct MealCalendarView: View {
    @Environment(AppState.self) private var state

    @State private var displayedMonth: Date = .now
    @State private var monthSessions: [ChewingSessionDTO] = []
    @State private var isLoading: Bool = false

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ko_KR")
        return c
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                weekdayLabels
                    .padding(.horizontal, 16)
                calendarGrid
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("식사 캘린더")
            .navigationBarTitleDisplayMode(.inline)
            .task { await reload() }
            .onChange(of: displayedMonth) { _, _ in
                Task { await reload() }
            }
        }
    }

    // MARK: - Header / weekdays

    private var monthHeader: some View {
        HStack {
            Button { goToMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.ink800)
            Spacer()
            Button { goToMonth(+1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
        }
        .foregroundStyle(Color.acorn700)
    }

    private var weekdayLabels: some View {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { sym in
                Text(sym)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(weekdayLabelColor(sym))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekdayLabelColor(_ symbol: String) -> Color {
        switch symbol {
        case "일": Color.blush400
        case "토": Color.acorn600
        default:   Color.ink400
        }
    }

    // MARK: - Grid

    private var calendarGrid: some View {
        let days = monthDays
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 4
        ) {
            ForEach(0..<days.count, id: \.self) { i in
                if let date = days[i] {
                    dayCell(date: date)
                } else {
                    Color.clear.frame(height: 56)
                }
            }
        }
    }

    private func dayCell(date: Date) -> some View {
        let count = sessionsCount(on: date)
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 14, weight: isToday ? .heavy : .semibold))
                .foregroundStyle(weekdayColor(date: date))
                .monospacedDigit()
            Circle()
                .fill(count > 0 ? Color.acorn500 : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            isToday ? Color.acorn100.opacity(0.7) : Color.white.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func weekdayColor(date: Date) -> Color {
        switch calendar.component(.weekday, from: date) {
        case 1: Color.blush400   // 일
        case 7: Color.acorn600   // 토
        default: Color.ink800
        }
    }

    // MARK: - Month logic

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
    }

    /// 6주 × 7일 = 42칸 고정. 시작/끝의 다른 달은 nil로 채워 그리드 모양 유지.
    private var monthDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = firstWeekday - 1  // 일=1 → 0개, 월=2 → 1개 ...
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for d in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: d, to: monthInterval.start))
        }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    private func sessionsCount(on date: Date) -> Int {
        monthSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.count
    }

    private func goToMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
    }

    // MARK: - Fetch

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            monthSessions = []
            return
        }
        let deviceId = DeviceIdentity.shared
        let rows = (try? await state.remoteStore.fetchChewingSessions(
            deviceId: deviceId,
            since: monthInterval.start,
            until: monthInterval.end
        )) ?? []
        monthSessions = rows
    }
}
