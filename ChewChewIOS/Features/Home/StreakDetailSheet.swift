import SwiftUI

enum StreakDetailSheetPolicy {
    static let defaultDetentFraction: CGFloat = 0.72
}

struct FreezeAwardGuidePresentation: Equatable {
    let title: String
    let message: String
    let supportingText: String

    static let `default` = Self(
        title: "프리즈는 이렇게 받아요",
        message: "스트릭 7일, 30일, 100일을 처음 달성할 때마다 프리즈 1개를 받아요.",
        supportingText: "프리즈는 최대 3개까지 보유할 수 있어요."
    )
}

enum StreakDayPresentationState: Equatable {
    case missing
    case attended
    case frozen
    case upcoming
    case unknownLoading
    case unknownUnavailable
}

enum StreakCalendarRingKind: Equatable {
    case neutral
    case attended
    case frozen
}

struct StreakDayPresentation: Equatable, Identifiable {
    let dateID: String
    let dayOfMonth: Int
    let state: StreakDayPresentationState
    let isToday: Bool

    var id: String { dateID }
    var accessibilityIdentifier: String { "StreakDay-\(dateID)" }

    var ringKind: StreakCalendarRingKind {
        switch state {
        case .attended:
            .attended
        case .frozen:
            .frozen
        case .missing, .upcoming, .unknownLoading, .unknownUnavailable:
            .neutral
        }
    }

    var accessibilityLabel: String {
        let status = switch state {
        case .missing: "기록 없음"
        case .attended: "출석"
        case .frozen: "프리즈 방어"
        case .upcoming: "아직 오지 않은 날"
        case .unknownLoading: "스트릭 정보 확인 중"
        case .unknownUnavailable: "스트릭 기록 정보 없음"
        }
        return "\(dayOfMonth)일, \(status)\(isToday ? ", 오늘" : "")"
    }
}

struct StreakDetailPresentation: Equatable {
    let current: Int
    let startedOnText: String
    let freezeInventory: Int
    let monthTitle: String
    let days: [StreakDayPresentation?]
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let historyStartText: String?
    let showsCalendar: Bool

    static func make(
        detail: StreakDetailDTO?,
        cachedCurrent: Int = 0,
        cachedFreezeInventory: Int = 0,
        selectedMonth: String? = nil,
        isLoading: Bool = false,
        now: Date = Date()
    ) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        guard let serviceTimeZone = TimeZone(identifier: "Asia/Seoul") else {
            preconditionFailure("Asia/Seoul time zone must be available")
        }
        calendar.timeZone = serviceTimeZone

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = Locale(identifier: "ko_KR")
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = "yyyy년 M월"

        let startFormatter = DateFormatter()
        startFormatter.calendar = calendar
        startFormatter.locale = Locale(identifier: "ko_KR")
        startFormatter.timeZone = calendar.timeZone
        startFormatter.dateFormat = "M월 d일"

        let fallbackToday = calendar.startOfDay(for: now)
        let asOf = detail.flatMap { dayFormatter.date(from: $0.asOf) } ?? fallbackToday
        let requestedMonth = detail.flatMap { dayFormatter.date(from: "\($0.resolvedMonth)-01") }
            ?? selectedMonth.flatMap { dayFormatter.date(from: "\($0)-01") }
            ?? calendar.dateInterval(of: .month, for: fallbackToday)?.start
            ?? fallbackToday
        let monthStart = calendar.dateInterval(of: .month, for: requestedMonth)?.start ?? requestedMonth
        let statesByDay = Dictionary(uniqueKeysWithValues: (detail?.days ?? []).map { ($0.date, $0.state) })

        var days: [StreakDayPresentation?] = Array(
            repeating: nil,
            count: calendar.component(.weekday, from: monthStart) - 1
        )
        let numberOfDays = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        for offset in 0..<numberOfDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let dateID = dayFormatter.string(from: date)
            let state: StreakDayPresentationState
            if detail == nil {
                state = isLoading ? .unknownLoading : .unknownUnavailable
            } else if date > asOf {
                state = .upcoming
            } else {
                state = switch statesByDay[dateID] {
                case .attended: .attended
                case .frozen: .frozen
                case nil: .missing
                }
            }
            days.append(
                StreakDayPresentation(
                    dateID: dateID,
                    dayOfMonth: calendar.component(.day, from: date),
                    state: state,
                    isToday: calendar.isDate(date, inSameDayAs: asOf)
                )
            )
        }
        while days.count < 42 { days.append(nil) }

        let displayedCurrent = detail?.current ?? cachedCurrent
        let startedOnText: String
        if let startedOn = detail?.startedOn, let date = dayFormatter.date(from: startedOn) {
            startedOnText = "\(startFormatter.string(from: date))부터 이어가는 중"
        } else if detail == nil, isLoading {
            startedOnText = "스트릭 정보를 확인하는 중"
        } else if displayedCurrent == 0 {
            startedOnText = ""
        } else {
            startedOnText = "시작일 정보 없음"
        }

        let oldestMonth = detail?.oldestRecordedOn.map { String($0.prefix(7)) }
        let currentServerMonth = detail.map { String($0.asOf.prefix(7)) }
        let resolvedSelectedMonth = detail?.resolvedMonth ?? selectedMonth
        let historyStartText = detail?.oldestRecordedOn.flatMap { value -> String? in
            guard let date = dayFormatter.date(from: value) else { return nil }
            return "스트릭 기록은 \(startFormatter.string(from: date))부터 확인할 수 있어요"
        }

        let canMovePrevious: Bool
        if let oldestMonth {
            canMovePrevious = resolvedSelectedMonth.map { $0 > oldestMonth } ?? false
        } else {
            canMovePrevious = true
        }
        let canMoveNext: Bool
        let fallbackCurrentMonth = dayFormatter.string(from: fallbackToday).prefix(7)
        if let resolvedSelectedMonth {
            canMoveNext = resolvedSelectedMonth < (currentServerMonth ?? String(fallbackCurrentMonth))
        } else {
            canMoveNext = false
        }

        return Self(
            current: displayedCurrent,
            startedOnText: startedOnText,
            freezeInventory: detail?.freezeInventory ?? cachedFreezeInventory,
            monthTitle: monthFormatter.string(from: monthStart),
            days: days,
            canMovePrevious: canMovePrevious,
            canMoveNext: canMoveNext,
            historyStartText: historyStartText,
            showsCalendar: true
        )
    }
}

struct StreakDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showsFreezeAwardGuide = false

    private var home: HomeStore { state.home }

    private var presentation: StreakDetailPresentation {
        .make(
            detail: home.streakDetail,
            cachedCurrent: home.currentStreak,
            cachedFreezeInventory: home.freezeInventory,
            selectedMonth: home.streakSelectedMonth,
            isLoading: isDetailLoading
        )
    }

    private var isDetailLoading: Bool {
        switch home.streakDetailLoadState {
        case .idle, .loading: true
        case .loaded, .failed: false
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.five) {
            AppSheetHeader(title: "스트릭") {
                AppSheetTextActionButton(title: "닫기") { dismiss() }
                    .accessibilityIdentifier("StreakDetailCloseButton")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summarySection
                    sectionDivider
                        .padding(.top, AppSpacing.one)
                        .padding(.bottom, AppSpacing.three)
                    calendarSection
                    legend
                        .padding(.top, AppSpacing.two)
                    if let historyStartText = presentation.historyStartText {
                        Text(historyStartText)
                            .font(.appFont(.semiboldCaption))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, AppSpacing.two)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, AppSpacing.sheetContent)
        .padding(.top, AppSpacing.four)
        .padding(.bottom, AppSpacing.cardOuterBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgPage.ignoresSafeArea())
        .task { await home.fetchStreakDetail() }
        .appDialog(
            isPresented: $showsFreezeAwardGuide,
            title: FreezeAwardGuidePresentation.default.title,
            message: FreezeAwardGuidePresentation.default.message,
            supportingText: FreezeAwardGuidePresentation.default.supportingText,
            primary: .init("확인") {}
        )
    }

    private var summarySection: some View {
        HStack(spacing: AppSpacing.four) {
            AppMetricIconBadge(
                icon: .flame,
                foreground: .statusDanger,
                background: .statusDangerMuted
            )

            VStack(alignment: .leading, spacing: AppSpacing.one) {
                Text("\(presentation.current)일째")
                    .font(.appFont(.heavyTitleXLarge))
                    .foregroundStyle(Color.textDefault)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(presentation.startedOnText)
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textMuted)
            }

            Spacer(minLength: AppSpacing.one)

            VStack(spacing: AppSpacing.half) {
                HStack(spacing: AppSpacing.one) {
                    Image(systemName: "shield.fill")
                        .foregroundStyle(Color.freezeForeground)
                    Text("\(presentation.freezeInventory)개")
                        .font(.appFont(.heavyHeadline))
                        .foregroundStyle(Color.freezeForeground)
                        .monospacedDigit()
                }
                .padding(.horizontal, AppSpacing.three)
                .frame(minHeight: AppSize.controlXLarge)
                .background(Color.bgSurface, in: Capsule())
                .accessibilityLabel("보유 프리즈 \(presentation.freezeInventory)개")

                Button {
                    showsFreezeAwardGuide = true
                } label: {
                    HStack(spacing: AppSpacing.one) {
                        Image(systemName: "info.circle")
                        Text("지급 기준")
                    }
                    .font(.appFont(.boldMicro))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, AppSpacing.one)
                    .frame(
                        minWidth: AppSize.dialogActionHeight,
                        minHeight: AppSize.controlMedium,
                        alignment: .top
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("프리즈 지급 기준 보기")
                .accessibilityIdentifier("FreezeAwardGuideButton")
            }
            .alignmentGuide(VerticalAlignment.center) { dimensions in
                dimensions[.top] + (AppSize.controlXLarge / 2)
            }
        }
        .padding(.top, AppSpacing.two)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("StreakSummaryCard")
    }

    private var sectionDivider: some View {
        Color.borderDefault
            .frame(maxWidth: .infinity)
            .frame(height: AppSize.hairline)
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthHeader
                .padding(.horizontal, AppSpacing.four)
                .padding(.vertical, AppSpacing.inner)
            if presentation.showsCalendar {
                weekdayLabels
                    .padding(.horizontal, AppSpacing.three)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.one), count: 7),
                    spacing: AppSpacing.one
                ) {
                    ForEach(presentation.days.indices, id: \.self) { index in
                        if let day = presentation.days[index] {
                            StreakDayCell(day: day)
                        } else {
                            Color.clear.frame(height: Metrics.calendarCellHeight)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.three)
                .padding(.top, AppSpacing.oneHalf)
                .padding(.bottom, AppSpacing.three)
                .accessibilityIdentifier("StreakMonthGrid")
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            monthButton(
                systemName: "chevron.left",
                accessibilityLabel: "이전 달",
                enabled: presentation.canMovePrevious
            ) {
                await home.moveStreakMonth(delta: -1)
            }
            Spacer()
            Text(presentation.monthTitle)
                .font(.appFont(.heavyBody))
                .foregroundStyle(Color.textDefault)
            Spacer()
            monthButton(
                systemName: "chevron.right",
                accessibilityLabel: "다음 달",
                enabled: presentation.canMoveNext
            ) {
                await home.moveStreakMonth(delta: 1)
            }
        }
    }

    private func monthButton(
        systemName: String,
        accessibilityLabel: String,
        enabled: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: systemName)
                .font(.appFont(.boldCallout))
                .frame(width: Metrics.calendarButton, height: Metrics.calendarButton)
                .background(Color.bgSurface.opacity(0.7), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textAction)
        .accessibilityLabel(accessibilityLabel)
        .disabled(!enabled || isDetailLoading)
        .opacity(enabled ? 1 : 0.35)
    }

    private var weekdayLabels: some View {
        HStack(spacing: AppSpacing.one) {
            ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { symbol in
                Text(symbol)
                    .font(.appFont(.boldMicro))
                    .foregroundStyle(symbol == "일" ? Color.blush400 : symbol == "토" ? Color.acorn600 : Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: AppSpacing.five) {
            StreakLegendItem(kind: .attended, label: "접속")
            StreakLegendItem(kind: .frozen, label: "프리즈 방어")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("StreakLegend")
    }
}

private struct StreakDayCell: View {
    let day: StreakDayPresentation

    var body: some View {
        ZStack {
            CalendarStatusRing(
                completedSegments: day.ringKind == .neutral ? 0 : 1,
                totalSegments: 1,
                accent: ringAccent,
                fill: day.isToday ? Color.borderSelected.opacity(0.7) : Color.clear,
                style: .streak
            )
            Text("\(day.dayOfMonth)")
                .font(.appFont(day.isToday ? .heavyCaption : .semiboldCaption))
                .foregroundStyle(dayNumberColor)
                .monospacedDigit()
        }
        .frame(width: Metrics.dateRing, height: Metrics.dateRing)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.calendarCellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityIdentifier(day.accessibilityIdentifier)
    }

    private var ringAccent: Color {
        switch day.ringKind {
        case .neutral, .attended:
            Color.acorn500
        case .frozen:
            Color.freezeForeground
        }
    }

    private var dayNumberColor: Color {
        switch day.state {
        case .upcoming, .unknownLoading, .unknownUnavailable:
            Color.textTertiary
        case .missing, .attended, .frozen:
            Color.textPrimary
        }
    }
}

private struct StreakLegendItem: View {
    enum Kind { case attended, frozen }

    let kind: Kind
    let label: String

    var body: some View {
        HStack(spacing: AppSpacing.oneHalf) {
            ZStack {
                CalendarStatusRing(
                    completedSegments: 1,
                    totalSegments: 1,
                    accent: kind == .attended ? Color.acorn500 : Color.freezeForeground,
                    style: .streak
                )
                if kind == .frozen {
                    Image(systemName: "shield.fill")
                        .font(.appFont(.semiboldMicro))
                        .foregroundStyle(Color.freezeForeground)
                }
            }
            .frame(width: AppSize.controlTiny, height: AppSize.controlTiny)
            Text(label)
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(Color.textMuted)
        }
    }
}

private enum Metrics {
    static let calendarButton = AppSize.controlLarge
    static let calendarCellHeight = AppSize.controlXLarge
    static let dateRing = AppSize.controlXLarge
}
