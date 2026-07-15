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

    private let store = UserDefaultsChewProfileStore()

    var body: some View {
        VStack(spacing: AppSpacing.none) {
            if settings == nil {
                setupButton
            } else {
                ChewDetectionPersonalizationSettingsRow(isPersonalized: true)
                    .padding(.top, AppSpacing.topInsetCompact)

                diagnosticsButton
            }
        }
        .fullScreenCover(isPresented: $isPersonalizationPresented) {
            MeasurementPersonalizationFlow(
                personalizationStore: store,
                remoteStore: state.remoteStore
            ) { updatedSettings in
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

    private var diagnosticsButton: some View {
        Button {
            isDiagnosticsPresented = true
        } label: {
            Label("측정값 보기", systemImage: "waveform.path.ecg")
        }
        .buttonStyle(.plain)
        .font(.appFont(.semiboldCallout))
        .foregroundStyle(Color.textAction)
        .padding(.top, AppSpacing.gap)
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
