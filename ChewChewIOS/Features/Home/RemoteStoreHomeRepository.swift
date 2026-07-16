import Foundation

struct RemoteStoreHomeRepository: HomeRepository {
    private let remoteStore: RemoteStore
    private let debugProfileIsActive: () -> Bool

    init(
        remoteStore: RemoteStore,
        debugProfileIsActive: @escaping () -> Bool = { false }
    ) {
        self.remoteStore = remoteStore
        self.debugProfileIsActive = debugProfileIsActive
    }

    func fetchHome() async throws -> HomeStateDTO {
        #if DEBUG
        if debugProfileIsActive() { return StreakDemoFixture.home }
        #endif
        return try await remoteStore.fetchHome(deviceId: DeviceIdentity.shared)
    }

    func earnAttendance(now: Date) async throws -> AttendanceResultDTO {
        try await earnAttendance(now: now, decision: nil, expectedMissedDays: nil)
    }

    func fetchAttendanceStatus() async throws -> AttendanceStatusDTO {
        #if DEBUG
        if debugProfileIsActive() { return StreakDemoFixture.attendanceStatus }
        #endif
        return try await remoteStore.fetchAttendanceStatus()
    }

    func earnAttendance(
        now: Date,
        decision: FreezeDecisionDTO?,
        expectedMissedDays: Int?
    ) async throws -> AttendanceResultDTO {
        #if DEBUG
        if debugProfileIsActive() { return StreakDemoFixture.attendanceResult }
        #endif
        let deviceId = DeviceIdentity.shared
        return try await remoteStore.earnAttendance(
            deviceId: deviceId,
            idempotencyKey: AttendanceKey.make(deviceId: deviceId, now: now),
            decision: decision,
            expectedMissedDays: expectedMissedDays
        )
    }

    func fetchRewardHistory() async throws -> [RewardHistoryDTO] {
        #if DEBUG
        if debugProfileIsActive() { return [] }
        #endif
        return try await remoteStore.fetchRewardHistory()
    }

    func fetchStreakDetail(month: String?) async throws -> StreakDetailDTO {
        #if DEBUG
        if debugProfileIsActive() { return StreakDemoFixture.detail(month: month) }
        #endif
        return try await remoteStore.fetchStreakDetail(month: month)
    }
}

#if DEBUG
enum StreakDemoFixture {
    static let home = HomeStateDTO(
        deviceId: "debug-profile",
        displayName: "개발자 다람이",
        points: 486,
        streak: 18,
        freezeInventory: 2,
        todayRealChewCount: 286,
        dailyGoal: 400,
        todayProgress: 0.715,
        todayCompleted: false,
        userId: "debug-profile"
    )

    static let attendanceStatus = AttendanceStatusDTO(
        asOf: "2026-07-16",
        status: .notNeeded,
        missedDates: [],
        requiredFreezes: 0,
        freezeInventory: 2
    )

    static let attendanceResult = AttendanceResultDTO(
        grantedPoints: 0,
        capped: false,
        idempotentReplay: true,
        streak: AttendanceStreakDTO(
            current: 18,
            longest: 18,
            startedOn: "2026-06-29",
            event: "NONE",
            freezeInventory: 2,
            freezeConsumed: 0,
            freezeGranted: 0
        ),
        userStats: home
    )

    static func detail(month requestedMonth: String?) -> StreakDetailDTO {
        let month = requestedMonth ?? "2026-07"
        return StreakDetailDTO(
            asOf: "2026-07-16",
            month: month,
            oldestRecordedOn: "2026-04-08",
            current: 18,
            longest: 18,
            startedOn: "2026-06-29",
            freezeInventory: 2,
            days: daysByMonth[month] ?? []
        )
    }

    private static let daysByMonth: [String: [StreakDayDTO]] = [
        "2026-04": makeDays(month: "2026-04", range: 8...19, frozen: [12]),
        "2026-05": makeDays(month: "2026-05", range: 2...14, frozen: [5, 11]),
        "2026-06": makeDays(month: "2026-06", range: 1...12, frozen: [6])
            + makeDays(month: "2026-06", range: 29...30),
        "2026-07": makeDays(month: "2026-07", range: 1...16, frozen: [3, 11]),
    ]

    private static func makeDays(
        month: String,
        range: ClosedRange<Int>,
        frozen: Set<Int> = []
    ) -> [StreakDayDTO] {
        range.map { day in
            StreakDayDTO(
                date: String(format: "%@-%02d", month, day),
                state: frozen.contains(day) ? .frozen : .attended
            )
        }
    }
}
#endif
