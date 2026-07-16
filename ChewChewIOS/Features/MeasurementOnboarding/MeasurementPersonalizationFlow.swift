import SwiftUI

struct MeasurementPersonalizationFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var store: MeasurementOnboardingStore
    @State private var connectionMonitor: AirPodsConnectionMonitor
    @State private var analyticsTracker: ChewProfileSetupAnalyticsTracker
    @State private var isPreparingAirPods = false
    @State private var isSavingProfile = false
    @State private var saveErrorMessage: String?
    @State private var readinessTask: Task<Void, Never>?

    private let readinessService: any AirPodsAudioReadinessServicing
    private let artifactUploader: any MeasurementCalibrationArtifactUploading
    private let onSaved: (PersonalizedChewDetectionSettings) async throws -> Void

    init(
        source: ChewProfileSetupSource,
        analytics: AnalyticsService,
        remoteStore: any RemoteStore = NoopRemoteStore(),
        readinessService: (any AirPodsAudioReadinessServicing)? = nil,
        onSaved: @escaping (PersonalizedChewDetectionSettings) async throws -> Void
    ) {
        let connectionMonitor = AirPodsConnectionMonitor()
        #if DEBUG && targetEnvironment(simulator)
        let sampler: any MeasurementCalibrationSampling = SimulatedMeasurementCalibrationSampler()
        let defaultReadinessService: any AirPodsAudioReadinessServicing =
            SimulatedAirPodsAudioReadinessService()
        let isConnected = true
        #else
        let sampler: any MeasurementCalibrationSampling = LocalMeasurementCalibrationSampler()
        let defaultReadinessService: any AirPodsAudioReadinessServicing = AirPodsAudioReadinessService()
        let isConnected = connectionMonitor.isConnected
        #endif
        let audioReadinessService = readinessService ?? defaultReadinessService
        let artifactUploader = CalibrationArtifactUploadQueue(remoteStore: remoteStore)

        _connectionMonitor = State(initialValue: connectionMonitor)
        _analyticsTracker = State(initialValue: ChewProfileSetupAnalyticsTracker(
            source: source,
            analytics: analytics
        ))
        _store = State(initialValue: MeasurementOnboardingStore(
            isAirPodsConnected: isConnected,
            sampler: sampler,
            artifactUploader: artifactUploader,
            cuePlayer: audioReadinessService
        ))
        self.readinessService = audioReadinessService
        self.artifactUploader = artifactUploader
        self.onSaved = onSaved
    }

    var body: some View {
        MeasurementOnboardingView(
            store: store,
            onComplete: saveAndDismiss,
            onSkip: {
                analyticsTracker.dismiss(at: store.stage)
                dismiss()
            },
            onRetryConnection: requestAirPodsReadiness,
            skipTitle: "닫기",
            isPreparingAirPods: isPreparingAirPods
        )
        .onAppear {
            analyticsTracker.start()
            refreshConnection()
            connectionMonitor.start { connected in
                Task { @MainActor in store.setAirPodsConnected(connected) }
            }
        }
        .task {
            await artifactUploader.retryPending()
        }
        .onDisappear {
            store.cancelMeasurement()
            readinessTask?.cancel()
            readinessService.stop()
            connectionMonitor.stop()
        }
        .onChange(of: store.stage) { oldStage, stage in
            analyticsTracker.transition(from: oldStage, to: stage, issue: store.issue)
            if stage == .connection {
                requestAirPodsReadiness()
            }
        }
        .disabled(isSavingProfile)
        .overlay {
            if isSavingProfile {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("맞춤 기준을 저장하고 있어요")
                        .padding(AppSpacing.four)
                        .background(Color.bgPopover, in: RoundedRectangle(cornerRadius: AppRadius.element))
                }
            }
        }
        .alert(
            "맞춤 기준을 저장하지 못했어요",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func refreshConnection() {
        #if DEBUG && targetEnvironment(simulator)
        store.setAirPodsConnected(true)
        #else
        store.setAirPodsConnected(connectionMonitor.isConnected)
        #endif
    }

    private func requestAirPodsReadiness() {
        guard store.stage == .connection, !isPreparingAirPods else { return }
        readinessTask?.cancel()
        readinessTask = Task { @MainActor in
            isPreparingAirPods = true
            store.setAirPodsConnected(false)
            let isReady = await readinessService.prepareAirPods()
            guard !Task.isCancelled else {
                isPreparingAirPods = false
                return
            }
            store.setAirPodsConnected(isReady)
            isPreparingAirPods = false
        }
    }

    private func saveAndDismiss() {
        guard let profile = store.profile, !isSavingProfile else { return }
        let settings = PersonalizedChewDetectionSettings(
            minPeakAmplitude: profile.minPeakAmplitude,
            calibrationPeakCount: profile.calibrationAmplitudes.count,
            validationDetectedCount: profile.validationDetectedCount,
            calibratedAt: Date(),
            naturalChewInterval: profile.naturalChewInterval,
            calibrationAmplitudes: profile.calibrationAmplitudes,
            gateThresholds: profile.gateThresholds
        )
        isSavingProfile = true
        Task { @MainActor in
            defer { isSavingProfile = false }
            do {
                try await onSaved(settings)
                analyticsTracker.complete()
                dismiss()
            } catch {
                analyticsTracker.failSave()
                saveErrorMessage = (error as? RemoteStoreError)?.userMessage
                    ?? "잠시 후 다시 시도해 주세요."
            }
        }
    }
}
