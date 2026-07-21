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
        displayName: "다람이",
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

    static func dailyReport(date: String) -> DailyReportDTO {
        let sessions = mealSessions.filter { dateKey(from: $0.startedAt) == date }
        guard !sessions.isEmpty else { return emptyDailyReport(date: date) }
        return makeDailyReport(date: date, sessions: sessions)
    }

    static var mealSessions: [ChewingSessionDTO] {
        previousWeekSessions + captureDailyReport.meals.map(\.session)
    }

    private static let captureDate = "2026-07-16"
    private static let captureDurationSec = 1_740.0
    private static let captureChewingFraction = 1_148.0 / captureDurationSec
    private static let captureStartedAt = Date(timeIntervalSince1970: 1_784_171_400)
    private static let captureSessionId = UUID(uuid: (
        0x7A, 0x16, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17, 0x40
    ))

    private static let captureMealReport = MealReportDTO(
        status: .generated,
        sessionId: captureSessionId,
        scorePolicyVersion: "legacy-ios-v1",
        analysisModelVersion: "capture-fixture-v1",
        totalScore: 88,
        axisScores: .init(
            chewingRate: 100,
            chewingTimeRatio: 92,
            totalChewCount: 86,
            mealDuration: 78
        ),
        metrics: .init(
            chewingRatePerMin: nil,
            legacyMealRatePerMin: 28,
            chewingTimeRatio: captureChewingFraction,
            totalChewCount: 812,
            mealDurationSec: captureDurationSec
        ),
        grade: .good,
        recommendedBaseline: .init(
            chewingRatePerMin: .init(target: 28),
            chewingTimeRatio: 0.6,
            totalChewCount: 600,
            mealDurationSec: 1_200
        )
    )

    private static let captureMeal = DailyReportMealDTO(
        sessionId: captureSessionId,
        slot: "LUNCH",
        startedAt: captureStartedAt,
        endedAt: captureStartedAt.addingTimeInterval(captureDurationSec),
        durationSec: captureDurationSec,
        totalChews: 812,
        chewRatePerMin: 28,
        chewingFraction: captureChewingFraction,
        paceBadge: "적당해요",
        mealReport: captureMealReport
    )

    private static let captureDailyReport = DailyReportDTO(
        date: captureDate,
        timezone: "Asia/Seoul",
        mealCount: 1,
        totalEatingSeconds: captureDurationSec,
        totalChews: 812,
        avgChewRatePerMin: 28,
        avgChewingFraction: captureChewingFraction,
        avgTotalScore: 88,
        meals: [captureMeal],
        vsYesterday: nil
    )

    private static let previousWeekSessions: [ChewingSessionDTO] = [
        makeSession(daysBeforeCapture: 6, durationSec: 1_380, chews: 620, rate: 27, fraction: 0.61, score: 74),
        makeSession(daysBeforeCapture: 5, durationSec: 1_620, chews: 760, rate: 28, fraction: 0.67, score: 85),
        makeSession(daysBeforeCapture: 4, durationSec: 1_500, chews: 690, rate: 26, fraction: 0.63, score: 78),
        makeSession(daysBeforeCapture: 3, durationSec: 1_800, chews: 840, rate: 28, fraction: 0.69, score: 91),
        makeSession(
            daysBeforeCapture: 2,
            hourOffset: -4,
            durationSec: 480,
            chews: 205,
            rate: 26,
            fraction: 0.61,
            score: 78
        ),
        makeSession(
            daysBeforeCapture: 2,
            durationSec: 600,
            chews: 295,
            rate: 29,
            fraction: 0.66,
            score: 86
        ),
        makeSession(
            daysBeforeCapture: 2,
            hourOffset: 7,
            durationSec: 480,
            chews: 235,
            rate: 27,
            fraction: 0.65,
            score: 82
        ),
        makeSession(daysBeforeCapture: 1, durationSec: 1_680, chews: 790, rate: 28, fraction: 0.68, score: 87),
    ]

    // 캡처 fixture 한 줄에서 그래프 축을 함께 조정하므로 값 묶음을 그대로 노출한다.
    // swiftlint:disable:next function_parameter_count
    private static func makeSession(
        daysBeforeCapture: Int,
        hourOffset: Int = 0,
        durationSec: Double,
        chews: Int,
        rate: Double,
        fraction: Double,
        score: Int
    ) -> ChewingSessionDTO {
        let sessionId = UUID()
        let startedAt = captureStartedAt.addingTimeInterval(
            (-Double(daysBeforeCapture) * 86_400) + (Double(hourOffset) * 3_600)
        )
        let report = MealReportDTO(
            status: .generated,
            sessionId: sessionId,
            scorePolicyVersion: "legacy-ios-v1",
            analysisModelVersion: "capture-fixture-v1",
            totalScore: score,
            axisScores: .init(
                chewingRate: min(100, score + 8),
                chewingTimeRatio: min(100, score + 3),
                totalChewCount: max(0, score - 2),
                mealDuration: max(0, score - 6)
            ),
            metrics: .init(
                chewingRatePerMin: nil,
                legacyMealRatePerMin: rate,
                chewingTimeRatio: fraction,
                totalChewCount: chews,
                mealDurationSec: durationSec
            ),
            grade: score >= 85 ? .good : .soso,
            recommendedBaseline: .init(
                chewingRatePerMin: .init(target: 28),
                chewingTimeRatio: 0.6,
                totalChewCount: 600,
                mealDurationSec: 1_200
            )
        )
        return ChewingSessionDTO(
            id: sessionId,
            deviceId: "debug-profile",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(durationSec),
            durationSec: durationSec,
            sensorLocation: "capture-fixture",
            sampleCount: 0,
            sampleRateHz: 0,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: durationSec * fraction,
            restSeconds: durationSec * (1 - fraction),
            chewingFraction: fraction,
            estimatedTotalChews: chews,
            modelVersion: "capture-fixture-v1",
            mealReport: report,
            userId: "debug-profile"
        )
    }

    private static func emptyDailyReport(date: String) -> DailyReportDTO {
        DailyReportDTO(
            date: date,
            timezone: "Asia/Seoul",
            mealCount: 0,
            totalEatingSeconds: 0,
            totalChews: 0,
            avgChewRatePerMin: nil,
            avgChewingFraction: nil,
            avgTotalScore: nil,
            meals: [],
            vsYesterday: nil
        )
    }

    private static func makeDailyReport(date: String, sessions: [ChewingSessionDTO]) -> DailyReportDTO {
        let meals = sessions.compactMap(makeDailyReportMeal)
        let totalEatingSeconds = meals.reduce(0) { $0 + $1.durationSec }
        let totalChews = meals.compactMap(\.totalChews).reduce(0, +)
        let rates = meals.compactMap(\.chewRatePerMin)
        let fractions = meals.compactMap(\.chewingFraction)
        let scores = meals.compactMap { $0.mealReport.totalScore }.map(Double.init)
        return DailyReportDTO(
            date: date,
            timezone: "Asia/Seoul",
            mealCount: meals.count,
            totalEatingSeconds: totalEatingSeconds,
            totalChews: totalChews,
            avgChewRatePerMin: average(rates),
            avgChewingFraction: average(fractions),
            avgTotalScore: average(scores),
            meals: meals,
            vsYesterday: nil
        )
    }

    private static func makeDailyReportMeal(session: ChewingSessionDTO) -> DailyReportMealDTO? {
        guard let mealReport = session.mealReport else { return nil }
        let hour = fixtureCalendar.component(.hour, from: session.startedAt)
        let slot = if hour < 11 { "BREAKFAST" } else if hour < 17 { "LUNCH" } else { "DINNER" }
        return DailyReportMealDTO(
            sessionId: session.id,
            slot: slot,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSec: session.durationSec,
            totalChews: session.estimatedTotalChews ?? mealReport.metrics?.totalChewCount,
            chewRatePerMin: mealReport.metrics?.legacyMealRatePerMin,
            chewingFraction: session.chewingFraction ?? mealReport.metrics?.chewingTimeRatio,
            paceBadge: "적당해요",
            mealReport: mealReport
        )
    }

    private static func dateKey(from date: Date) -> String {
        fixtureDateFormatter.string(from: date)
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static var fixtureCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private static var fixtureDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = fixtureCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = fixtureCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
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
