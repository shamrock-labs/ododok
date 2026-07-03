import AVFoundation
import Foundation

/// 식사 세션용 오디오 피드백 엔진.
///
/// iOS 실기기에서는 `.playback + .mixWithOthers` 오디오 세션을 열어 백그라운드에서도
/// AirPods IMU 수집이 끊기지 않게 하고, 3초 지속 씹기 이벤트마다 현재 페이스에 맞는
/// 짧은 톤을 낸다. 시뮬레이터에서는 하드웨어 수집 의미가 없어 lifecycle API를 노옵으로 둔다.
final class BackgroundAudioKeepAlive {

    // MARK: - Public state (플랫폼 공통)

    var volume: Float = 0.5 {
        didSet {
            volume = max(0.0, min(1.0, volume))
            applyVolume()
        }
    }

    /// 플랫폼과 무관한 페이스→톤 분류. `avgInterval`은 씹기 간격(초)이며 0이면 기본 톤으로 폴백한다.
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
        #if DEBUG
        print("[KeepAlive] 신호등 톤 keep-alive 시작 (volume=\(volume))")
        #endif
    }

    func stop() {
        unsubscribeInterruptionNotification()
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #if DEBUG
        print("[KeepAlive] 신호등 톤 keep-alive 정지")
        #endif
    }

    func playTone(for pace: ChewPaceSample) {
        let kind = Self.toneKind(for: pace, fastThreshold: fastThreshold)
        #if DEBUG
        print("[KeepAlive] sustained isChewing=\(pace.isChewing) avg=\(String(format: "%.2f", pace.avgInterval)) → \(kind)")
        #endif
        playTone(kind)
    }

    // MARK: - Graph / tone synthesis

    private func configureGraphIfNeeded() {
        guard !graphConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: toneFormat)
        graphConfigured = true
    }

    private func prepareToneBuffersIfNeeded() {
        guard toneBuffers.isEmpty else { return }
        toneBuffers[.good] = makeToneBuffer(frequency: 440, duration: 0.18)
        toneBuffers[.tooFast] = makeToneBuffer(frequency: 880, duration: 0.12)
    }

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

    private func playTone(_ kind: ChewToneKind) {
        guard kind != .none, let buffer = toneBuffers[kind] else { return }
        applyVolume()
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        #if DEBUG
        print("[KeepAlive] tone \(kind) scheduled vol=\(player.volume) engine=\(engine.isRunning) playing=\(player.isPlaying)")
        #endif
    }

    // MARK: - Interruption

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

/// 톤 분류에 필요한 씹기 페이스 스냅샷.
struct ChewPaceSample: Sendable, Equatable {
    let isChewing: Bool
    let avgInterval: Double
}

/// 씹기 페이스 피드백 톤.
enum ChewToneKind: Equatable {
    case none
    case good
    case tooFast
}
