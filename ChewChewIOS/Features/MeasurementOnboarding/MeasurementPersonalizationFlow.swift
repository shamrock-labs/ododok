import SwiftUI

struct MeasurementPersonalizationFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var store: MeasurementOnboardingStore
    @State private var connectionMonitor: AirPodsConnectionMonitor
    @State private var isPreparingAirPods = false
    @State private var readinessTask: Task<Void, Never>?

    private let personalizationStore: any ChewDetectionPersonalizationStoring
    private let readinessService: any AirPodsAudioReadinessServicing
    private let artifactUploader: any MeasurementCalibrationArtifactUploading
    private let onSaved: (PersonalizedChewDetectionSettings) -> Void

    init(
        personalizationStore: any ChewDetectionPersonalizationStoring = UserDefaultsChewProfileStore(),
        remoteStore: any RemoteStore = NoopRemoteStore(),
        readinessService: (any AirPodsAudioReadinessServicing)? = nil,
        onSaved: @escaping (PersonalizedChewDetectionSettings) -> Void
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
        _store = State(initialValue: MeasurementOnboardingStore(
            isAirPodsConnected: isConnected,
            sampler: sampler,
            artifactUploader: artifactUploader,
            cuePlayer: audioReadinessService
        ))
        self.personalizationStore = personalizationStore
        self.readinessService = audioReadinessService
        self.artifactUploader = artifactUploader
        self.onSaved = onSaved
    }

    var body: some View {
        MeasurementOnboardingView(
            store: store,
            onComplete: saveAndDismiss,
            onSkip: { dismiss() },
            onRetryConnection: requestAirPodsReadiness,
            skipTitle: "닫기",
            isPreparingAirPods: isPreparingAirPods
        )
        .onAppear {
            refreshConnection()
            connectionMonitor.start { connected in
                Task { @MainActor in store.setAirPodsConnected(connected) }
            }
        }
        .task {
            await artifactUploader.retryPending()
        }
        .onDisappear {
            readinessTask?.cancel()
            readinessService.stop()
            connectionMonitor.stop()
        }
        .onChange(of: store.stage) { _, stage in
            if stage == .connection {
                requestAirPodsReadiness()
            }
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
            guard !Task.isCancelled else { return }
            store.setAirPodsConnected(isReady)
            isPreparingAirPods = false
        }
    }

    private func saveAndDismiss() {
        guard let profile = store.profile else { return }
        let settings = PersonalizedChewDetectionSettings(
            minPeakAmplitude: profile.minPeakAmplitude,
            calibrationPeakCount: profile.calibrationAmplitudes.count,
            validationDetectedCount: profile.validationDetectedCount,
            calibratedAt: Date(),
            naturalChewInterval: profile.naturalChewInterval,
            calibrationAmplitudes: profile.calibrationAmplitudes,
            gateThresholds: profile.gateThresholds
        )
        personalizationStore.save(settings)
        onSaved(settings)
        dismiss()
    }
}
