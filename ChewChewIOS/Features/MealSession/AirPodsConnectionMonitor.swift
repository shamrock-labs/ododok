import AVFoundation
import Foundation

protocol AirPodsConnectionMonitoring: AnyObject {
    var isConnected: Bool { get }
    func start(onRouteConnectionChanged: @escaping (Bool) -> Void)
    func stop()
}

/// AVAudioSession 라우트 변경을 관찰하는 Feature 전용 외부 효과 어댑터.
final class AirPodsConnectionMonitor: AirPodsConnectionMonitoring {
    private let notificationCenter: NotificationCenter
    private let currentOutputs: () -> [AVAudioSessionPortDescription]
    private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        currentOutputs: @escaping () -> [AVAudioSessionPortDescription] = {
            AVAudioSession.sharedInstance().currentRoute.outputs
        }
    ) {
        self.notificationCenter = notificationCenter
        self.currentOutputs = currentOutputs
    }

    var isConnected: Bool {
        AirPodsRouteDetector.hasHeadphoneAudioRoute(outputs: currentOutputs())
    }

    func start(onRouteConnectionChanged: @escaping (Bool) -> Void) {
        stop()
        observer = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                onRouteConnectionChanged(self.isConnected)
            }
        }
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }
}
