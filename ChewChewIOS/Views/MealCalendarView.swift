import SwiftUI

/// 캘린더/그리드/리스트 모두에서 같은 day boundary 동작 보장. 두 view가 각자 instance를
/// 생성했을 때 발생할 수 있는 미세한 차이를 차단. TrackingView 인라인 캘린더에서도
/// 같은 instance로 filter해야 dot/리스트 일관성이 깨지지 않아 internal 노출.
let mealCalendarCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "ko_KR")
    return c
}()

// MARK: - MealCalendarGrid (인라인 임베드 + 풀스크린 sheet 양쪽에서 재사용)

/// 월간 캘린더 그리드. 자체 fetch + month navigation 보유. 셀 탭 동작은 두 모드:
/// - `onTapDay: nil` → 셀이 `NavigationLink(value: date)`로 동작. 부모 NavigationStack의
///   `navigationDestination(for: Date.self)`에서 push (풀스크린 sheet 모드).
/// - `onTapDay: 클로저` → 셀을 Button으로 감싸 closure 호출 (인라인 모드, NavigationStack
///   바깥에서 사용).
struct MealCalendarGrid: View {
    @Environment(AppState.self) private var state

    @Binding var displayedMonth: Date
    @Binding var monthSessions: [ChewingSessionDTO]
    var onTapDay: ((Date) -> Void)? = nil

    private var calendar: Calendar { mealCalendarCalendar }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            weekdayLabels
                .padding(.horizontal, 12)
            calendarGrid
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .task { await reload() }
        .onChange(of: displayedMonth) { _, _ in
            Task { await reload() }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { goToMonth(-1) } label: {
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
            Button { goToMonth(+1) } label: {
                Image(systemName: "chevron.right")
                    .font(.appFont(.bold, size: 13))
                    .frame(width: 32, height: 32)
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
                    .font(.appFont(.bold, size: 10))
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
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(date: Date) -> some View {
        // LazyVGrid 안 NavigationLink / Button + buttonStyle.plain 조합이 일부 환경에서
        // 탭 자체가 안 먹는 회귀가 있어, 단순 `onTapGesture` + `contentShape(Rectangle())`
        // 패턴으로 통일. 풀스크린 sheet 모드도 같은 closure 경로를 쓰도록 onTapDay를
        // 호출자가 반드시 전달.
        let count = sessionsCount(on: date)
        return dayCellContent(date: date)
            .contentShape(Rectangle())
            .onTapGesture {
                guard count > 0 else { return }
                onTapDay?(date)
            }
    }

    private func dayCellContent(date: Date) -> some View {
        let count = sessionsCount(on: date)
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .heavy : .semibold))
                .foregroundStyle(weekdayColor(date: date))
                .monospacedDigit()
            Circle()
                .fill(count > 0 ? Color.acorn500 : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            isToday ? Color.acorn100.opacity(0.7) : Color.white.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func weekdayColor(date: Date) -> Color {
        switch calendar.component(.weekday, from: date) {
        case 1: Color.blush400
        case 7: Color.acorn600
        default: Color.ink800
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
    }

    private var monthDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = firstWeekday - 1
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

    @MainActor
    private func reload() async {
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

// MARK: - MealCalendarView (NavigationStack + 도구바 + grid)

struct MealCalendarView: View {
    @Environment(AppState.self) private var state

    @State private var displayedMonth: Date = .now
    @State private var monthSessions: [ChewingSessionDTO] = []
    @State private var showDeleteAllConfirm: Bool = false
    @State private var path = NavigationPath()

    private var calendar: Calendar { mealCalendarCalendar }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                MealCalendarGrid(
                    displayedMonth: $displayedMonth,
                    monthSessions: $monthSessions,
                    onTapDay: { date in
                        path.append(date)
                    }
                )
                .padding(20)
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("식사 캘린더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("모든 식사 기록 삭제", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.acorn700)
                    }
                }
            }
            .confirmationDialog(
                "모든 식사 기록을 삭제할까요?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("전체 삭제", role: .destructive) {
                    Task {
                        await state.deleteAllChewingSessions()
                        monthSessions = []
                    }
                }
                Button("취소", role: .cancel) { }
            } message: {
                Text("이 기기의 모든 식사 세션이 사라집니다.\n도토리/꾸미기 등 게임 상태는 보존돼요.\n되돌릴 수 없어요.")
            }
            .navigationDestination(for: Date.self) { date in
                DaySessionsView(
                    date: date,
                    monthSessions: $monthSessions,
                    onDelete: { session in
                        Task {
                            await state.deleteSession(session)
                            monthSessions.removeAll { $0.id == session.id }
                        }
                    },
                    onTapSession: { session in
                        path.append(session.id)
                    }
                )
            }
            .navigationDestination(for: UUID.self) { sessionId in
                if let session = monthSessions.first(where: { $0.id == sessionId }) {
                    SessionReportDetailView(dto: session)
                }
            }
        }
    }
}

// MARK: - Day sessions list

struct DaySessionsView: View {
    let date: Date
    /// 전체 월간 세션을 Binding으로 받아 view body 호출 시점마다 latest로 self-filter.
    /// closure 안에서 한 번 평가된 sessions를 stale capture하는 race 회피.
    @Binding var monthSessions: [ChewingSessionDTO]
    let onDelete: (ChewingSessionDTO) -> Void
    /// row 탭 시 호출. 호출자가 NavigationPath append 또는 다른 전환 처리.
    let onTapSession: (ChewingSessionDTO) -> Void

    private var sessions: [ChewingSessionDTO] {
        monthSessions.filter { mealCalendarCalendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                VStack {
                    Spacer()
                    Text("이 날엔 식사 기록이 없어요.")
                        .font(.appFont(.regular, size: 13))
                        .foregroundStyle(Color.ink600)
                    Spacer()
                }
            } else {
                List {
                    ForEach(sessions, id: \.id) { session in
                        sessionRow(session)
                            .contentShape(Rectangle())
                            .onTapGesture { onTapSession(session) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(session)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .navigationTitle(dateLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f.string(from: date)
    }

    private func sessionRow(_ session: ChewingSessionDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(session.startedAt))
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.ink800)
                    .monospacedDigit()
                Text(formatDuration(session.durationSec))
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if let chews = session.estimatedTotalChews {
                    Text("\(chews.koLocale)회 · 씹은 비율 \(String(format: "%.0f%%", (session.chewingFraction ?? 0) * 100))")
                        .font(.appFont(.bold, size: 13))
                        .foregroundStyle(Color.ink800)
                } else {
                    Text("분석 없음")
                        .font(.appFont(.regular, size: 13))
                        .foregroundStyle(Color.ink400)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs)초" }
        if secs == 0 { return "\(mins)분" }
        return "\(mins)분 \(secs)초"
    }
}

// MARK: - Single session detail (NavigationStack push)

/// 캘린더에서 push되는 단일 세션 리포트 화면.
struct SessionReportDetailView: View {
    let dto: ChewingSessionDTO

    /// PNG 렌더는 ImageRenderer 호출 비용이 작지 않아 view 진입 시 1회만 만든다.
    /// 빈 상태(분석 5필드 nil) 세션에선 nil로 남아 공유 버튼이 자동 hidden.
    @State private var sharePayload: ReportCardSharePayload?

    var body: some View {
        ScrollView {
            Group {
                if let model = ReportCardModel.from(dto) {
                    ReportCardView(model: model)
                } else {
                    EmptyReportCardView()
                }
            }
            .padding(20)
        }
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .navigationTitle("식사 리포트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let payload = sharePayload {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: payload, preview: SharePreview("식사 리포트")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(Color.acorn600)
                }
            }
        }
        .task {
            guard sharePayload == nil,
                  let model = ReportCardModel.from(dto),
                  let data = ReportCardRenderer.render(model)
            else { return }
            sharePayload = ReportCardSharePayload(imageData: data)
        }
    }
}
