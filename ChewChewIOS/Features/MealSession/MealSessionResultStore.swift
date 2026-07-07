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

    private let repository: MealSessionUploadRepository
    private let analytics: AnalyticsService
    private let appVersion: String?
    private let onHomeReceived: @MainActor (HomeStateDTO) -> Void
    private let onSessionRewardReceived: @MainActor (CreateSessionResultDTO) -> Void
    private let onRemoteError: @MainActor (Error) -> Void
    private let refreshHome: @MainActor () async -> Void
    @ObservationIgnored private var pendingUpload: (output: IMUSessionRecorder.Output, stats: SessionStats?)?

    init(
        repository: MealSessionUploadRepository,
        analytics: AnalyticsService,
        appVersion: String?,
        onHomeReceived: @escaping @MainActor (HomeStateDTO) -> Void,
        onSessionRewardReceived: @escaping @MainActor (CreateSessionResultDTO) -> Void,
        onRemoteError: @escaping @MainActor (Error) -> Void,
        refreshHome: @escaping @MainActor () async -> Void
    ) {
        self.repository = repository
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
            let upload = try await repository.uploadSession(output: output, stats: stats, appVersion: appVersion)
            let dto = upload.session
            let result = upload.result
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
        do {
            let rows = try await repository.fetchTodaySessions(startOfDay: startOfDay)
            todaySessions = rows.filter { ReportCardModel.from($0) != nil }
            await refreshHome()
        } catch {
            onRemoteError(error)
        }
    }

    func deleteSession(_ session: ChewingSessionDTO) async {
        do {
            try await repository.deleteSession(session)
            todaySessions.removeAll { $0.id == session.id }
            await refreshHome()
        } catch {
            onRemoteError(error)
        }
    }

    func deleteAllChewingSessions() async {
        do {
            try await repository.deleteAllSessions()
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

    func closeResultPresentation() {
        lastCompletedSession = nil
        if sessionUploadStatus == .success {
            dismissSessionUploadStatus()
        }
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
