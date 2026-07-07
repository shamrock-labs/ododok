import Foundation

/// AirPods 연결 감지, 카운트다운, 연결 해제 시 팝업 복귀를 묶는 Feature coordinator.
final class AirPodsAutoStartCoordinator {
    var onPromptVisibilityChange: ((Bool) -> Void)?
    var onCountdownValueChange: ((Int?) -> Void)? {
        didSet {
            countdown.onValueChange = { [weak self] value in
                self?.onCountdownValueChange?(value)
            }
        }
    }

    private let monitor: AirPodsConnectionMonitor
    private let countdown: StartCountdownController

    init(
        monitor: AirPodsConnectionMonitor = AirPodsConnectionMonitor(),
        countdown: StartCountdownController = StartCountdownController()
    ) {
        self.monitor = monitor
        self.countdown = countdown
    }

    var isHeadphoneConnected: Bool {
        monitor.isConnected
    }

    func waitForConnectionThenStart(onFinished: @escaping () -> Void) {
        onPromptVisibilityChange?(true)
        startMonitoring(onFinished: onFinished)
        if monitor.isConnected {
            onPromptVisibilityChange?(false)
            beginCountdown(onFinished: onFinished)
        }
    }

    func startCountdownWithDisconnectMonitoring(onFinished: @escaping () -> Void) {
        onPromptVisibilityChange?(false)
        startMonitoring(onFinished: onFinished)
        beginCountdown(onFinished: onFinished)
    }

    func dismissPromptAndStop() {
        onPromptVisibilityChange?(false)
        countdown.cancel()
        monitor.stop()
    }

    private func startMonitoring(onFinished: @escaping () -> Void) {
        monitor.start { [weak self] connected in
            guard let self else { return }
            if connected {
                self.onPromptVisibilityChange?(false)
                self.beginCountdown(onFinished: onFinished)
            } else if self.countdown.isRunning {
                self.countdown.cancel()
                self.onPromptVisibilityChange?(true)
            }
        }
    }

    private func beginCountdown(onFinished: @escaping () -> Void) {
        countdown.begin { [weak self] in
            self?.monitor.stop()
            onFinished()
        }
    }
}
