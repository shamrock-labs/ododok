import SwiftUI

struct ChewPersonalizationSettingsControls: View {
    private enum PendingDiagnosticsAction {
        case remeasure
        case reset
    }

    @Environment(AppState.self) private var state
    @Binding var settings: PersonalizedChewDetectionSettings?

    let onResetRequested: () -> Void

    @State private var isPersonalizationPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var pendingDiagnosticsAction: PendingDiagnosticsAction?

    var body: some View {
        VStack(spacing: AppSpacing.none) {
            if settings == nil {
                setupButton
            } else {
                detailsButton
            }
        }
        .fullScreenCover(isPresented: $isPersonalizationPresented) {
            MeasurementPersonalizationFlow(
                source: .settings,
                analytics: state.analytics,
                remoteStore: state.remoteStore
            ) { updatedSettings in
                try await state.saveChewDetectionSettings(updatedSettings)
                settings = updatedSettings
            }
        }
        .sheet(
            isPresented: $isDiagnosticsPresented,
            onDismiss: performPendingDiagnosticsAction
        ) {
            if let settings {
                ChewPersonalizationDiagnosticsView(
                    settings: settings,
                    showsInternalValues: AppFeatureFlags.showsCalibrationDiagnostics,
                    onRemeasure: { pendingDiagnosticsAction = .remeasure },
                    onReset: { pendingDiagnosticsAction = .reset }
                )
            }
        }
    }

    private var setupButton: some View {
        Button {
            isPersonalizationPresented = true
        } label: {
            ChewDetectionPersonalizationSettingsRow(isPersonalized: false)
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.topInsetCompact)
        .accessibilityIdentifier("ChewDetectionPersonalization")
    }

    private var detailsButton: some View {
        Button {
            isDiagnosticsPresented = true
        } label: {
            ChewDetectionPersonalizationSettingsRow(isPersonalized: true)
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.topInsetCompact)
        .accessibilityIdentifier("ChewDetectionPersonalizationDetails")
    }

    private func performPendingDiagnosticsAction() {
        defer { pendingDiagnosticsAction = nil }
        switch pendingDiagnosticsAction {
        case .remeasure:
            isPersonalizationPresented = true
        case .reset:
            onResetRequested()
        case nil:
            break
        }
    }
}
