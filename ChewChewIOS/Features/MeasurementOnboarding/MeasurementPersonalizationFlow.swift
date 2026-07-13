import SwiftUI

struct MeasurementPersonalizationFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var store: MeasurementOnboardingStore
    @State private var connectionMonitor: AirPodsConnectionMonitor

    private let personalizationStore: any ChewDetectionPersonalizationStoring
    private let onSaved: (PersonalizedChewDetectionSettings) -> Void

    init(
        personalizationStore: any ChewDetectionPersonalizationStoring = UserDefaultsChewProfileStore(),
        onSaved: @escaping (PersonalizedChewDetectionSettings) -> Void
    ) {
        let connectionMonitor = AirPodsConnectionMonitor()
        #if DEBUG && targetEnvironment(simulator)
        let sampler: any MeasurementCalibrationSampling = SimulatedMeasurementCalibrationSampler()
        let isConnected = true
        #else
        let sampler: any MeasurementCalibrationSampling = LocalMeasurementCalibrationSampler()
        let isConnected = connectionMonitor.isConnected
        #endif

        _connectionMonitor = State(initialValue: connectionMonitor)
        _store = State(initialValue: MeasurementOnboardingStore(
            isAirPodsConnected: isConnected,
            sampler: sampler
        ))
        self.personalizationStore = personalizationStore
        self.onSaved = onSaved
    }

    var body: some View {
        MeasurementOnboardingView(
            store: store,
            onComplete: saveAndDismiss,
            onSkip: { dismiss() },
            onRetryConnection: refreshConnection,
            skipTitle: "닫기"
        )
        .onAppear {
            refreshConnection()
            connectionMonitor.start { connected in
                Task { @MainActor in store.setAirPodsConnected(connected) }
            }
        }
        .onDisappear {
            connectionMonitor.stop()
        }
    }

    private func refreshConnection() {
        #if DEBUG && targetEnvironment(simulator)
        store.setAirPodsConnected(true)
        #else
        store.setAirPodsConnected(connectionMonitor.isConnected)
        #endif
    }

    private func saveAndDismiss() {
        guard let profile = store.profile else { return }
        let settings = PersonalizedChewDetectionSettings(
            minPeakAmplitude: profile.minPeakAmplitude,
            calibrationPeakCount: profile.calibrationAmplitudes.count,
            validationDetectedCount: profile.validationDetectedCount,
            calibratedAt: Date()
        )
        personalizationStore.save(settings)
        onSaved(settings)
        dismiss()
    }
}
