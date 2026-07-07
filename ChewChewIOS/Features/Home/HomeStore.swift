import Foundation
import Observation

@Observable
@MainActor
final class HomeStore {
    private(set) var serverHome: HomeStateDTO?
    private(set) var points: Int
    private(set) var streak: Int
    private(set) var freezeInventory: Int
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let repository: HomeRepository
    private let localTodayRealChewCount: @MainActor () -> Int
    private let onHomeApplied: @MainActor (HomeStateDTO) -> Void
    private let onRemoteError: @MainActor (Error) -> Void
    private var loadGeneration: Int = 0

    init(
        repository: HomeRepository,
        initialHome: HomeStateDTO? = nil,
        initialPoints: Int = 0,
        initialStreak: Int = 0,
        initialFreezeInventory: Int = 0,
        localTodayRealChewCount: @escaping @MainActor () -> Int = { 0 },
        onHomeApplied: @escaping @MainActor (HomeStateDTO) -> Void = { _ in },
        onRemoteError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.repository = repository
        self.serverHome = initialHome
        self.points = initialHome?.points ?? initialPoints
        self.streak = initialHome?.streak ?? initialStreak
        self.freezeInventory = initialHome?.freezeInventory ?? initialFreezeInventory
        self.localTodayRealChewCount = localTodayRealChewCount
        self.onHomeApplied = onHomeApplied
        self.onRemoteError = onRemoteError
    }

    var currentStreak: Int {
        serverHome?.streak ?? streak
    }

    var todayRealChewCount: Int {
        if let serverHome, serverHome.dailyGoal > 0 { return serverHome.todayRealChewCount }
        return localTodayRealChewCount()
    }

    var todayProgress: Double {
        if let serverHome, serverHome.dailyGoal > 0 {
            return Self.clampedProgress(serverHome.todayProgress)
        }
        return Self.clampedProgress(Double(todayRealChewCount) / Double(Constants.dailyGoal))
    }

    var status: MoodStatus {
        MoodStatus.from(count: todayRealChewCount)
    }

    func refresh(shouldApply: (@MainActor () -> Bool)? = nil) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        do {
            let home = try await repository.fetchHome()
            guard generation == loadGeneration else { return }
            guard shouldApply?() ?? true else {
                isLoading = false
                return
            }
            apply(home)
            onHomeApplied(home)
            errorMessage = nil
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            onRemoteError(error)
            errorMessage = "홈 정보를 불러오지 못했어요."
            isLoading = false
        }
    }

    func applyExternal(_ home: HomeStateDTO) {
        loadGeneration += 1
        apply(home)
        errorMessage = nil
        isLoading = false
    }

    func reset() {
        loadGeneration += 1
        serverHome = nil
        points = 0
        streak = 0
        freezeInventory = 0
        errorMessage = nil
        isLoading = false
    }

    private func apply(_ home: HomeStateDTO) {
        serverHome = home
        points = home.points
        streak = home.streak
        freezeInventory = home.freezeInventory
    }

    private static func clampedProgress(_ progress: Double) -> Double {
        min(1.0, max(0.0, progress))
    }
}
