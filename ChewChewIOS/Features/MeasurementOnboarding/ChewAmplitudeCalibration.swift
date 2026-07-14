import Foundation

struct MeasurementCalibrationProfile: Equatable {
    let minPeakAmplitude: Double
    let calibrationAmplitudes: [Double]
    let validationDetectedCount: Int
}

enum PeakAmplitudeCalibration {
    static let minimumRequiredPeaks = 7
    static let acceptableValidationCount = 8...12

    static func personalizedThreshold(from amplitudes: [Double]) -> Double? {
        guard amplitudes.count >= minimumRequiredPeaks else { return nil }

        let sorted = amplitudes.sorted()
        let lowerBoundIndex = Int(floor(Double(sorted.count - 1) * 0.2))
        let conservativePeak = sorted[lowerBoundIndex]
        return min(max(conservativePeak * 0.6, 0.001), 0.03)
    }

    static func validationPassed(detectedCount: Int) -> Bool {
        acceptableValidationCount.contains(detectedCount)
    }
}

@MainActor
enum MeasurementCalibrationSamplingMode: Equatable {
    case collectPersonalSignal
    case validate(minPeakAmplitude: Double)
}

@MainActor
protocol MeasurementCalibrationSampling: AnyObject {
    var isDeviceMotionAvailable: Bool { get }

    func start(
        mode: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError: @escaping @MainActor (String) -> Void
    )
    func stop() async
}

@MainActor
final class LocalMeasurementCalibrationSampler: MeasurementCalibrationSampling {
    private enum Processor {
        case amplitudeProbe(ChewPeakAmplitudeProbe)
        case detectionEngine(ChewDetectionEngine)

        func feed(_ sample: ChewDetectionSample) async -> ChewDetectionEvent? {
            switch self {
            case let .amplitudeProbe(probe):
                return await probe.feed(sample)
            case let .detectionEngine(engine):
                return await engine.feed(sample)
            }
        }

        func finish() async {
            guard case let .detectionEngine(engine) = self else { return }
            _ = await engine.finishSession()
        }
    }

    private let motionService: any MealMotionServicing
    private var processor: Processor?
    private var sampleProcessingTailTask: Task<Void, Never>?
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?
    private var processingGeneration = UUID()

    init(motionService: any MealMotionServicing = HeadphoneMotionService()) {
        self.motionService = motionService
    }

    var isDeviceMotionAvailable: Bool {
        motionService.isDeviceMotionAvailable
    }

    func start(
        mode: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        motionService.stop()
        sampleProcessingTailTask?.cancel()
        processingGeneration = UUID()

        let processor: Processor
        switch mode {
        case .collectPersonalSignal:
            processor = .amplitudeProbe(ChewPeakAmplitudeProbe())
        case let .validate(minPeakAmplitude):
            processor = .detectionEngine(ChewDetectionEngine(
                configuration: ChewDetectionConfiguration(minPeakAmplitude: minPeakAmplitude)
            ))
        }
        self.processor = processor
        self.onEvent = onEvent
        let generation = processingGeneration

        motionService.start { [weak self] sample in
            self?.enqueue(sample, processor: processor, generation: generation)
        } onError: { message in
            Task { @MainActor in onError(message) }
        }
    }

    func stop() async {
        motionService.stop()
        let pendingTask = sampleProcessingTailTask
        sampleProcessingTailTask = nil
        await pendingTask?.value
        await processor?.finish()
        processor = nil
        onEvent = nil
        processingGeneration = UUID()
    }

    private func enqueue(
        _ sample: HeadphoneMotionSample,
        processor: Processor,
        generation: UUID
    ) {
        let previousTask = sampleProcessingTailTask
        sampleProcessingTailTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }

            let event = await processor.feed(ChewDetectionSample(
                timestamp: sample.timestamp,
                rotX: sample.rotationX,
                rotY: sample.rotationY,
                rotZ: sample.rotationZ,
                accelX: sample.userAccelX,
                accelY: sample.userAccelY,
                accelZ: sample.userAccelZ
            ))
            guard let event else { return }
            await MainActor.run { [weak self] in
                guard self?.processingGeneration == generation else { return }
                self?.onEvent?(event)
            }
        }
    }
}

#if DEBUG
@MainActor
final class SimulatedMeasurementCalibrationSampler: MeasurementCalibrationSampling {
    private var eventTask: Task<Void, Never>?

    var isDeviceMotionAvailable: Bool { true }

    func start(
        mode: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        eventTask?.cancel()
        let amplitudes = [0.031, 0.028, 0.034, 0.041, 0.029, 0.036, 0.033, 0.039, 0.030, 0.037]
        let initialDelay: Duration
        let minPeakAmplitude: Double
        switch mode {
        case .collectPersonalSignal:
            initialDelay = .milliseconds(1_300)
            minPeakAmplitude = 0
        case let .validate(threshold):
            initialDelay = .milliseconds(300)
            minPeakAmplitude = threshold
        }
        eventTask = Task {
            for (index, amplitude) in amplitudes.enumerated() {
                do {
                    try await Task.sleep(for: index == 0 ? initialDelay : .milliseconds(1_200))
                } catch {
                    return
                }
                guard !Task.isCancelled, amplitude > minPeakAmplitude else { continue }
                onEvent(ChewDetectionEvent(count: index + 1, timestamp: Double(index), amplitude: amplitude))
            }
        }
    }

    func stop() async {
        eventTask?.cancel()
        eventTask = nil
    }
}
#endif
