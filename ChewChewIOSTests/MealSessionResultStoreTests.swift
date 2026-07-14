import XCTest
@testable import ChewChewIOS

@MainActor
final class MealSessionResultStoreTests: XCTestCase {
    func testUploadSuccessUsesRepositoryAndPublishesResult() async {
        let repository = FakeMealSessionUploadRepository()
        let output = makeOutput()
        let localSession = makeSession(id: output.sessionId)
        let serverSession = makeSession(
            id: output.sessionId,
            mealReport: makeGeneratedReport(sessionId: output.sessionId)
        )
        let result = makeResult(session: serverSession)
        repository.uploadResults = [.success(.init(session: localSession, result: result))]
        var receivedHome: HomeStateDTO?
        var receivedReward: CreateSessionResultDTO?
        let store = makeStore(
            repository: repository,
            onHomeReceived: { receivedHome = $0 },
            onSessionRewardReceived: { receivedReward = $0 }
        )

        await store.uploadSession(output, stats: makeStats())

        XCTAssertEqual(repository.uploadCalls.map(\.output.sessionId), [output.sessionId])
        XCTAssertEqual(repository.uploadCalls.first?.appVersion, "test-version")
        XCTAssertEqual(store.sessionUploadStatus, .success)
        XCTAssertNil(store.sessionUploadErrorMessage)
        XCTAssertEqual(store.todaySessions, [serverSession])
        XCTAssertEqual(store.lastCompletedSession, serverSession)
        XCTAssertEqual(receivedHome, result.userStats)
        XCTAssertEqual(receivedReward, result)
    }

    func testUnreportableUploadPublishesServerReasonWithoutAddingReportCollection() async {
        let repository = FakeMealSessionUploadRepository()
        let analytics = SpyMealSessionAnalytics()
        let output = makeOutput()
        let localSession = makeSession(id: output.sessionId)
        let serverSession = makeSession(
            id: output.sessionId,
            mealReport: MealReportDTO(
                status: .unreportable,
                reason: .sessionTooShort,
                sessionId: output.sessionId
            )
        )
        let result = makeResult(session: serverSession)
        repository.uploadResults = [.success(.init(session: localSession, result: result))]
        var receivedReward: CreateSessionResultDTO?
        let store = makeStore(
            repository: repository,
            analytics: analytics,
            onSessionRewardReceived: { receivedReward = $0 }
        )

        await store.uploadSession(output, stats: makeStats())

        XCTAssertEqual(store.sessionUploadStatus, .success)
        XCTAssertEqual(store.lastCompletedSession, serverSession)
        XCTAssertEqual(store.lastCompletedSession?.mealReport?.reason, .sessionTooShort)
        XCTAssertTrue(store.todaySessions.isEmpty)
        XCTAssertEqual(receivedReward, result)
        XCTAssertEqual(analytics.completedReportableValues, [false])
    }

    func testUploadFailureKeepsPendingPayloadForRetry() async {
        let repository = FakeMealSessionUploadRepository()
        let output = makeOutput()
        let session = makeSession(
            id: output.sessionId,
            mealReport: makeGeneratedReport(sessionId: output.sessionId)
        )
        let result = makeResult(session: session)
        repository.uploadResults = [
            .failure(RemoteStoreError.offline),
            .success(.init(session: session, result: result))
        ]
        var remoteErrors: [Error] = []
        let store = makeStore(repository: repository, onRemoteError: { remoteErrors.append($0) })

        await store.uploadSession(output, stats: makeStats())

        XCTAssertEqual(store.sessionUploadStatus, .failure)
        XCTAssertEqual(store.sessionUploadErrorMessage, RemoteStoreError.offline.userMessage)
        XCTAssertEqual(remoteErrors.count, 1)

        store.retryLastSessionUpload()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(repository.uploadCalls.count, 2)
        XCTAssertEqual(store.sessionUploadStatus, .success)
        XCTAssertEqual(store.todaySessions, [session])
    }

    func testMalformedMealReportResponseDoesNotPublishSuccess() async {
        let repository = FakeMealSessionUploadRepository()
        let output = makeOutput()
        repository.uploadResults = [
            .failure(RemoteStoreError.malformed("mealReport contract violation"))
        ]
        let store = makeStore(repository: repository)

        await store.uploadSession(output, stats: makeStats())

        XCTAssertEqual(store.sessionUploadStatus, .failure)
        XCTAssertNil(store.lastCompletedSession)
        XCTAssertTrue(store.todaySessions.isEmpty)
    }

    func testFetchTodaySessionsFiltersUnreportableRowsAndRefreshesHome() async {
        let repository = FakeMealSessionUploadRepository()
        let reportableId = UUID()
        let reportable = makeSession(id: reportableId, mealReport: makeGeneratedReport(sessionId: reportableId))
        let unreportable = makeSession(
            id: UUID(),
            mealReport: MealReportDTO(status: .unreportable, reason: .analysisMissing)
        )
        repository.todaySessions = [reportable, unreportable]
        var refreshCount = 0
        let store = makeStore(repository: repository, refreshHome: { refreshCount += 1 })

        await store.fetchTodaySessions()

        XCTAssertEqual(store.todaySessions, [reportable])
        XCTAssertEqual(repository.fetchTodayStartOfDayCount, 1)
        XCTAssertEqual(refreshCount, 1)
    }

    func testHomeFallbackChewCountUsesOnlyCompleteStoredReportMetrics() async {
        let repository = FakeMealSessionUploadRepository()
        let generatedId = UUID()
        var generated = makeSession(
            id: generatedId,
            mealReport: makeGeneratedReport(sessionId: generatedId, totalChewCount: 432)
        )
        generated.estimatedTotalChews = 9_999
        var unreportable = makeSession(
            id: UUID(),
            mealReport: MealReportDTO(status: .unreportable, reason: .analysisMissing)
        )
        unreportable.estimatedTotalChews = 8_888
        repository.todaySessions = [generated, unreportable]
        let store = makeStore(repository: repository)

        await store.fetchTodaySessions()

        XCTAssertEqual(store.serverReportTodayChewCount, 432)
    }

    func testDeleteSessionUsesRepositoryThenRefreshesHome() async {
        let repository = FakeMealSessionUploadRepository()
        let session = makeSession(id: UUID())
        var refreshCount = 0
        let store = makeStore(repository: repository, refreshHome: { refreshCount += 1 })
        store.todaySessions = [session]

        await store.deleteSession(session)

        XCTAssertEqual(repository.deletedSessionIds, [session.id])
        XCTAssertTrue(store.todaySessions.isEmpty)
        XCTAssertEqual(refreshCount, 1)
    }

    func testDeleteAllSessionsUsesRepositoryThenRefreshesHome() async {
        let repository = FakeMealSessionUploadRepository()
        let store = makeStore(repository: repository)
        store.todaySessions = [makeSession(id: UUID())]

        await store.deleteAllChewingSessions()

        XCTAssertEqual(repository.deleteAllCallCount, 1)
        XCTAssertTrue(store.todaySessions.isEmpty)
    }

    private func makeStore(
        repository: FakeMealSessionUploadRepository,
        analytics: AnalyticsService = NoopAnalytics(),
        onHomeReceived: @escaping @MainActor (HomeStateDTO) -> Void = { _ in },
        onSessionRewardReceived: @escaping @MainActor (CreateSessionResultDTO) -> Void = { _ in },
        onRemoteError: @escaping @MainActor (Error) -> Void = { _ in },
        refreshHome: @escaping @MainActor () async -> Void = {}
    ) -> MealSessionResultStore {
        MealSessionResultStore(
            repository: repository,
            analytics: analytics,
            appVersion: "test-version",
            onHomeReceived: onHomeReceived,
            onSessionRewardReceived: onSessionRewardReceived,
            onRemoteError: onRemoteError,
            refreshHome: refreshHome
        )
    }

    private func makeOutput(sessionId: UUID = UUID()) -> IMUSessionRecorder.Output {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return IMUSessionRecorder.Output(
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(180),
            durationSec: 180,
            sampleCount: 9_000,
            sensorLocation: "headphone_left",
            csvData: Data("csv".utf8),
            interruptionGaps: []
        )
    }

    private func makeStats() -> SessionStats {
        SessionStats(
            chewingSeconds: 90,
            restSeconds: 90,
            chewingFraction: 0.5,
            estimatedTotalChews: 180,
            modelVersion: "test-model",
            chewingTimeline: "111000"
        )
    }

    private func makeSession(
        id: UUID,
        durationSec: Double = 180,
        mealReport: MealReportDTO? = nil
    ) -> ChewingSessionDTO {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return ChewingSessionDTO(
            id: id,
            deviceId: "test-device",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(durationSec),
            durationSec: durationSec,
            sensorLocation: "headphone_left",
            sampleCount: 9_000,
            sampleRateHz: 50,
            storagePath: "imu/\(id).csv",
            appVersion: "test-version",
            chewingSeconds: 90,
            restSeconds: 90,
            chewingFraction: 0.5,
            estimatedTotalChews: 180,
            modelVersion: "test-model",
            chewingTimeline: "111000",
            mealReport: mealReport
        )
    }

    private func makeGeneratedReport(sessionId: UUID, totalChewCount: Int = 180) -> MealReportDTO {
        MealReportDTO(
            status: .generated,
            sessionId: sessionId,
            scorePolicyVersion: "legacy-ios-v1",
            analysisModelVersion: "server",
            totalScore: 71,
            axisScores: .init(chewingRate: 0, chewingTimeRatio: 100, totalChewCount: 100, mealDuration: 85),
            metrics: .init(
                chewingRatePerMin: nil,
                legacyMealRatePerMin: 28,
                chewingTimeRatio: 0.5,
                totalChewCount: totalChewCount,
                mealDurationSec: 180
            ),
            grade: .soso,
            recommendedBaseline: .init(
                chewingRatePerMin: .init(target: 28),
                chewingTimeRatio: 0.5,
                totalChewCount: 200,
                mealDurationSec: 720
            )
        )
    }

    private func makeResult(session: ChewingSessionDTO) -> CreateSessionResultDTO {
        CreateSessionResultDTO(
            chewingSession: session,
            mealReport: session.mealReport
                ?? MealReportDTO(status: .unreportable, reason: .analysisMissing),
            chewingSessionAccepted: true,
            rewardEligible: true,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 3, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 1, event: "FIRST_DAY", freezeInventory: 0),
            today: SessionTodayDTO(completed: true),
            userStats: .empty(deviceId: session.deviceId)
        )
    }
}

private final class FakeMealSessionUploadRepository: MealSessionUploadRepository {
    struct UploadCall {
        let output: IMUSessionRecorder.Output
        let stats: SessionStats?
        let appVersion: String?
    }

    var uploadResults: [Result<MealSessionUploadResult, Error>] = []
    var uploadCalls: [UploadCall] = []
    var todaySessions: [ChewingSessionDTO] = []
    var fetchTodayStartOfDayCount = 0
    var deletedSessionIds: [UUID] = []
    var deleteAllCallCount = 0

    func uploadSession(
        output: IMUSessionRecorder.Output,
        stats: SessionStats?,
        appVersion: String?
    ) async throws -> MealSessionUploadResult {
        uploadCalls.append(.init(output: output, stats: stats, appVersion: appVersion))
        guard !uploadResults.isEmpty else {
            throw RemoteStoreError.malformed("missing fake upload result")
        }
        return try uploadResults.removeFirst().get()
    }

    func fetchTodaySessions(startOfDay: Date) async throws -> [ChewingSessionDTO] {
        fetchTodayStartOfDayCount += 1
        return todaySessions
    }

    func deleteSession(_ session: ChewingSessionDTO) async throws {
        deletedSessionIds.append(session.id)
    }

    func deleteAllSessions() async throws {
        deleteAllCallCount += 1
    }
}

private final class SpyMealSessionAnalytics: AnalyticsService {
    private(set) var completedReportableValues: [Bool] = []

    func track(_ event: AnalyticsEvent) {
        guard event.name == "meal_session_completed",
              let reportable = event.properties["reportable"] as? Bool else { return }
        completedReportableValues.append(reportable)
    }

    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}
