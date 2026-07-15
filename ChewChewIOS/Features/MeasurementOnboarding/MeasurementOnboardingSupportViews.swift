import SwiftUI
import UIKit

struct MeasurementDiagnosticsSharePresenter: UIViewControllerRepresentable {
    @Binding var items: [URL]

    func makeCoordinator() -> Coordinator {
        Coordinator(items: $items)
    }

    func makeUIViewController(context _: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.present(items: items, from: controller)
    }

    @MainActor
    final class Coordinator {
        private let itemsBinding: Binding<[URL]>
        private var isPresenting = false

        init(items: Binding<[URL]>) {
            itemsBinding = items
        }

        func present(items: [URL], from host: UIViewController) {
            guard !items.isEmpty, !isPresenting else { return }
            isPresenting = true

            Task { @MainActor in
                guard host.viewIfLoaded?.window != nil else {
                    isPresenting = false
                    return
                }

                let controller = UIActivityViewController(
                    activityItems: items,
                    applicationActivities: nil
                )
                configurePopover(for: controller, host: host)
                controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
                    Task { @MainActor in
                        self?.itemsBinding.wrappedValue = []
                        self?.isPresenting = false
                    }
                }
                host.present(controller, animated: true)
            }
        }

        private func configurePopover(for controller: UIActivityViewController, host: UIViewController) {
            controller.popoverPresentationController?.sourceView = host.view
            controller.popoverPresentationController?.sourceRect = CGRect(
                x: host.view.bounds.midX,
                y: host.view.bounds.midY,
                width: 1,
                height: 1
            )
        }
    }
}

#if DEBUG
struct MeasurementOnboardingPreviewHost: View {
    @State private var store: MeasurementOnboardingStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let stage: MeasurementOnboardingStore.Stage
        if let index = arguments.firstIndex(of: "-measurementOnboardingStage"),
           index + 1 < arguments.count,
           let requestedStage = MeasurementOnboardingStore.Stage(rawValue: arguments[index + 1]) {
            stage = requestedStage
        } else {
            stage = .intro
        }
        #if targetEnvironment(simulator)
        let sampler: any MeasurementCalibrationSampling = SimulatedMeasurementCalibrationSampler()
        #else
        let sampler: any MeasurementCalibrationSampling = LocalMeasurementCalibrationSampler()
        #endif
        _store = State(initialValue: MeasurementOnboardingStore.preview(
            stage: stage,
            sampler: sampler
        ))
    }

    var body: some View {
        MeasurementOnboardingView(
            store: store,
            onComplete: {},
            onSkip: {},
            onRetryConnection: { store.setAirPodsConnected(true) }
        )
        .task {
            if store.stage == .baseline || store.stage == .calibration || store.stage == .adjustment {
                store.startMeasurement()
            }
        }
    }
}
#endif
