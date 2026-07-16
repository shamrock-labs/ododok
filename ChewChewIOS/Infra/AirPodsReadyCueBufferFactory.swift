import AVFoundation

enum AirPodsReadyCueBufferFactory {
    static func make(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let segments: [Segment] = [
            .tone(frequency: 523.25, duration: 0.14, amplitude: 0.22),
            .silence(duration: 0.04),
            .tone(frequency: 659.25, duration: 0.16, amplitude: 0.22),
        ]
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
}

private struct Segment {
    let frequency: Double?
    let duration: Double
    let amplitude: Float

    static func tone(frequency: Double, duration: Double, amplitude: Float) -> Segment {
        Segment(frequency: frequency, duration: duration, amplitude: amplitude)
    }

    static func silence(duration: Double) -> Segment {
        Segment(frequency: nil, duration: duration, amplitude: 0)
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
