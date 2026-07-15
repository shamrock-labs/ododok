import Foundation

struct MeasurementCalibrationProfile: Equatable {
    let minPeakAmplitude: Double
    let gateThresholds: ChewingGateThresholds
    let calibrationAmplitudes: [Double]
    let naturalChewInterval: TimeInterval
    let validationDetectedCount: Int
}

enum PeakAmplitudeCalibration {
    static let minimumRequiredPeaks = 7
    static let maximumRepresentativePeaks = 10
    static let minimumPeakSeparation: TimeInterval = 0.32
    static let adjustmentTargetCount = 8...10
    static let fallbackAdjustmentTargetCount = 5...15
    static let adjustmentIntervalRange: ClosedRange<TimeInterval> = 0.45...1.25

    struct NaturalMeasurement: Equatable {
        let representativePeaks: [ChewPeak]
        let naturalChewInterval: TimeInterval

        var amplitudes: [Double] {
            representativePeaks.map(\.amplitude)
        }

        var adjustmentCueInterval: TimeInterval {
            min(max(naturalChewInterval, adjustmentIntervalRange.lowerBound), adjustmentIntervalRange.upperBound)
        }
    }

    static func personalizedThreshold(from amplitudes: [Double]) -> Double? {
        guard amplitudes.count >= minimumRequiredPeaks else { return nil }

        let sorted = amplitudes.sorted()
        let lowerBoundIndex = Int(floor(Double(sorted.count - 1) * 0.2))
        let conservativePeak = sorted[lowerBoundIndex]
        return min(max(conservativePeak * 0.6, 0.001), 0.03)
    }

    static func adjustmentSucceeded(detectedCount: Int) -> Bool {
        adjustmentTargetCount.contains(detectedCount)
    }

    static func fallbackAdjustmentSucceeded(detectedCount: Int) -> Bool {
        fallbackAdjustmentTargetCount.contains(detectedCount)
    }

    static func naturalMeasurement(from events: [ChewDetectionEvent]) -> NaturalMeasurement? {
        let peaks = representativePeaks(from: events)
        guard peaks.count >= minimumRequiredPeaks else { return nil }

        let intervals = zip(peaks, peaks.dropFirst()).map { $1.timestamp - $0.timestamp }
        guard let naturalChewInterval = median(intervals), naturalChewInterval > 0 else { return nil }
        return NaturalMeasurement(
            representativePeaks: peaks,
            naturalChewInterval: naturalChewInterval
        )
    }

    static func representativePeaks(from events: [ChewDetectionEvent]) -> [ChewPeak] {
        let sortedEvents = events
            .filter { $0.amplitude > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = sortedEvents.first else { return [] }

        var windowStartedAt = first.timestamp
        var strongest = ChewPeak(timestamp: first.timestamp, amplitude: first.amplitude)
        var collapsed: [ChewPeak] = []

        for event in sortedEvents.dropFirst() {
            let peak = ChewPeak(timestamp: event.timestamp, amplitude: event.amplitude)
            if event.timestamp - windowStartedAt < minimumPeakSeparation {
                if peak.amplitude > strongest.amplitude {
                    strongest = peak
                }
            } else {
                collapsed.append(strongest)
                windowStartedAt = event.timestamp
                strongest = peak
            }
        }
        collapsed.append(strongest)

        guard collapsed.count > maximumRepresentativePeaks else { return collapsed }
        return collapsed
            .sorted { $0.amplitude > $1.amplitude }
            .prefix(maximumRepresentativePeaks)
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

@MainActor
enum MeasurementCalibrationSamplingMode: Equatable {
    case captureBaseline
    case collectPersonalSignal
    case adjust(minPeakAmplitude: Double, gateThresholds: ChewingGateThresholds)
}

@MainActor
protocol MeasurementCalibrationSampling: AnyObject {
    var isDeviceMotionAvailable: Bool { get }

    func start(
        mode: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError: @escaping @MainActor (String) -> Void
    )
    func stop() async -> MeasurementCalibrationCapture?
}

@MainActor
final class LocalMeasurementCalibrationSampler: MeasurementCalibrationSampling {
    private enum Processor {
        case captureOnly
        case amplitudeProbe(ChewPeakAmplitudeProbe)
        case detectionEngine(ChewDetectionEngine)

        func feed(_ sample: ChewDetectionSample) async -> ChewDetectionEvent? {
            switch self {
            case .captureOnly:
                return nil
            case let .amplitudeProbe(probe):
                return await probe.feed(sample)
            case let .detectionEngine(engine):
                return await engine.feed(sample)
            }
        }

        func finish() async -> ChewDetectionEvent? {
            guard case let .detectionEngine(engine) = self else { return nil }
            return await engine.finishSession()
        }
    }

    private let motionService: any MealMotionServicing
    private var processor: Processor?
    private var sampleProcessingTailTask: Task<Void, Never>?
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?
    private var processingGeneration = UUID()
    private var captureStartedAt: Date?
    private var capturedSamples: [HeadphoneMotionSample] = []
    private var isAcceptingSamples = false

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
        captureStartedAt = Date()
        capturedSamples = []
        isAcceptingSamples = true

        let processor: Processor
        switch mode {
        case .captureBaseline:
            processor = .captureOnly
        case .collectPersonalSignal:
            processor = .amplitudeProbe(ChewPeakAmplitudeProbe())
        case let .adjust(minPeakAmplitude, gateThresholds):
            processor = .detectionEngine(ChewDetectionEngine(
                configuration: ChewDetectionConfiguration(
                    minPeakAmplitude: minPeakAmplitude,
                    gateThresholds: gateThresholds
                )
            ))
        }
        self.processor = processor
        self.onEvent = onEvent
        let generation = processingGeneration

        motionService.start { [weak self] sample in
            self?.enqueue(sample, processor: processor, generation: generation)
        } onError: { [weak self] message in
            Task { @MainActor in
                guard self?.processingGeneration == generation,
                      self?.isAcceptingSamples == true else { return }
                onError(message)
            }
        }
    }

    func stop() async -> MeasurementCalibrationCapture? {
        motionService.stop()
        isAcceptingSamples = false
        let pendingTask = sampleProcessingTailTask
        sampleProcessingTailTask = nil
        await pendingTask?.value
        let finalEvent = await processor?.finish()
        if let finalEvent {
            onEvent?(finalEvent)
        }
        processor = nil
        onEvent = nil
        processingGeneration = UUID()
        defer {
            captureStartedAt = nil
            capturedSamples = []
        }
        guard let captureStartedAt else { return nil }
        return MeasurementCalibrationCapture(
            startedAt: captureStartedAt,
            endedAt: Date(),
            samples: capturedSamples
        )
    }

    private func enqueue(
        _ sample: HeadphoneMotionSample,
        processor: Processor,
        generation: UUID
    ) {
        guard isAcceptingSamples, processingGeneration == generation else { return }
        capturedSamples.append(sample)
        let previousTask = sampleProcessingTailTask
        sampleProcessingTailTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }

            let event = await processor.feed(sample.detectionSample)
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
    private var activeMode: MeasurementCalibrationSamplingMode?

    var isDeviceMotionAvailable: Bool { true }

    func start(
        mode: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        eventTask?.cancel()
        activeMode = mode
        let amplitudes = [0.031, 0.028, 0.034, 0.041, 0.029, 0.036, 0.033, 0.039, 0.030, 0.037]
        switch mode {
        case .captureBaseline:
            eventTask = nil
        case .collectPersonalSignal:
            eventTask = Task {
                for (index, amplitude) in amplitudes.enumerated() {
                    do {
                        try await Task.sleep(for: .milliseconds(750))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    onEvent(ChewDetectionEvent(
                        count: index + 1,
                        timestamp: Double(index) * 0.75,
                        amplitude: amplitude
                    ))
                }
            }
        case let .adjust(threshold, _):
            eventTask = Task {
                for (index, amplitude) in amplitudes.enumerated() {
                    do {
                        try await Task.sleep(for: index == 0 ? .milliseconds(300) : .milliseconds(1_100))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, amplitude > threshold else { continue }
                    onEvent(ChewDetectionEvent(
                        count: index + 1,
                        timestamp: Double(index),
                        amplitude: amplitude
                    ))
                }
            }
        }
    }

    func stop() async -> MeasurementCalibrationCapture? {
        eventTask?.cancel()
        eventTask = nil
        defer { activeMode = nil }
        switch activeMode {
        case .captureBaseline:
            return makeCapture(isChewing: false, duration: 5)
        case .collectPersonalSignal:
            return makeCapture(isChewing: true, duration: 8)
        case .adjust, .none:
            return nil
        }
    }

    private func makeCapture(isChewing: Bool, duration: TimeInterval) -> MeasurementCalibrationCapture {
        let startedAt = Date()
        let samples = (0..<Int(duration * 50)).map { index in
            let timestamp = Double(index) / 50
            let primarySignal = isChewing
                ? 0.08 * sin(2 * Double.pi * 1.3 * timestamp)
                : 0.002 * sin(2 * Double.pi * 1.1 * timestamp)
            let sideSignal = 0.002 * sin(2 * Double.pi * 1.7 * timestamp)
            return HeadphoneMotionSample(
                timestamp: timestamp,
                rotationRateMagnitude: abs(primarySignal),
                userAccelerationMagnitude: 0.0001,
                attitudeRoll: 0,
                attitudePitch: 0,
                attitudeYaw: 0,
                rotationX: sideSignal,
                rotationY: primarySignal,
                rotationZ: sideSignal,
                gravityX: 0,
                gravityY: 0,
                gravityZ: -1,
                userAccelX: 0.0001,
                userAccelY: 0.0001,
                userAccelZ: 0.0001,
                magneticFieldX: 0,
                magneticFieldY: 0,
                magneticFieldZ: 0,
                sensorLocation: "headphone_right"
            )
        }
        return MeasurementCalibrationCapture(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            samples: samples
        )
    }
}
#endif
