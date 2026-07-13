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
        return min(max(conservativePeak * 0.6, 0.003), 0.03)
    }

    static func validationPassed(detectedCount: Int) -> Bool {
        acceptableValidationCount.contains(detectedCount)
    }
}

@MainActor
protocol MeasurementCalibrationSampling: AnyObject {
    var isDeviceMotionAvailable: Bool { get }

    func start(
        minPeakAmplitude: Double,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError: @escaping @MainActor (String) -> Void
    )
    func stop() async
}

@MainActor
final class LocalMeasurementCalibrationSampler: MeasurementCalibrationSampling {
    private let motionService: any MealMotionServicing
    private var detectionEngine: ChewDetectionEngine?
    private var sampleProcessingTailTask: Task<Void, Never>?
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?

    init(motionService: any MealMotionServicing = HeadphoneMotionService()) {
        self.motionService = motionService
    }

    var isDeviceMotionAvailable: Bool {
        motionService.isDeviceMotionAvailable
    }

    func start(
        minPeakAmplitude: Double,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        motionService.stop()
        sampleProcessingTailTask?.cancel()

        let engine = ChewDetectionEngine(
            configuration: ChewDetectionConfiguration(minPeakAmplitude: minPeakAmplitude)
        )
        detectionEngine = engine
        self.onEvent = onEvent

        motionService.start { [weak self] sample in
            self?.enqueue(sample, engine: engine)
        } onError: { message in
            Task { @MainActor in onError(message) }
        }
    }

    func stop() async {
        motionService.stop()
        let pendingTask = sampleProcessingTailTask
        sampleProcessingTailTask = nil
        await pendingTask?.value
        _ = await detectionEngine?.finishSession()
        detectionEngine = nil
        onEvent = nil
    }

    private func enqueue(_ sample: HeadphoneMotionSample, engine: ChewDetectionEngine) {
        let previousTask = sampleProcessingTailTask
        sampleProcessingTailTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }

            let event = await engine.feed(ChewDetectionSample(
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
                guard self?.detectionEngine === engine else { return }
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
        minPeakAmplitude: Double,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        eventTask?.cancel()
        let amplitudes = [0.031, 0.028, 0.034, 0.041, 0.029, 0.036, 0.033, 0.039, 0.030, 0.037]
        eventTask = Task {
            for (index, amplitude) in amplitudes.enumerated() {
                do {
                    try await Task.sleep(for: index == 0 ? .milliseconds(250) : .seconds(1))
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
