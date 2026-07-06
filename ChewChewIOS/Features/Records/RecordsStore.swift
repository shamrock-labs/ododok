import Foundation
import Observation

@Observable
@MainActor
final class RecordsStore {
    private(set) var monthSessions: [ChewingSessionDTO] = []
    private(set) var oldestSessionMonth: Date?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    var displayedMonth: Date
    var selectedDate: Date?

    private let repository: MealSessionRepository
    private let calendar: Calendar
    private var loadGeneration: Int = 0

    init(
        repository: MealSessionRepository,
        calendar: Calendar = mealCalendarCalendar,
        initialMonth: Date = .now
    ) {
        self.repository = repository
        self.calendar = calendar
        self.displayedMonth = calendar.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth
    }

    func loadInitial() async {
        await loadOldestSessionMonthIfNeeded()
        await loadMonth()
    }

    func loadMonth() async {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            monthSessions = []
            errorMessage = "기록을 불러오지 못했어요."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        do {
            let rows = try await repository.fetchSessions(
                since: monthInterval.start,
                until: monthInterval.end
            )
            guard generation == loadGeneration else { return }
            monthSessions = rows.filter { ReportCardModel.from($0) != nil }
            errorMessage = nil
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = "기록을 불러오지 못했어요."
            isLoading = false
        }
    }

    func moveMonth(delta: Int) async {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        let nextMonth = calendar.dateInterval(of: .month, for: next)?.start ?? next
        if delta < 0, let oldestSessionMonth, nextMonth < oldestSessionMonth { return }

        displayedMonth = nextMonth
        selectedDate = nil
        await loadMonth()
    }

    func selectDate(_ date: Date) {
        if let current = selectedDate, calendar.isDate(current, inSameDayAs: date) {
            selectedDate = nil
        } else {
            selectedDate = date
        }
    }

    func deleteSession(_ session: ChewingSessionDTO) async {
        loadGeneration += 1
        do {
            try await repository.deleteSession(id: session.id)
            monthSessions.removeAll { $0.id == session.id }
            if let selectedDate, sessions(on: selectedDate).isEmpty {
                self.selectedDate = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = "기록을 삭제하지 못했어요."
        }
    }

    func deleteAllSessions() async {
        loadGeneration += 1
        do {
            try await repository.deleteAllSessions()
            monthSessions = []
            selectedDate = nil
            oldestSessionMonth = nil
            errorMessage = nil
        } catch {
            errorMessage = "기록을 삭제하지 못했어요."
        }
    }

    func sessions(on date: Date) -> [ChewingSessionDTO] {
        monthSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    func sessionsCount(on date: Date) -> Int {
        sessions(on: date).count
    }

    private func loadOldestSessionMonthIfNeeded() async {
        guard oldestSessionMonth == nil else { return }
        do {
            let rows = try await repository.fetchSessions(since: .distantPast, until: nil)
            guard let earliest = rows.map(\.startedAt).min() else { return }
            oldestSessionMonth = calendar.dateInterval(of: .month, for: earliest)?.start
        } catch {
            errorMessage = "기록을 불러오지 못했어요."
        }
    }
}
