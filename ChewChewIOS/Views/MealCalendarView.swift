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
    var onTapSession: ((ChewingSessionDTO) -> Void)? = nil

    /// 가장 오래된 세션이 있는 달 — 좌측 chevron 비활성 기준. 첫 로딩 시 1회 계산.
    @State private var oldestSessionMonth: Date?
    /// 인라인으로 펼친 날짜 — 한 번 더 탭하면 접힌다.
    @State private var selectedDate: Date?

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
            if let date = selectedDate {
                DayInlineSection(
                    date: date,
                    sessions: sessions(on: date),
                    onTapSession: onTapSession
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedDate)
        .task {
            await loadOldestSessionMonthIfNeeded()
            await reload()
        }
        .onChange(of: displayedMonth) { _, _ in
            Task {
                selectedDate = nil
                await reload()
            }
        }
    }

    private func sessions(on date: Date) -> [ChewingSessionDTO] {
        monthSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    private var monthHeader: some View {
        HStack {
            Button { goToMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.appFont(.bold, size: 13))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .disabled(isAtOldestMonth)
            .opacity(isAtOldestMonth ? 0.35 : 1.0)
            Spacer()
            Text(monthTitle)
                .font(.appFont(.heavy, size: 15))
                .foregroundStyle(Color.textPrimary)
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
                    .font(.appFont(.bold, size: 11))
                    .foregroundStyle(weekdayLabelColor(sym))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekdayLabelColor(_ symbol: String) -> Color {
        switch symbol {
        case "일": Color.blush400
        case "토": Color.acorn600
        default:   Color.textTertiary
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
        // LazyVGrid 안 NavigationLink/Button 회귀를 피해 onTapGesture + contentShape 패턴.
        // 같은 날 다시 탭하면 접고, 다른 날 탭하면 그 날로 교체한다.
        let count = sessionsCount(on: date)
        return dayCellContent(date: date)
            .contentShape(Rectangle())
            .onTapGesture {
                guard count > 0 else { return }
                if let current = selectedDate, calendar.isDate(current, inSameDayAs: date) {
                    selectedDate = nil
                } else {
                    selectedDate = date
                }
            }
    }

    private func dayCellContent(date: Date) -> some View {
        let count = sessionsCount(on: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday || isSelected ? .heavy : .semibold))
                .foregroundStyle(isSelected ? Color.white : weekdayColor(date: date))
                .monospacedDigit()
            Circle()
                .fill(count > 0 ? (isSelected ? Color.white : Color.acorn500) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            cellBackground(isToday: isToday, isSelected: isSelected),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func cellBackground(isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return Color.acorn600 }
        if isToday    { return Color.acorn100.opacity(0.7) }
        return Color.white.opacity(0.45)
    }

    private func weekdayColor(date: Date) -> Color {
        switch calendar.component(.weekday, from: date) {
        case 1: Color.blush400
        case 7: Color.acorn600
        default: Color.textPrimary
        }
    }

    private var monthTitle: String {
        return KoDate.string(displayedMonth, "yyyy년 M월")
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
        if delta < 0, let oldest = oldestSessionMonth, next < oldest { return }
        displayedMonth = next
    }

    /// 현재 표시 달이 가장 오래된 기록 달과 같은지. nil(미로딩)이면 false.
    private var isAtOldestMonth: Bool {
        guard let oldest = oldestSessionMonth else { return false }
        return calendar.isDate(displayedMonth, equalTo: oldest, toGranularity: .month)
    }

    /// 가장 오래된 세션이 있는 달을 1회 fetch해 캐시. 빠른 응답을 위해 month 단위로만 truncate.
    private func loadOldestSessionMonthIfNeeded() async {
        guard oldestSessionMonth == nil else { return }
        let deviceId = DeviceIdentity.shared
        guard let rows = try? await state.remoteStore.fetchChewingSessions(
            deviceId: deviceId,
            since: .distantPast
        ) else { return }
        guard let earliest = rows.map(\.startedAt).min() else { return }
        oldestSessionMonth = calendar.dateInterval(of: .month, for: earliest)?.start
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
        monthSessions = rows.filter { ReportCardModel.from($0) != nil }
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
                    onTapSession: { session in
                        path.append(session.id)
                    }
                )
                .padding(20)
            }
            .background(Color.pageBackground.ignoresSafeArea())
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
            .appDialog(
                isPresented: $showDeleteAllConfirm,
                title: "모든 식사 기록을 삭제할까요?",
                message: "이 기기의 모든 식사가 사라져요.\n도토리·꾸미기는 그대로예요.",
                primary: .init("전체 삭제", role: .destructive) {
                    Task {
                        await state.deleteAllChewingSessions()
                        monthSessions = []
                    }
                },
                secondary: .init("취소", role: .cancel) { }
            )
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
                    Text("이 날은 식사 기록이 없어요.")
                        .font(.appFont(.semibold, size: 15))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(sessions, id: \.id) { session in
                        sessionRow(session)
                            .contentShape(Rectangle())
                            .onTapGesture { onTapSession(session) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.visible)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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
        .background(Color.pageBackground.ignoresSafeArea())
        .navigationTitle(dateLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dateLabel: String {
        return KoDate.string(date, "M월 d일 EEEE")
    }

    private func sessionRow(_ session: ChewingSessionDTO) -> some View {
        HStack(spacing: 12) {
            Text(formatTime(session.startedAt))
                .font(.appFont(.heavy, size: 17))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(formatDuration(session.durationSec))
                .font(.appFont(.semibold, size: 14))
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private func formatTime(_ d: Date) -> String {
        return KoDate.string(d, "HH:mm")
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
        .background(Color.pageBackground.ignoresSafeArea())
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


// MARK: - Day inline expansion (calendar 밑에 열리는 세션 리스트)

/// 시간대별로 묶어 보여주는 일간 식사 리스트. 캘린더 그리드 바로 아래에서 펼침/접힘.
private struct DayInlineSection: View {
    let date: Date
    let sessions: [ChewingSessionDTO]
    let onTapSession: ((ChewingSessionDTO) -> Void)?

    var body: some View {
        if sessions.isEmpty {
            Text("이 날은 식사 기록이 없어요.")
                .font(.appFont(.semibold, size: 14))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(slotGroups, id: \.slot) { group in
                    slotBlock(slot: group.slot, sessions: group.sessions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func slotBlock(slot: DayMealSlot, sessions: [ChewingSessionDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                OpenIconView(icon: slot.openIcon, color: slot.iconColor, lineWidth: 2.1)
                    .frame(width: 20, height: 20)
                Text(slot.label)
                    .font(.appFont(.heavy, size: 16))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                ForEach(sessions, id: \.id) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: ChewingSessionDTO) -> some View {
        Button {
            onTapSession?(session)
        } label: {
            HStack(spacing: 12) {
                Text(formatTime12(session.startedAt))
                    .font(.appFont(.semibold, size: 15))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(formatDuration(session.durationSec))
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.appFont(.semibold, size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.acorn50.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var slotGroups: [(slot: DayMealSlot, sessions: [ChewingSessionDTO])] {
        let grouped = Dictionary(grouping: sessions) { dto in
            DayMealSlot(hour: Calendar.current.component(.hour, from: dto.startedAt))
        }
        return DayMealSlot.allCases.compactMap { slot in
            guard let group = grouped[slot], !group.isEmpty else { return nil }
            return (slot, group.sorted { $0.startedAt < $1.startedAt })
        }
    }

    private func formatTime12(_ d: Date) -> String {
        return KoDate.string(d, "a h:mm")
    }

    private func formatDuration(_ secs: Double) -> String {
        let total = Int(secs.rounded())
        let m = total / 60
        let s = total % 60
        if m == 0 { return "\(s)초" }
        if s == 0 { return "\(m)분" }
        return "\(m)분 \(s)초"
    }
}

/// 끼니 슬롯 분류. 시각(시간)으로 매핑. UI 라벨/아이콘 보관.
enum DayMealSlot: CaseIterable, Hashable {
    case morning, lunch, dinner, lateNight

    var label: String {
        switch self {
        case .morning:   "아침"
        case .lunch:     "점심"
        case .dinner:    "저녁"
        case .lateNight: "야식"
        }
    }
    var openIcon: OpenIcon {
        switch self {
        case .morning:   .sunrise
        case .lunch:     .utensils
        case .dinner:    .moonStar
        case .lateNight: .moonStar
        }
    }
    var iconColor: Color {
        switch self {
        case .morning:   .butter600
        case .lunch:     .sage600
        case .dinner:    .blush500
        case .lateNight: .acorn700
        }
    }
    init(hour: Int) {
        switch hour {
        case 6...10:  self = .morning
        case 11...14: self = .lunch
        case 15...21: self = .dinner
        default:      self = .lateNight
        }
    }
}
