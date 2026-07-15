import Foundation

protocol MealSessionUploadRepository {
    func uploadSession(
        output: IMUSessionRecorder.Output,
        stats: SessionStats?,
        appVersion: String?
    ) async throws -> MealSessionUploadResult

    func fetchTodaySessions(startOfDay: Date) async throws -> [ChewingSessionDTO]
    func deleteSession(_ session: ChewingSessionDTO) async throws
    func deleteAllSessions() async throws
}

struct MealSessionUploadResult {
    let session: ChewingSessionDTO
    let result: CreateSessionResultDTO
}

struct RemoteStoreMealSessionUploadRepository: MealSessionUploadRepository {
    private let remoteStore: RemoteStore
    private let deviceIdProvider: () -> String

    init(
        remoteStore: RemoteStore,
        deviceIdProvider: @escaping () -> String = { DeviceIdentity.shared }
    ) {
        self.remoteStore = remoteStore
        self.deviceIdProvider = deviceIdProvider
    }

    func uploadSession(
        output: IMUSessionRecorder.Output,
        stats: SessionStats?,
        appVersion: String?
    ) async throws -> MealSessionUploadResult {
        let deviceId = deviceIdProvider()
        let storagePath = try await remoteStore.uploadIMUCSV(
            sessionId: output.sessionId,
            deviceId: deviceId,
            csvData: output.csvData
        )
        let session = makeSessionDTO(
            output: output,
            stats: stats,
            deviceId: deviceId,
            storagePath: storagePath,
            appVersion: appVersion
        )
        let result = try await remoteStore.createChewingSession(session)
        guard result.chewingSession.id == session.id else {
            throw RemoteStoreError.malformed("chewingSession id does not match uploaded session")
        }
        guard let topLevelReport = result.mealReport else {
            throw RemoteStoreError.malformed("missing top-level mealReport")
        }
        guard let embeddedReport = result.chewingSession.mealReport else {
            throw RemoteStoreError.malformed("missing chewingSession.mealReport")
        }
        guard topLevelReport == embeddedReport else {
            throw RemoteStoreError.malformed("mealReport does not match chewingSession.mealReport")
        }
        guard MealSessionReportability.isValidServerReport(topLevelReport, sessionId: session.id) else {
            throw RemoteStoreError.malformed("mealReport contract violation")
        }
        return MealSessionUploadResult(session: result.chewingSession, result: result)
    }

    func fetchTodaySessions(startOfDay: Date) async throws -> [ChewingSessionDTO] {
        try await remoteStore.fetchChewingSessions(deviceId: deviceIdProvider(), since: startOfDay)
    }

    func deleteSession(_ session: ChewingSessionDTO) async throws {
        try await remoteStore.deleteChewingSession(id: session.id, deviceId: deviceIdProvider())
    }

    func deleteAllSessions() async throws {
        try await remoteStore.deleteAllChewingSessions(deviceId: deviceIdProvider())
    }

    private func makeSessionDTO(
        output: IMUSessionRecorder.Output,
        stats: SessionStats?,
        deviceId: String,
        storagePath: String,
        appVersion: String?
    ) -> ChewingSessionDTO {
        ChewingSessionDTO(
            id: output.sessionId,
            deviceId: deviceId,
            startedAt: output.startedAt,
            endedAt: output.endedAt,
            durationSec: output.durationSec,
            sensorLocation: output.sensorLocation,
            sampleCount: output.sampleCount,
            sampleRateHz: 50,
            storagePath: storagePath,
            appVersion: appVersion,
            chewingSeconds: stats?.chewingSeconds,
            restSeconds: stats?.restSeconds,
            chewingFraction: stats?.chewingFraction,
            estimatedTotalChews: stats?.estimatedTotalChews,
            modelVersion: stats?.modelVersion,
            chewingTimeline: stats?.chewingTimeline
        )
    }
}
