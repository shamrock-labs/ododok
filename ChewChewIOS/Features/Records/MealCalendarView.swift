import SwiftUI

/// 캘린더/그리드/리스트 모두에서 같은 day boundary 동작 보장. 두 view가 각자 instance를
/// 생성했을 때 발생할 수 있는 미세한 차이를 차단. TrackingView 인라인 캘린더에서도
/// 같은 instance로 filter해야 dot/리스트 일관성이 깨지지 않아 internal 노출.
let mealCalendarCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ko_KR")
    return calendar
}()

// MARK: - MealCalendarGrid (인라인 임베드 + 풀스크린 sheet 양쪽에서 재사용)

/// 월간 캘린더 그리드. 자체 fetch + month navigation 보유. 셀 탭 동작은 두 모드:
/// - `onTapDay: nil` → 셀이 `NavigationLink(value: date)`로 동작. 부모 NavigationStack의
///   `navigationDestination(for: Date.self)`에서 push (풀스크린 sheet 모드).
/// - `onTapDay: 클로저` → 셀을 Button으로 감싸 closure 호출 (인라인 모드, NavigationStack
///   바깥에서 사용).
struct MealCalendarGrid: View {
    var store: RecordsStore
    var onTapSession: ((MealSessionRecord) -> Void)?

    private var calendar: Calendar { mealCalendarCalendar }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, AppSpacing.four)
                .padding(.vertical, AppSpacing.inner)
            weekdayLabels
                .padding(.horizontal, AppSpacing.three)
            calendarGrid
                .padding(.horizontal, AppSpacing.three)
                .padding(.top, AppSpacing.oneHalf)
                .padding(.bottom, AppSpacing.three)
            if let date = store.selectedDate {
                DayInlineSection(
                    date: date,
                    sessions: store.sessions(on: date),
                    onTapSession: onTapSession
                )
                .padding(.horizontal, AppSpacing.four)
                .padding(.bottom, AppSpacing.verticalLoose)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            .spring(response: AppMotion.springResponse, dampingFraction: AppMotion.springDampingFraction),
            value: store.selectedDate
        )
        .task {
            await store.loadInitial()
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { goToMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.appFont(.boldCallout))
                    .frame(width: Metrics.calendarButton, height: Metrics.calendarButton)
                    .background(Color.bgSurface.opacity(0.7), in: Circle())
            }
            .disabled(isAtOldestMonth)
            .opacity(isAtOldestMonth ? 0.35 : 1.0)
            Spacer()
            Text(monthTitle)
                .font(.appFont(.heavyBody))
                .foregroundStyle(Color.textDefault)
            Spacer()
            Button { goToMonth(+1) } label: {
                Image(systemName: "chevron.right")
                    .font(.appFont(.boldCallout))
                    .frame(width: Metrics.calendarButton, height: Metrics.calendarButton)
                    .background(Color.bgSurface.opacity(0.7), in: Circle())
            }
        }
        .foregroundStyle(Color.textAction)
    }

    private var weekdayLabels: some View {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return HStack(spacing: AppSpacing.one) {
            ForEach(symbols, id: \.self) { sym in
                Text(sym)
                    .font(.appFont(.boldMicro))
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
            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.one), count: 7),
            spacing: AppSpacing.one
        ) {
            ForEach(0..<days.count, id: \.self) { i in
                if let date = days[i] {
                    dayCell(date: date)
                } else {
                    Color.clear.frame(height: Metrics.calendarCellHeight)
                }
            }
        }
    }

    private func dayCell(date: Date) -> some View {
        // LazyVGrid 안 NavigationLink/Button 회귀를 피해 onTapGesture + contentShape 패턴.
        // 같은 날 다시 탭하면 접고, 다른 날 탭하면 그 날로 교체한다.
        let count = store.sessionsCount(on: date)
        return dayCellContent(date: date)
            .contentShape(Rectangle())
            .onTapGesture {
                guard count > 0 else { return }
                store.selectDate(date)
            }
    }

    private func dayCellContent(date: Date) -> some View {
        let count = store.sessionsCount(on: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = store.selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: date))")
                .font(.appFont(isToday || isSelected ? .heavyCaption : .semiboldCaption))
                .foregroundStyle(isSelected ? Color.textActionInverse : weekdayColor(date: date))
                .monospacedDigit()
            Circle()
                .fill(count > 0 ? (isSelected ? Color.textActionInverse : Color.dataChew) : Color.clear)
                .frame(width: Metrics.calendarDot, height: Metrics.calendarDot)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.calendarCellHeight)
        .background(
            cellBackground(isToday: isToday, isSelected: isSelected),
            in: RoundedRectangle(cornerRadius: AppRadius.inner)
        )
    }

    private func cellBackground(isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return Color.textActionStrong }
        if isToday { return Color.borderSelected.opacity(0.7) }
        return Color.bgSurface.opacity(0.45)
    }

    private func weekdayColor(date: Date) -> Color {
        switch calendar.component(.weekday, from: date) {
        case 1: Color.blush400
        case 7: Color.acorn600
        default: Color.textPrimary
        }
    }

    private var monthTitle: String {
        return KoDate.string(store.displayedMonth, "yyyy년 M월")
    }

    private var monthDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: store.displayedMonth)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = firstWeekday - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: store.displayedMonth)?.count ?? 0

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for dayOffset in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: dayOffset, to: monthInterval.start))
        }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    private func goToMonth(_ delta: Int) {
        Task {
            await store.moveMonth(delta: delta)
        }
    }

    /// 현재 표시 달이 가장 오래된 기록 달과 같은지. nil(미로딩)이면 false.
    private var isAtOldestMonth: Bool {
        guard let oldest = store.oldestSessionMonth else { return false }
        return calendar.isDate(store.displayedMonth, equalTo: oldest, toGranularity: .month)
    }
}

// MARK: - MealCalendarView (NavigationStack + 도구바 + grid)

struct MealCalendarView: View {
    @Environment(AppState.self) private var state

    @State private var showDeleteAllConfirm: Bool = false
    @State private var path = NavigationPath()

    private var records: RecordsStore { state.records }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                MealCalendarGrid(
                    store: records,
                    onTapSession: { session in
                        path.append(session.id)
                    }
                )
                .padding(AppSpacing.page)
                if let errorMessage = records.errorMessage {
                    Text(errorMessage)
                        .font(.appFont(.semiboldLabel))
                        .foregroundStyle(Color.blush500)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, AppSpacing.page)
                        .padding(.bottom, AppSpacing.page)
                }
            }
            .background(Color.bgPage.ignoresSafeArea())
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
                            .foregroundStyle(Color.textAction)
                    }
                }
            }
            .appDialog(
                isPresented: $showDeleteAllConfirm,
                title: "모든 식사 기록을 삭제할까요?",
                message: "이 기기의 모든 식사가 사라져요.\n도토리·꾸미기는 그대로예요.",
                primary: .init("전체 삭제", role: .destructive) {
                    Task {
                        await records.deleteAllSessions()
                    }
                },
                secondary: .init("취소", role: .cancel) { }
            )
            .navigationDestination(for: UUID.self) { sessionId in
                if let session = records.monthSessions.first(where: { $0.id == sessionId }) {
                    SessionReportDetailView(record: session)
                }
            }
        }
    }
}

// MARK: - Single session detail (NavigationStack push)

/// 캘린더에서 push되는 단일 세션 리포트 화면.
struct SessionReportDetailView: View {
    private let model: ReportCardModel?
    private let unavailableContent: MealReportUnavailableContent?

    /// PNG 렌더는 ImageRenderer 호출 비용이 작지 않아 view 진입 시 1회만 만든다.
    /// 빈 상태(분석 5필드 nil) 세션에선 nil로 남아 공유 버튼이 자동 hidden.
    @State private var sharePayload: ReportCardSharePayload?

    init(dto: ChewingSessionDTO) {
        self.model = ReportCardModel.from(dto)
        self.unavailableContent = model == nil ? .from(dto.mealReport) : nil
    }

    init(record: MealSessionRecord) {
        self.model = record.reportCard
        self.unavailableContent = nil
    }

    var body: some View {
        ScrollView {
            Group {
                if let model {
                    ReportCardView(model: model)
                } else {
                    EmptyReportCardView(
                        emoji: unavailableContent?.emoji ?? "🐿️",
                        title: unavailableContent?.title ?? "리포트를 표시할 수 없어요",
                        subtitle: unavailableContent?.message ?? "저장된 식사 리포트가 없어요."
                    )
                }
            }
            // 식사 리포트 카드를 더 넓게 — 좌우 여백을 줄인다.
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .background(Color.pageBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                AppSheetTitleText(title: "식사 리포트")
            }
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
                  let model,
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
    let sessions: [MealSessionRecord]
    let onTapSession: ((MealSessionRecord) -> Void)?

    var body: some View {
        if sessions.isEmpty {
            Text("이 날은 식사 기록이 없어요.")
                .font(.appFont(.semiboldLabel))
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

    private func slotBlock(slot: DayMealSlot, sessions: [MealSessionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                OpenIconView(icon: slot.openIcon, color: slot.iconColor, lineWidth: 2.1)
                    .frame(width: AppSpacing.five, height: AppSpacing.five)
                Text(slot.label)
                    .font(.appFont(.heavyBodyLarge))
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

    private func sessionRow(_ session: MealSessionRecord) -> some View {
        Button {
            onTapSession?(session)
        } label: {
            HStack(spacing: AppSpacing.three) {
                Text(formatTime12(session.startedAt))
                    .font(.appFont(.semiboldBody))
                    .foregroundStyle(Color.textDefault)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(formatDuration(session.durationSec))
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.appFont(.semiboldCaption))
                    .foregroundStyle(Color.textSubtle)
            }
            .padding(.horizontal, AppSpacing.cell)
            .padding(.vertical, AppSpacing.three)
            .background(Color.bgSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: AppSpacing.three))
        }
        .buttonStyle(.plain)
    }

    private var slotGroups: [(slot: DayMealSlot, sessions: [MealSessionRecord])] {
        let grouped = Dictionary(grouping: sessions) { session in
            DayMealSlot(hour: Calendar.current.component(.hour, from: session.startedAt))
        }
        return DayMealSlot.allCases.compactMap { slot in
            guard let group = grouped[slot], !group.isEmpty else { return nil }
            return (slot, group.sorted { $0.startedAt < $1.startedAt })
        }
    }

    private func formatTime12(_ date: Date) -> String {
        return KoDate.clockTime(date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs)초" }
        if secs == 0 { return "\(mins)분" }
        return "\(mins)분 \(secs)초"
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
    var analyticsValue: String {
        switch self {
        case .morning:   "morning"
        case .lunch:     "lunch"
        case .dinner:    "dinner"
        case .lateNight: "late_night"
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

private enum Metrics {
    static let calendarButton = AppSize.controlLarge
    static let calendarCellHeight = AppSize.controlXLarge
    static let calendarDot = AppSpacing.one
}
