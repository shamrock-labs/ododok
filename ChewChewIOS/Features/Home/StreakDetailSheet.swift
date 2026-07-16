import SwiftUI

enum StreakDayPresentationState: Equatable {
    case missing
    case attended
    case frozen
    case unknownLoading
    case unknownUnavailable
}

struct StreakDayPresentation: Equatable, Identifiable {
    let dateID: String
    let weekday: String
    let dayOfMonth: Int
    let state: StreakDayPresentationState
    let isToday: Bool

    var id: String { dateID }
    var accessibilityIdentifier: String { "StreakDay-\(dateID)" }

    var accessibilityLabel: String {
        let status = switch state {
        case .missing: "기록 없음"
        case .attended: "출석"
        case .frozen: "프리즈 방어"
        case .unknownLoading: "스트릭 정보 확인 중"
        case .unknownUnavailable: "스트릭 기록 정보 없음"
        }
        return "\(dayOfMonth)일, \(status)\(isToday ? ", 오늘" : "")"
    }
}

struct StreakDetailPresentation: Equatable {
    let current: Int
    let longestText: String
    let startedOnText: String
    let freezeInventory: Int
    let days: [StreakDayPresentation]
    let showsRetry: Bool

    static func make(
        detail: StreakDetailDTO?,
        cachedCurrent: Int = 0,
        cachedFreezeInventory: Int = 0,
        isLoading: Bool = false,
        hasFailed: Bool = false,
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

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = Locale(identifier: "ko_KR")
        weekdayFormatter.timeZone = calendar.timeZone
        weekdayFormatter.dateFormat = "EEEEE"

        let startFormatter = DateFormatter()
        startFormatter.calendar = calendar
        startFormatter.locale = Locale(identifier: "ko_KR")
        startFormatter.timeZone = calendar.timeZone
        startFormatter.dateFormat = "M월 d일"

        let statesByDay = Dictionary(uniqueKeysWithValues: (detail?.days ?? []).map { ($0.date, $0.state) })
        let today = detail.flatMap { dayFormatter.date(from: $0.asOf) }
            ?? calendar.startOfDay(for: now)
        let days = (-13...0).compactMap { offset -> StreakDayPresentation? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let dateID = dayFormatter.string(from: date)
            let state: StreakDayPresentationState = if detail == nil {
                isLoading ? .unknownLoading : .unknownUnavailable
            } else {
                switch statesByDay[dateID] {
                case .attended: .attended
                case .frozen: .frozen
                case nil: .missing
                }
            }
            return StreakDayPresentation(
                dateID: dateID,
                weekday: weekdayFormatter.string(from: date),
                dayOfMonth: calendar.component(.day, from: date),
                state: state,
                isToday: offset == 0
            )
        }

        let startedOnText: String
        if let startedOn = detail?.startedOn, let date = dayFormatter.date(from: startedOn) {
            startedOnText = "\(startFormatter.string(from: date))부터 이어가는 중"
        } else if detail == nil, isLoading {
            startedOnText = "스트릭 정보를 확인하는 중"
        } else {
            startedOnText = "시작일 정보 없음"
        }

        return Self(
            current: detail?.current ?? cachedCurrent,
            longestText: detail.map { "최장 스트릭 \($0.longest)일" } ?? "최장 스트릭 —",
            startedOnText: startedOnText,
            freezeInventory: detail?.freezeInventory ?? cachedFreezeInventory,
            days: days,
            showsRetry: detail == nil && hasFailed
        )
    }
}

struct StreakDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var home: HomeStore { state.home }

    private var presentation: StreakDetailPresentation {
        .make(
            detail: home.streakDetail,
            cachedCurrent: home.currentStreak,
            cachedFreezeInventory: home.freezeInventory,
            isLoading: isDetailLoading,
            hasFailed: home.streakDetailLoadState == .failed
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
            header

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.five) {
                    Text(presentation.startedOnText)
                        .font(.appFont(.semiboldBody))
                        .foregroundStyle(Color.textMuted)

                    summarySection
                    recentDays
                    if !presentation.showsRetry {
                        legend
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
        .accessibilityIdentifier("StreakDetailSheet")
        .task {
            await home.fetchStreakDetail()
        }
    }

    private var header: some View {
        AppSheetHeader(title: "나의 스트릭") {
            AppSheetTextActionButton(title: "닫기") { dismiss() }
                .accessibilityIdentifier("StreakDetailCloseButton")
        }
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
                Text(presentation.longestText)
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }

            Spacer(minLength: AppSpacing.one)

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
        }
        .padding(.vertical, AppSpacing.two)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("StreakSummaryCard")
    }

    private var recentDays: some View {
        VStack(alignment: .leading, spacing: AppSpacing.three) {
            HStack {
                Text("최근 기록")
                    .font(.appFont(.heavyHeadline))
                    .foregroundStyle(Color.textDefault)
                Spacer()
                Text("14일")
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textMuted)
            }

            if presentation.showsRetry {
                HStack(spacing: AppSpacing.three) {
                    Text("기록을 불러오지 못했어요")
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textMuted)

                    Spacer(minLength: AppSpacing.two)

                    Button("다시 시도") {
                        Task { await home.fetchStreakDetail() }
                    }
                    .buttonStyle(.plain)
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(Color.textAction)
                    .padding(.horizontal, AppSpacing.three)
                    .frame(minHeight: AppSize.controlXLarge)
                    .background(Color.bgSunken, in: Capsule())
                    .accessibilityLabel("스트릭 기록 다시 불러오기")
                    .accessibilityIdentifier("StreakDetailRetryButton")
                }
                .frame(minHeight: Metrics.retryHeight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("StreakDetailRetryState")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.two), count: 7), spacing: AppSpacing.three) {
                    ForEach(presentation.days) { day in
                        StreakDayCell(day: day)
                    }
                }
                .accessibilityIdentifier("StreakRecentDaysGrid")
            }
        }
    }

    private var legend: some View {
        HStack(spacing: AppSpacing.five) {
            StreakLegendItem(kind: .today, label: "오늘 접속")
            StreakLegendItem(kind: .frozen, label: "프리즈 방어")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("StreakLegend")
    }
}

private struct StreakDayCell: View {
    let day: StreakDayPresentation

    var body: some View {
        VStack(spacing: AppSpacing.oneHalf) {
            Text(day.isToday ? "오늘" : day.weekday)
                .font(.appFont(.boldCaption))
                .foregroundStyle(day.isToday ? Color.textAction : Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ZStack {
                Circle()
                    .fill(surface)
                Circle()
                    .stroke(border, lineWidth: borderWidth)

                switch day.state {
                case .frozen:
                    Image(systemName: "shield.fill")
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.freezeForeground)
                case .attended, .missing, .unknownLoading, .unknownUnavailable:
                    Text("\(day.dayOfMonth)")
                        .font(.appFont(.heavyCallout))
                        .foregroundStyle(foreground)
                        .monospacedDigit()
                }
            }
            .frame(width: Metrics.dayCircle, height: Metrics.dayCircle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityIdentifier(day.accessibilityIdentifier)
    }

    private var surface: Color {
        switch day.state {
        case .missing, .unknownLoading, .unknownUnavailable: Color.bgSunken
        case .attended: Color.tintPrimary
        case .frozen: Color.freezeSurface
        }
    }

    private var foreground: Color {
        day.state == .attended ? Color.textActionInverse : Color.textSubtle
    }

    private var border: Color {
        if day.isToday, day.state == .attended { return Color.butter400 }
        if day.state == .frozen { return Color.freezeBorder }
        return day.state == .attended ? Color.tintPrimary : Color.borderDefault
    }

    private var borderWidth: CGFloat {
        day.isToday && day.state == .attended ? Metrics.todayBorder : AppSize.border
    }
}

private struct StreakLegendItem: View {
    enum Kind { case today, frozen }

    let kind: Kind
    let label: String

    var body: some View {
        HStack(spacing: AppSpacing.oneHalf) {
            ZStack {
                Circle().fill(kind == .today ? Color.tintPrimary : Color.freezeSurface)
                Circle().stroke(kind == .today ? Color.butter400 : Color.freezeBorder, lineWidth: AppSize.border)
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
    static let dayCircle: CGFloat = 44
    static let todayBorder: CGFloat = 4
    static let retryHeight: CGFloat = 88
}
