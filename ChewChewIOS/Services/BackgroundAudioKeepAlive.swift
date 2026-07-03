import AVFoundation
import Foundation

/// 식사 세션 동안 오디오 세션을 유지하고, 씹기 페이스 피드백 톤을 재생한다.
/// 시뮬레이터에서는 하드웨어 백그라운드 수집 의미가 없어 노옵으로 둔다.
final class BackgroundAudioKeepAlive {

    // MARK: - Public state (플랫폼 공통)

    /// 톤 재생 볼륨(0.0~1.0). 세팅 즉시 재생 노드에 반영한다.
    var volume: Float = 0.5 {
        didSet { applyVolume() }
    }

    /// 씹기 페이스를 신호등 톤으로 분류하는 순수 함수(테스트 가능, 플랫폼 무관).
    ///
    /// `avgInterval`은 씹기 간격(초)이다. `ChewCounter`의 `minPeakGap`(32샘플=0.64초)이
    /// 간격 하한이므로 실측 간격은 0.64초 이상에서 움직인다. 그 위에서 상대적으로 짧으면(빨리 씹으면)
    /// 경고, 충분히 길면(천천히 씹으면) 적정으로 본다. 안 씹는 중이면 무음.
    /// 3초 지속 씹기 이벤트가 이미 들어온 상태에서 아직 평균 간격이 없으면 기본 적정 톤을 낸다.
    /// `fastThreshold` 기본 0.8초는 1차 값 — 실기기 튜닝 대상이다.
    static func toneKind(for pace: ChewPaceSample, fastThreshold: Double = 0.8) -> ChewToneKind {
        guard pace.isChewing else { return .none }
        guard pace.avgInterval > 0 else { return .good }
        return pace.avgInterval < fastThreshold ? .tooFast : .good
    }

    #if os(iOS) && !targetEnvironment(simulator)

    // MARK: - Private state

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let toneFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var toneBuffers: [ChewToneKind: AVAudioPCMBuffer] = [:]
    private var graphConfigured = false

    private let fastThreshold: Double = 0.8

    var isRunning: Bool { engine.isRunning }

    // MARK: - Lifecycle

    func start() {
        guard !engine.isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[KeepAlive] AVAudioSession 설정 실패: \(error)")
            return
        }

        prepareToneBuffersIfNeeded()
        configureGraphIfNeeded()

        do {
            try engine.start()
        } catch {
            print("[KeepAlive] AVAudioEngine 시작 실패: \(error)")
            return
        }
        player.play()
        applyVolume()
        subscribeInterruptionNotification()
        print("[KeepAlive] 신호등 톤 keep-alive 시작 (volume=\(volume))")
    }

    func stop() {
        unsubscribeInterruptionNotification()
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[KeepAlive] 신호등 톤 keep-alive 정지")
    }

    /// 3초 지속 씹기 이벤트가 들어왔을 때 현재 페이스에 맞는 신호등 톤을 한 번 낸다.
    func playTone(for pace: ChewPaceSample) {
        let kind = Self.toneKind(for: pace, fastThreshold: fastThreshold)
        print("[KeepAlive] sustained isChewing=\(pace.isChewing) avg=\(String(format: "%.2f", pace.avgInterval)) → \(kind)")
        playTone(kind)
    }

    // MARK: - Graph / tone synthesis

    /// 노드 attach/connect는 한 번만 — 재시작(stop→start) 때 중복 attach로 크래시하지 않게 가드한다.
    private func configureGraphIfNeeded() {
        guard !graphConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: toneFormat)
        graphConfigured = true
    }

    private func prepareToneBuffersIfNeeded() {
        guard toneBuffers.isEmpty else { return }
        // 적정=낮은 톤(부드러운 저음), 빠름=높은 경고 톤(짧게).
        toneBuffers[.good] = makeToneBuffer(frequency: 440, duration: 0.18)
        toneBuffers[.tooFast] = makeToneBuffer(frequency: 880, duration: 0.12)
    }

    /// 사인파 한 사이클 버퍼를 합성한다. 클릭음을 막으려 앞뒤 짧은 페이드 엔벨로프를 건다.
    /// 진폭은 0.9로 고정하고 실제 크기는 재생 시 `player.volume`(=서버 볼륨)으로만 조절한다.
    private func makeToneBuffer(frequency: Double, duration: Double) -> AVAudioPCMBuffer? {
        let sampleRate = toneFormat.sampleRate
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: toneFormat, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames

        let twoPiF = 2.0 * Double.pi * frequency
        let fadeFrames = max(1.0, min(Double(frames) / 4.0, 0.01 * sampleRate))
        for frame in 0..<Int(frames) {
            let pos = Double(frame)
            let envelope: Double
            if pos < fadeFrames {
                envelope = pos / fadeFrames
            } else if pos > Double(frames) - fadeFrames {
                envelope = (Double(frames) - pos) / fadeFrames
            } else {
                envelope = 1.0
            }
            channel[frame] = Float(sin(twoPiF * pos / sampleRate) * envelope * 0.9)
        }
        return buffer
    }

    private func applyVolume() {
        guard graphConfigured else { return }
        player.volume = max(0.0, min(1.0, volume))
    }

    /// 지정 신호등 톤을 한 번 재생한다. 재생 노드는 계속 playing 상태라 스케줄만 하면 즉시 난다.
    private func playTone(_ kind: ChewToneKind) {
        guard kind != .none, let buffer = toneBuffers[kind] else { return }
        applyVolume()
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        print("[KeepAlive] tone \(kind) scheduled vol=\(player.volume) engine=\(engine.isRunning) playing=\(player.isPlaying)")
    }

    // MARK: - Interruption (엔진 자체 회복용, 내부 전용)
    // 전화 등으로 세션이 인터럽트되면 톤 엔진도 멈춘다. keep-alive가 죽지 않도록 종료 시 스스로 되살린다.
    // 측정 정지·통화 갭 기록은 여기서 하지 않는다 — 그건 AppState의 CallInterruptionMonitor 경로 담당.

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

        switch type {
        case .began:
            player.pause()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard options.contains(.shouldResume) else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if !engine.isRunning { try engine.start() }
                player.play()
            } catch {
                print("[KeepAlive] 인터럽트 종료 후 세션 재활성화 실패: \(error)")
            }
        @unknown default:
            break
        }
    }

    #else

    // MARK: - Simulator stubs

    var isRunning: Bool { false }

    func start() {}
    func stop() {}
    func playTone(for pace: ChewPaceSample) {}
    private func applyVolume() {}

    #endif
}

/// 씹기 페이스 한 컷 — keep-alive가 톤을 고르는 데 필요한 최소 정보.
struct ChewPaceSample: Sendable, Equatable {
    /// 지금 씹는 중으로 판단되는지.
    let isChewing: Bool
    /// 평균 씹기 간격(초). 0이면 아직 간격 데이터 없음.
    let avgInterval: Double
}

/// 신호등 톤 종류. 색이 아니라 톤(높낮이)으로 상태를 구분한다.
enum ChewToneKind: Equatable {
    /// 소리 없음(안 씹는 중 / 데이터 부족).
    case none
    /// 적정 페이스 — 낮은 톤.
    case good
    /// 너무 빠름 — 경고(높은) 톤.
    case tooFast
}
