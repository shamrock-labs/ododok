import AVFoundation
import Foundation

@MainActor
protocol MeasurementCuePlaying: AnyObject {
    func playCalibrationCue()
}

@MainActor
protocol AirPodsAudioReadinessServicing: MeasurementCuePlaying {
    func prepareAirPods() async -> Bool
    func stop()
}

@MainActor
final class AirPodsAudioReadinessService: AirPodsAudioReadinessServicing {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private let hasHeadphoneRoute: () -> Bool
    private var graphConfigured = false

    init(
        hasHeadphoneRoute: @escaping () -> Bool = {
            AirPodsRouteDetector.hasHeadphoneAudioRoute(
                outputs: AVAudioSession.sharedInstance().currentRoute.outputs
            )
        }
    ) {
        self.hasHeadphoneRoute = hasHeadphoneRoute
    }

    func prepareAirPods() async -> Bool {
        stopEngine(deactivateSession: false)
        guard let format,
              let transferCue = makeTransferCue(format: format),
              let readyCue = makeReadyCue(format: format) else {
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            configureGraphIfNeeded(format: format)
            try engine.start()
            player.play()

            if !hasHeadphoneRoute() {
                await player.scheduleBuffer(transferCue)
            }

            guard await waitForHeadphoneRoute() else {
                stop()
                return false
            }

            await player.scheduleBuffer(readyCue)
            return true
        } catch {
            stop()
            return false
        }
    }

    func stop() {
        stopEngine(deactivateSession: true)
    }

    func playCalibrationCue() {
        guard engine.isRunning,
              let format,
              let cue = makeCalibrationCue(format: format) else { return }
        player.scheduleBuffer(cue, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }

    private func configureGraphIfNeeded(format: AVAudioFormat) {
        guard !graphConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        graphConfigured = true
    }

    private func waitForHeadphoneRoute() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))

        while !hasHeadphoneRoute(), clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return hasHeadphoneRoute()
    }

    private func makeTransferCue(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeCue(format: format, segments: [
            .tone(frequency: 392, duration: 0.14, amplitude: 0.07),
        ])
    }

    private func makeReadyCue(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeCue(format: format, segments: [
            .tone(frequency: 523.25, duration: 0.14, amplitude: 0.22),
            .silence(duration: 0.04),
            .tone(frequency: 659.25, duration: 0.16, amplitude: 0.22),
        ])
    }

    private func makeCalibrationCue(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeCue(format: format, segments: [
            .tone(frequency: 784, duration: 0.08, amplitude: 0.16),
        ])
    }

    private func makeCue(format: AVAudioFormat, segments: [CueSegment]) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = segments.reduce(0) { partial, segment in
            partial + Int(sampleRate * segment.duration)
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let samples = buffer.floatChannelData?[0] else { return nil }
        var offset = 0
        for segment in segments {
            let segmentFrameCount = Int(sampleRate * segment.duration)
            for frame in 0..<segmentFrameCount {
                samples[offset + frame] = segment.sample(at: frame, sampleRate: sampleRate)
            }
            offset += segmentFrameCount
        }
        return buffer
    }

    private func stopEngine(deactivateSession: Bool) {
        player.stop()
        engine.stop()
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

private struct CueSegment {
    let frequency: Double?
    let duration: Double
    let amplitude: Float

    static func tone(frequency: Double, duration: Double, amplitude: Float) -> CueSegment {
        CueSegment(frequency: frequency, duration: duration, amplitude: amplitude)
    }

    static func silence(duration: Double) -> CueSegment {
        CueSegment(frequency: nil, duration: duration, amplitude: 0)
    }

    func sample(at frame: Int, sampleRate: Double) -> Float {
        guard let frequency else { return 0 }
        let frameCount = max(Int(sampleRate * duration), 1)
        let attackFrames = max(Int(sampleRate * 0.02), 1)
        let releaseFrames = max(Int(sampleRate * 0.08), 1)
        let attack = min(Float(frame) / Float(attackFrames), 1)
        let release = min(Float(frameCount - frame) / Float(releaseFrames), 1)
        let envelope = min(attack, release)
        let phase = 2 * Double.pi * frequency * Double(frame) / sampleRate
        return Float(sin(phase)) * amplitude * envelope
    }
}

#if DEBUG
@MainActor
final class SimulatedAirPodsAudioReadinessService: AirPodsAudioReadinessServicing {
    func prepareAirPods() async -> Bool {
        try? await Task.sleep(for: .milliseconds(350))
        return !Task.isCancelled
    }

    func playCalibrationCue() {}

    func stop() {}
}
#endif
