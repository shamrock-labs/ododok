import AVFoundation
import Foundation

/// 식사 세션 동안 백그라운드에서도 AirPods IMU 콜백이 끊기지 않도록,
/// 번들의 `ambient_loop.m4a`(저진폭 brown noise)를 루프 재생해 앱이 suspend 되지 않게 잡아둔다.
///
/// 원리:
/// - `AVAudioSession`만 active 상태로 두면 iOS는 몇 초 뒤 앱을 suspend → `CMHeadphoneMotionManager`
///   콜백이 끊긴다.
/// - 실제로 오디오 파일을 재생해야 "오디오 재생 중인 앱"으로 분류되어 백그라운드에서도 살아있는다.
/// - 카테고리는 `.playback` + `.mixWithOthers`로 설정해 유튜브/스포티파이 등 외부 오디오를 끊지 않음.
/// - 재생 볼륨은 `keepAliveVolume`(기본 0.03)으로 매우 낮지만 0보다 크게 유지해
///   App Store 2.5.4 완전무음 재생 금지 정책을 준수한다.
///
/// 전화 인터럽트 대응:
/// - `handleInterruption(type:options:)` — 테스트 가능하도록 순수 메서드로 분리.
///   `.began` 시 플레이어를 pause, `.ended + .shouldResume` 시 resume.
/// - `onInterrupt` 콜백으로 AppState가 IMU 루프 pause/resume 여부를 결정한다.
///
/// 시뮬레이터에선 `start()` 노옵 — CMHeadphoneMotion 자체가 없어 keep-alive 의미가 없고,
/// 불필요한 오디오 세션 활성화로 다른 소리를 잡지 않도록.
final class BackgroundAudioKeepAlive {

    // MARK: - Public state

    /// 재생 볼륨. 0보다 크게 유지해 App Store 정책 준수.
    let keepAliveVolume: Float = 0.03

    #if os(iOS) && !targetEnvironment(simulator)

    // MARK: - Private state

    private var audioPlayer: AVAudioPlayer?

    /// `.began` 인터럽트가 왔을 때 저장해두는 시작 시각 — 갭 기록용.
    private(set) var interruptionBeganAt: Date?

    /// `.began` → IMU stop / `.ended + shouldResume` → IMU resume 을 AppState에 위임.
    /// 인수: (shouldResume: Bool) — true면 재개, false면 중단 유지.
    var onInterrupt: ((Bool) -> Void)?

    var isRunning: Bool { audioPlayer?.isPlaying == true }

    /// 통화(CXCallObserver) 감지처럼 오디오 인터럽트 없이 측정만 멈출 때 중단 시각을 기록한다.
    /// `.mixWithOthers` 세션은 통화에 인터럽트를 안 받아 `interruptionBeganAt`이 안 잡히므로,
    /// AppState가 통화 감지 시 이걸 호출해 "계속하기" 때 통화 구간이 갭으로 빠지게 한다.
    /// 이미 인터럽트 진행 중이면(began 설정됨) 덮어쓰지 않는다.
    func markInterruptionBegan() {
        if interruptionBeganAt == nil { interruptionBeganAt = Date() }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[KeepAlive] AVAudioSession 설정 실패: \(error)")
            return
        }

        guard let url = Bundle.main.url(forResource: "ambient_loop", withExtension: "m4a") else {
            print("[KeepAlive] ambient_loop.m4a 번들 누락")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = keepAliveVolume
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            subscribeInterruptionNotification()
            print("[KeepAlive] ambient 루프 시작 (volume=\(keepAliveVolume))")
        } catch {
            print("[KeepAlive] AVAudioPlayer 생성 실패: \(error)")
        }
    }

    func stop() {
        unsubscribeInterruptionNotification()
        audioPlayer?.stop()
        audioPlayer = nil
        interruptionBeganAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[KeepAlive] ambient 루프 정지")
    }

    // MARK: - Mute

    /// ambient만 멈추고 `AVAudioSession`은 active 유지 (세션 유효 = IMU 콜백 유지).
    func setMuted(_ muted: Bool) {
        if muted {
            audioPlayer?.pause()
        } else {
            audioPlayer?.play()
        }
    }

    // MARK: - Resume

    /// 인터럽트(전화 등)로 일시정지된 ambient 재생을 사용자 동작으로 다시 켠다.
    /// 세션을 active로 되돌린 뒤 기존 플레이어를 재생 — `start()`를 다시 부르면
    /// 인터럽션 옵저버가 중복 등록되므로, 살아있는 플레이어가 있으면 재생만 한다.
    /// 플레이어가 사라졌으면(앱 종료 후 복귀 등) `start()`로 폴백.
    func resume() {
        guard let audioPlayer else {
            start()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[KeepAlive] resume 세션 재활성화 실패: \(error)")
        }
        audioPlayer.play()
        interruptionBeganAt = nil
        print("[KeepAlive] ambient 재개")
    }

    // MARK: - Interruption (테스트 가능하게 분리)

    /// 인터럽트 처리 진입점. `AVAudioSession.interruptionNotification` 핸들러와
    /// 단위테스트 양쪽에서 직접 호출 가능.
    func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            interruptionBeganAt = Date()
            audioPlayer?.pause()
            onInterrupt?(false)

        case .ended:
            let shouldResume = options.contains(.shouldResume)
            if shouldResume {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("[KeepAlive] 인터럽트 종료 후 세션 재활성화 실패: \(error)")
                }
                audioPlayer?.play()
            }
            onInterrupt?(shouldResume)

        @unknown default:
            break
        }
    }

    // MARK: - Notification subscription

    private func subscribeInterruptionNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func unsubscribeInterruptionNotification() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruptionNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        handleInterruption(type: type, options: options)
    }

    #else

    // MARK: - Simulator stubs

    var isRunning: Bool { false }
    var onInterrupt: ((Bool) -> Void)?

    func start() {}
    func stop() {}
    func setMuted(_ muted: Bool) {}
    func resume() {}
    func markInterruptionBegan() {}
    func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {}

    #endif
}
