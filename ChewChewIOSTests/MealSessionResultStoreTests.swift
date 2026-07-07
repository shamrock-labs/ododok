import XCTest
@testable import ChewChewIOS

@MainActor
final class MealSessionResultStoreTests: XCTestCase {
    func testUploadSuccessUsesRepositoryAndPublishesResult() async {
        let repository = FakeMealSessionUploadRepository()
        let output = makeOutput()
        let session = makeSession(id: output.sessionId)
        let result = makeResult(session: session)
        repository.uploadResults = [.success(.init(session: session, result: result))]
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
        XCTAssertEqual(store.todaySessions, [session])
        XCTAssertEqual(store.lastCompletedSession, session)
        XCTAssertEqual(receivedHome, result.userStats)
        XCTAssertEqual(receivedReward, result)
    }

    func testUploadFailureKeepsPendingPayloadForRetry() async {
        let repository = FakeMealSessionUploadRepository()
        let output = makeOutput()
        let session = makeSession(id: output.sessionId)
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

    func testFetchTodaySessionsFiltersUnreportableRowsAndRefreshesHome() async {
        let repository = FakeMealSessionUploadRepository()
        let reportable = makeSession(id: UUID())
        let short = makeSession(id: UUID(), durationSec: 20)
        repository.todaySessions = [reportable, short]
        var refreshCount = 0
        let store = makeStore(repository: repository, refreshHome: { refreshCount += 1 })

        await store.fetchTodaySessions()

        XCTAssertEqual(store.todaySessions, [reportable])
        XCTAssertEqual(repository.fetchTodayStartOfDayCount, 1)
        XCTAssertEqual(refreshCount, 1)
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
        onHomeReceived: @escaping @MainActor (HomeStateDTO) -> Void = { _ in },
        onSessionRewardReceived: @escaping @MainActor (CreateSessionResultDTO) -> Void = { _ in },
        onRemoteError: @escaping @MainActor (Error) -> Void = { _ in },
        refreshHome: @escaping @MainActor () async -> Void = {}
    ) -> MealSessionResultStore {
        MealSessionResultStore(
            repository: repository,
            analytics: NoopAnalytics(),
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

    private func makeSession(id: UUID, durationSec: Double = 180) -> ChewingSessionDTO {
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
            chewingTimeline: "111000"
        )
    }

    private func makeResult(session: ChewingSessionDTO) -> CreateSessionResultDTO {
        CreateSessionResultDTO(
            chewingSession: session,
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
