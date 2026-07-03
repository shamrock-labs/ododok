import AVFoundation
import Foundation

/// 오디오 에셋 없이 코드로 합성한 짧은 비프음을 재생한다.
///
/// 용도: 씹기가 3초 이상 지속 감지될 때마다 청각 피드백을 준다(`ChewCounter` 연동).
/// 사인파 PCM 버퍼를 메모리에서 직접 만들어 `AVAudioPlayerNode`로 재생하므로 번들 리소스가 필요 없다.
///
/// 오디오 세션:
/// - 식사 세션 중엔 `BackgroundAudioKeepAlive`가 이미 `.playback + .mixWithOthers`로 세션을 잡고 있다.
///   여기서도 같은 카테고리를 설정해 충돌 없이 공존한다(중복 설정은 무해).
/// - `stop()`에서 세션을 비활성화하지 않는다 — 세션 수명은 keep-alive가 소유한다.
final class ChewBeepPlayer {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var beepBuffer: AVAudioPCMBuffer?
    private var isPrepared = false

    // 비프 파라미터 — 880Hz(A5) 0.18초. 어택/릴리즈 램프로 클릭 노이즈를 없앤다.
    private let toneFrequency = 880.0
    private let toneDuration = 0.18
    private let toneAmplitude: Float = 0.4
    private let attackDuration = 0.01
    private let releaseDuration = 0.08

    /// 엔진 그래프 구성 + 버퍼 합성 + 엔진 시작. 식사 세션 시작 시 1회 호출.
    func prepare() {
        guard !isPrepared else { return }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[ChewBeep] AVAudioSession 설정 실패: \(error)")
        }
        #endif

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = makeBeepBuffer(format: format) else {
            print("[ChewBeep] 비프 버퍼 생성 실패")
            return
        }
        beepBuffer = buffer

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
            player.play()
            isPrepared = true
        } catch {
            print("[ChewBeep] AVAudioEngine 시작 실패: \(error)")
        }
    }

    /// 비프 1회 재생. prepare 전이거나 엔진이 죽어 있으면 노옵.
    func play() {
        guard isPrepared, let beepBuffer, engine.isRunning else { return }
        player.scheduleBuffer(beepBuffer, at: nil)
    }

    /// 엔진 정지 + 상태 해제. 식사 세션 종료 시 호출.
    /// 오디오 세션 deactivate는 하지 않는다(keep-alive가 소유).
    func stop() {
        guard isPrepared else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        beepBuffer = nil
        isPrepared = false
    }

    /// 사인파 + 어택/릴리즈 선형 램프를 입힌 mono PCM 버퍼를 합성한다.
    private func makeBeepBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * toneDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let attackFrames = Int(sampleRate * attackDuration)
        let releaseFrames = Int(sampleRate * releaseDuration)
        let totalFrames = Int(frameCount)

        for frame in 0..<totalFrames {
            let phase = 2.0 * Double.pi * toneFrequency * Double(frame) / sampleRate
            var envelope: Float = 1.0
            if frame < attackFrames {
                envelope = Float(frame) / Float(max(1, attackFrames))
            } else if frame >= totalFrames - releaseFrames {
                envelope = Float(totalFrames - frame) / Float(max(1, releaseFrames))
            }
            channel[frame] = Float(sin(phase)) * toneAmplitude * envelope
        }
        return buffer
    }
}
