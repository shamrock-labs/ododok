import AVFoundation
import Foundation

/// 식사 세션 동안 백그라운드에서도 AirPods IMU 콜백이 끊기지 않도록,
/// `AVAudioEngine`으로 무음 PCM 버퍼를 루프 재생해 앱이 suspend 되지 않게 잡아둔다.
///
/// 원리:
/// - `AVAudioSession`만 active 상태로 두면 iOS는 몇 초 뒤 앱을 suspend → `CMHeadphoneMotionManager`
///   콜백이 끊긴다.
/// - 실제로 무음 버퍼를 재생해야 "오디오 재생 중인 앱"으로 분류되어 백그라운드에서도 살아있는다.
/// - 카테고리는 `.playback` + `.mixWithOthers`로 설정해 유튜브/스포티파이 등 외부 오디오를 끊지 않음.
/// - `outputVolume = 0.0`이라 실제로는 완전 무음.
///
/// chewing-imu-collector(`ChewingIMUCollectorApp.swift`)의 `BackgroundAudioKeepAlive`를 이식.
/// 차이점:
///   1. 앱 시작 시 상시가 아닌, 식사 세션 동안에만 `start()` / `stop()`. 배터리 + App Store 정책 리스크 완화.
///   2. 시뮬레이터에선 `start()` 노옵 — CMHeadphoneMotion 자체가 없어 keep-alive 의미가 없고,
///      불필요한 오디오 세션 활성화로 다른 소리(예: 시스템 사운드)를 잡지 않도록.
final class BackgroundAudioKeepAlive {
    #if os(iOS) && !targetEnvironment(simulator)
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    var isRunning: Bool { engine?.isRunning == true }
    #else
    var isRunning: Bool { false }
    #endif

    func start() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard !isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[BG-TEST] AVAudioSession 설정 실패: \(error)")
            return
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            print("[BG-TEST] AVAudioFormat 생성 실패")
            return
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.0

        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[BG-TEST] AVAudioPCMBuffer 생성 실패")
            return
        }
        buffer.frameLength = frameCount

        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            self.engine = engine
            self.player = player
            print("[BG-TEST] 무음 오디오 엔진 시작 완료")
        } catch {
            print("[BG-TEST] AudioEngine 시작 실패: \(error)")
        }
        #endif
    }

    func stop() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let engine else { return }
        player?.stop()
        engine.stop()
        self.player = nil
        self.engine = nil
        // 오디오 세션 비활성화 — 다른 앱이 카테고리를 되찾을 수 있도록.
        // notifyOthersOnDeactivation: 멈춰있던 외부 오디오가 자동 복귀하게 안내.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[BG-TEST] 무음 오디오 엔진 정지")
        #endif
    }
}
