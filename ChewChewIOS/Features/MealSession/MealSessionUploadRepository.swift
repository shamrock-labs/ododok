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
        return MealSessionUploadResult(session: session, result: result)
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
