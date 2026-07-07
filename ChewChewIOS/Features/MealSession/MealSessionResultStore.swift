import Foundation
import Observation

enum MealSessionUploadStatus: Equatable {
    case idle
    case uploading
    case success
    case failure

    var isTerminal: Bool {
        self == .success || self == .failure
    }
}

@Observable
@MainActor
final class MealSessionResultStore {
    var sessionUploadStatus: MealSessionUploadStatus = .idle
    var sessionUploadErrorMessage: String?
    var todaySessions: [ChewingSessionDTO] = []
    var lastCompletedSession: ChewingSessionDTO?

    private let remoteStore: RemoteStore
    private let analytics: AnalyticsService
    private let appVersion: String?
    private let onHomeReceived: @MainActor (HomeStateDTO) -> Void
    private let onSessionRewardReceived: @MainActor (CreateSessionResultDTO) -> Void
    private let onRemoteError: @MainActor (Error) -> Void
    private let refreshHome: @MainActor () async -> Void
    @ObservationIgnored private var pendingUpload: (output: IMUSessionRecorder.Output, stats: SessionStats?)?

    init(
        remoteStore: RemoteStore,
        analytics: AnalyticsService,
        appVersion: String?,
        onHomeReceived: @escaping @MainActor (HomeStateDTO) -> Void,
        onSessionRewardReceived: @escaping @MainActor (CreateSessionResultDTO) -> Void,
        onRemoteError: @escaping @MainActor (Error) -> Void,
        refreshHome: @escaping @MainActor () async -> Void
    ) {
        self.remoteStore = remoteStore
        self.analytics = analytics
        self.appVersion = appVersion
        self.onHomeReceived = onHomeReceived
        self.onSessionRewardReceived = onSessionRewardReceived
        self.onRemoteError = onRemoteError
        self.refreshHome = refreshHome
    }

    var localTodayRealChewCount: Int {
        todaySessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
    }

    func uploadSession(_ output: IMUSessionRecorder.Output, stats: SessionStats?) async {
        sessionUploadStatus = .uploading
        do {
            let deviceId = DeviceIdentity.shared
            let storagePath = try await remoteStore.uploadIMUCSV(
                sessionId: output.sessionId,
                deviceId: deviceId,
                csvData: output.csvData
            )
            let dto = makeSessionDTO(output: output, stats: stats, deviceId: deviceId, storagePath: storagePath)
            let result = try await remoteStore.createChewingSession(dto)
            sessionUploadStatus = .success
            sessionUploadErrorMessage = nil
            pendingUpload = nil
            onHomeReceived(result.userStats)

            let isReportable = ReportCardModel.from(dto) != nil
            analytics.track(.mealSessionCompleted(
                durationSec: Int(dto.durationSec),
                sampleCount: dto.sampleCount,
                chewingFraction: dto.chewingFraction,
                estimatedTotalChews: dto.estimatedTotalChews,
                reportable: isReportable
            ))
            guard isReportable else { return }

            todaySessions.append(dto)
            lastCompletedSession = dto
            onSessionRewardReceived(result)
        } catch {
            onRemoteError(error)
            if case RemoteStoreError.authExpired = error { return }
            analytics.track(.mealSessionFailed(reason: Self.uploadFailureReason(error)))
            sessionUploadStatus = .failure
            sessionUploadErrorMessage = (error as? RemoteStoreError)?.userMessage
            pendingUpload = (output: output, stats: stats)
        }
    }

    func fetchTodaySessions() async {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let deviceId = DeviceIdentity.shared
        do {
            let rows = try await remoteStore.fetchChewingSessions(deviceId: deviceId, since: startOfDay)
            todaySessions = rows.filter { ReportCardModel.from($0) != nil }
            await refreshHome()
        } catch {
            onRemoteError(error)
        }
    }

    func deleteSession(_ session: ChewingSessionDTO) async {
        do {
            try await remoteStore.deleteChewingSession(id: session.id, deviceId: DeviceIdentity.shared)
            todaySessions.removeAll { $0.id == session.id }
            await refreshHome()
        } catch {
            onRemoteError(error)
        }
    }

    func deleteAllChewingSessions() async {
        do {
            try await remoteStore.deleteAllChewingSessions(deviceId: DeviceIdentity.shared)
            todaySessions = []
            await refreshHome()
        } catch {
            onRemoteError(error)
        }
    }

    func retryLastSessionUpload() {
        guard let pending = pendingUpload else { return }
        Task { [weak self] in
            await self?.uploadSession(pending.output, stats: pending.stats)
        }
    }

    func dismissSessionUploadStatus() {
        if sessionUploadStatus == .failure {
            pendingUpload = nil
        }
        sessionUploadStatus = .idle
        sessionUploadErrorMessage = nil
    }

    func resetTransientState() {
        lastCompletedSession = nil
        sessionUploadStatus = .idle
        sessionUploadErrorMessage = nil
        pendingUpload = nil
    }

    func resetAll() {
        todaySessions = []
        resetTransientState()
    }

    private func makeSessionDTO(
        output: IMUSessionRecorder.Output,
        stats: SessionStats?,
        deviceId: String,
        storagePath: String
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

    private static func uploadFailureReason(_ error: Error) -> String {
        guard let remoteError = error as? RemoteStoreError else { return "unknown" }
        switch remoteError {
        case .authExpired: return "auth_expired"
        case .server: return "server"
        case .offline: return "offline"
        case .malformed: return "malformed"
        case .http: return "http"
        case .invalidUploadResponse: return "invalid_upload"
        }
    }
}
