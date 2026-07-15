import SwiftUI

struct ChewPersonalizationSettingsControls: View {
    private enum PendingDiagnosticsAction {
        case remeasure
        case reset
    }

    @Environment(AppState.self) private var state
    @State private var isPersonalizationPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var isResetConfirmationPresented = false
    @State private var pendingDiagnosticsAction: PendingDiagnosticsAction?
    @State private var settings = UserDefaultsChewProfileStore().load()

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
        .appDialog(
            isPresented: $isResetConfirmationPresented,
            title: "기본 감지 기준으로 돌아갈까요?",
            message: "저장된 맞춤 기준을 지우고 다음 식사부터 기본 기준으로 감지해요.",
            primary: .init("기본값 사용", role: .destructive) {
                store.clear()
                settings = nil
            },
            secondary: .init("취소", role: .cancel) {}
        )
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
            isResetConfirmationPresented = true
        case nil:
            break
        }
    }
}
