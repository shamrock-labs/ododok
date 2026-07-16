import Foundation

/// AirPods 연결 감지, 카운트다운, 연결 해제 시 팝업 복귀를 묶는 Feature coordinator.
@MainActor
final class AirPodsAutoStartCoordinator {
    var onPromptVisibilityChange: ((Bool) -> Void)?
    var onPreparationChange: ((Bool) -> Void)?
    var onCountdownValueChange: ((Int?) -> Void)? {
        didSet {
            countdown.onValueChange = { [weak self] value in
                self?.onCountdownValueChange?(value)
            }
        }
    }

    private let monitor: AirPodsConnectionMonitoring
    private let countdown: StartCountdownController
    private let readinessService: any AirPodsAudioReadinessServicing
    private var readinessTask: Task<Void, Never>?
    private var promptDelayTask: Task<Void, Never>?
    private var isPreparing = false

    init(
        monitor: AirPodsConnectionMonitoring = AirPodsConnectionMonitor(),
        countdown: StartCountdownController = StartCountdownController(),
        readinessService: any AirPodsAudioReadinessServicing
    ) {
        self.monitor = monitor
        self.countdown = countdown
        self.readinessService = readinessService
    }

    var isHeadphoneConnected: Bool {
        monitor.isConnected
    }

    func prepareRoute(onReady: @escaping () -> Void) {
        guard !isPreparing else { return }
        setPreparing(true)
        promptDelayTask = Task { @MainActor [weak self] in
            // 1초 안에 경로가 잡히는 보통 케이스에선 준비 다이얼로그를 아예 안 보여준다.
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            self?.onPromptVisibilityChange?(true)
        }
        readinessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let isReady = await readinessService.prepareAirPods()
            guard !Task.isCancelled else { return }
            readinessTask = nil
            promptDelayTask?.cancel()
            promptDelayTask = nil

            guard isReady else {
                setPreparing(false)
                waitForConnection(onReady: onReady)
                return
            }
            onReady()
        }
    }

    func startCountdown(onStarted: @escaping () -> Void, onFinished: @escaping () -> Void) {
        startMonitoringDuringCountdown(onFinished: onFinished)
        onPromptVisibilityChange?(false)
        onStarted()
        beginCountdown(onFinished: onFinished)
    }

    func dismissPromptAndStop() {
        readinessTask?.cancel()
        readinessTask = nil
        promptDelayTask?.cancel()
        promptDelayTask = nil
        readinessService.stop()
        setPreparing(false)
        onPromptVisibilityChange?(false)
        countdown.cancel()
        monitor.stop()
    }

    private func waitForConnection(onReady: @escaping () -> Void) {
        readinessService.stop()
        onPromptVisibilityChange?(true)
        monitor.start { [weak self] connected in
            guard let self, connected else { return }
            monitor.stop()
            onPromptVisibilityChange?(false)
            onReady()
        }
    }

    private func startMonitoringDuringCountdown(onFinished: @escaping () -> Void) {
        monitor.start { [weak self] connected in
            guard let self else { return }
            guard !connected, countdown.isRunning else { return }
            countdown.cancel()
            readinessService.stop()
            setPreparing(false)
            onPromptVisibilityChange?(true)
        }
    }

    private func beginCountdown(onFinished: @escaping () -> Void) {
        countdown.begin { [weak self] in
            self?.monitor.stop()
            self?.finishPreparation(onFinished: onFinished)
        }
    }

    private func finishPreparation(onFinished: @escaping () -> Void) {
        setPreparing(false)
        // 곧바로 측정 keep-alive가 같은 오디오 세션을 이어받는다. 여기서 세션을 내리면
        // 비활성화→재활성화 왕복이 생겨 다른 앱 오디오(유튜브 등)가 무음이 된다.
        readinessService.stop(deactivatingSession: false)
        onFinished()
    }

    private func setPreparing(_ preparing: Bool) {
        isPreparing = preparing
        onPreparationChange?(preparing)
    }
}
