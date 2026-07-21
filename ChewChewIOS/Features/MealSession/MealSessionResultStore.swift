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
    private struct PendingUpload {
        let output: IMUSessionRecorder.Output
        let stats: SessionStats?
        let failedAttemptCount: Int
    }

    @ObservationIgnored private var pendingUpload: PendingUpload?

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

    /// 홈 API를 아직 받지 못한 짧은 구간에만 쓰는 저장 리포트 기반 fallback.
    /// raw 분석값이나 rewardEligible을 홈 진행도와 결합하지 않는다.
    var serverReportTodayChewCount: Int {
        todaySessions.reduce(0) { partial, session in
            guard let report = MealSessionReportability.completeGeneratedReport(
                session.mealReport,
                sessionId: session.id
            ) else { return partial }
            return partial + (report.metrics?.totalChewCount ?? 0)
        }
    }

    func uploadSession(_ output: IMUSessionRecorder.Output, stats: SessionStats?) async {
        await performUpload(output, stats: stats, attemptNumber: 1)
    }

    private func performUpload(
        _ output: IMUSessionRecorder.Output,
        stats: SessionStats?,
        attemptNumber: Int
    ) async {
        sessionUploadStatus = .uploading
        do {
            let upload = try await repository.uploadSession(output: output, stats: stats, appVersion: appVersion)
            let result = upload.result
            let dto = result.chewingSession
            sessionUploadStatus = .success
            sessionUploadErrorMessage = nil
            pendingUpload = nil
            onHomeReceived(result.userStats)

            lastCompletedSession = dto
            let isReportable = MealSessionReportability.isReportable(dto)
            analytics.track(.mealSessionCompleted(
                sessionId: output.sessionId,
                durationSec: Int(dto.durationSec),
                sampleCount: dto.sampleCount,
                chewingFraction: dto.chewingFraction,
                estimatedTotalChews: dto.estimatedTotalChews,
                reportable: isReportable
            ))
            onSessionRewardReceived(result)

            if isReportable {
                todaySessions.append(dto)
            }
        } catch {
            // 인증 만료도 측정을 마쳤지만 저장하지 못한 결과다. 세션의 기존 user_id가 지워지기 전에
            // 실패 이벤트를 먼저 보내야 사용자와 동일 meal_session_id에 귀속된다.
            analytics.track(.mealSessionFailed(
                sessionId: output.sessionId,
                reason: Self.uploadFailureReason(error),
                attemptNumber: attemptNumber
            ))
            onRemoteError(error)
            if case RemoteStoreError.authExpired = error { return }
            sessionUploadStatus = .failure
            sessionUploadErrorMessage = (error as? RemoteStoreError)?.userMessage
            pendingUpload = PendingUpload(
                output: output,
                stats: stats,
                failedAttemptCount: attemptNumber
            )
        }
    }

    func fetchTodaySessions() async {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        do {
            let rows = try await repository.fetchTodaySessions(startOfDay: startOfDay)
            todaySessions = rows.filter(MealSessionReportability.isReportable)
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
        guard sessionUploadStatus == .failure, let pending = pendingUpload else { return }
        let nextAttemptNumber = pending.failedAttemptCount + 1
        // AppDialog는 버튼 액션 직후 isPresented=false를 쓴다. 여기서 동기적으로 failure를
        // 벗어나야 그 dismiss가 사용자 포기(upload_abandoned)로 오인되지 않는다.
        sessionUploadStatus = .uploading
        sessionUploadErrorMessage = nil
        analytics.track(.mealSessionUploadRetryRequested(
            sessionId: pending.output.sessionId,
            nextAttemptNumber: nextAttemptNumber
        ))
        Task { [weak self] in
            await self?.performUpload(
                pending.output,
                stats: pending.stats,
                attemptNumber: nextAttemptNumber
            )
        }
    }

    func dismissSessionUploadStatus() {
        if sessionUploadStatus == .failure, let pending = pendingUpload {
            analytics.track(.mealSessionUploadAbandoned(
                sessionId: pending.output.sessionId,
                failedAttemptCount: pending.failedAttemptCount
            ))
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
