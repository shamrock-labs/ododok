import Foundation

struct TimedChewingGateFeatures {
    let timestamp: TimeInterval
    let features: ChewingGateFeatures
}

struct CalibrationSignalAnalyzer {
    private let warmupDuration: TimeInterval = 1.0
    private let peakNeighborhood: TimeInterval = 0.30

    func gateFeatureRows(from capture: MeasurementCalibrationCapture) -> [TimedChewingGateFeatures] {
        guard let firstTimestamp = capture.samples.first?.timestamp else { return [] }
        var extractor = ChewingGateFeatureExtractor()
        return capture.samples.compactMap { sample in
            let timestamp = sample.timestamp - firstTimestamp
            let features = extractor.feed(sample.detectionSample)
            guard timestamp >= warmupDuration else { return nil }
            return TimedChewingGateFeatures(timestamp: timestamp, features: features)
        }
    }

    func gateFeatures(
        from capture: MeasurementCalibrationCapture,
        around peakTimestamps: [TimeInterval]
    ) -> [ChewingGateFeatures] {
        guard !peakTimestamps.isEmpty else { return [] }
        return gateFeatureRows(from: capture).compactMap { row in
            let isNearPeak = peakTimestamps.contains {
                abs($0 - row.timestamp) <= peakNeighborhood
            }
            return isNearPeak ? row.features : nil
        }
    }

    func replay(
        _ capture: MeasurementCalibrationCapture,
        configuration: ChewDetectionConfiguration
    ) async -> [ChewDetectionEvent] {
        let engine = ChewDetectionEngine(configuration: configuration)
        var events: [ChewDetectionEvent] = []
        for sample in capture.samples {
            if let event = await engine.feed(sample.detectionSample) {
                events.append(event)
            }
        }
        if let finalEvent = await engine.finishSession() {
            events.append(finalEvent)
        }
        return events
    }
}

extension HeadphoneMotionSample {
    var detectionSample: ChewDetectionSample {
        ChewDetectionSample(
            timestamp: timestamp,
            rotX: rotationX,
            rotY: rotationY,
            rotZ: rotationZ,
            accelX: userAccelX,
            accelY: userAccelY,
            accelZ: userAccelZ
        )
    }
}

struct ValidationGateAdjustment: Equatable {
    let initialThresholds: ChewingGateThresholds
    let adjustedThresholds: ChewingGateThresholds
    let adjustedEvents: [ChewDetectionEvent]
}

struct MeasurementValidationRun: Equatable {
    private(set) var initialEvents: [ChewDetectionEvent] = []
    private(set) var adjustment: ValidationGateAdjustment?
    private(set) var initialThresholds: ChewingGateThresholds?
    private(set) var adjustmentApplied = false

    init(initialEvents: [ChewDetectionEvent] = []) {
        self.initialEvents = initialEvents
    }

    var initialCount: Int { initialEvents.count }
    var adjustedEvents: [ChewDetectionEvent] { adjustment?.adjustedEvents ?? [] }
    var adjustedCount: Int? { adjustment?.adjustedEvents.count }
    var finalEvents: [ChewDetectionEvent] { adjustment?.adjustedEvents ?? initialEvents }
    var finalCount: Int { finalEvents.count }
    var adjustedThresholds: ChewingGateThresholds? { adjustment?.adjustedThresholds }

    mutating func appendInitial(_ event: ChewDetectionEvent) {
        initialEvents.append(event)
    }

    mutating func begin(with thresholds: ChewingGateThresholds) {
        initialThresholds = thresholds
    }

    mutating func record(_ adjustment: ValidationGateAdjustment) {
        self.adjustment = adjustment
        adjustmentApplied = PeakAmplitudeCalibration.validationPassed(
            detectedCount: adjustment.adjustedEvents.count
        )
    }
}

protocol ChewingGateCalibrating {
    func thresholds(
        baseline: MeasurementCalibrationCapture?,
        measurement: MeasurementCalibrationCapture?,
        representativePeaks: [ChewPeak]
    ) -> ChewingGateThresholds?
}

struct CaptureBasedChewingGateCalibrator: ChewingGateCalibrating {
    private let analyzer = CalibrationSignalAnalyzer()

    func thresholds(
        baseline: MeasurementCalibrationCapture?,
        measurement: MeasurementCalibrationCapture?,
        representativePeaks: [ChewPeak]
    ) -> ChewingGateThresholds? {
        guard let baseline, let measurement else { return nil }
        return PersonalizedChewingGateCalibration.thresholds(
            baseline: analyzer.gateFeatureRows(from: baseline).map(\.features),
            chewing: analyzer.gateFeatures(
                from: measurement,
                around: representativePeaks.map(\.timestamp)
            )
        )
    }
}

@MainActor
protocol ValidationGateAutoAdjusting {
    func adjustment(
        for capture: MeasurementCalibrationCapture,
        minPeakAmplitude: Double,
        initialThresholds: ChewingGateThresholds
    ) async -> ValidationGateAdjustment?
}

struct CaptureBasedValidationGateAutoAdjuster: ValidationGateAutoAdjusting {
    private let analyzer = CalibrationSignalAnalyzer()

    func adjustment(
        for capture: MeasurementCalibrationCapture,
        minPeakAmplitude: Double,
        initialThresholds: ChewingGateThresholds
    ) async -> ValidationGateAdjustment? {
        guard !capture.samples.isEmpty else { return nil }

        let candidateEvents = await analyzer.replay(
            capture,
            configuration: ChewDetectionConfiguration(
                minPeakAmplitude: minPeakAmplitude,
                gateThresholds: initialThresholds,
                requiresOpenActivityGate: false
            )
        )
        let candidateFeatures = analyzer.gateFeatures(
            from: capture,
            around: candidateEvents.map(\.timestamp)
        )
        guard candidateFeatures.count >= PersonalizedChewingGateCalibration.minimumSampleCount else {
            return nil
        }

        let adjustedThresholds = PersonalizedChewingGateCalibration.loweredDominanceThresholds(
            from: candidateFeatures,
            preserving: initialThresholds
        )
        guard adjustedThresholds != initialThresholds else { return nil }

        let adjustedEvents = await analyzer.replay(
            capture,
            configuration: ChewDetectionConfiguration(
                minPeakAmplitude: minPeakAmplitude,
                gateThresholds: adjustedThresholds
            )
        )
        return ValidationGateAdjustment(
            initialThresholds: initialThresholds,
            adjustedThresholds: adjustedThresholds,
            adjustedEvents: adjustedEvents
        )
    }
}

enum PersonalizedChewingGateCalibration {
    static let minimumSampleCount = 20

    static func thresholds(
        baseline: [ChewingGateFeatures],
        chewing: [ChewingGateFeatures]
    ) -> ChewingGateThresholds? {
        guard baseline.count >= minimumSampleCount, chewing.count >= minimumSampleCount else {
            return nil
        }
        let thresholds = loweredDominanceThresholds(from: chewing, preserving: .standard)
        if longestMatchingStreak(in: baseline, thresholds: thresholds) < 10,
           longestMatchingStreak(in: chewing, thresholds: thresholds) >= 10 {
            return thresholds
        }
        return .standard
    }

    static func loweredDominanceThresholds(
        from chewing: [ChewingGateFeatures],
        preserving current: ChewingGateThresholds
    ) -> ChewingGateThresholds {
        ChewingGateThresholds(
            minimumRotationYStd: current.minimumRotationYStd,
            minimumRotationYDominance: min(
                current.minimumRotationYDominance,
                personalDominanceThreshold(from: chewing.map(\.rotationYDominance))
            ),
            minimumRotationYJitterBandDominance: min(
                current.minimumRotationYJitterBandDominance,
                personalDominanceThreshold(from: chewing.map(\.rotationYJitterBandDominance))
            )
        )
    }

    static func personalDominanceThreshold(from chewing: [Double]) -> Double {
        guard let chewingLow = percentile(chewing, fraction: 0.20) else {
            return ChewingGateThresholds.standard.minimumRotationYDominance
        }
        return min(max(chewingLow * 0.8, 0.02), 0.15)
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(floor(Double(sorted.count - 1) * fraction))
        return sorted[index]
    }

    private static func longestMatchingStreak(
        in features: [ChewingGateFeatures],
        thresholds: ChewingGateThresholds
    ) -> Int {
        var longest = 0
        var current = 0
        for feature in features {
            let matches = feature.rotationYStd >= thresholds.minimumRotationYStd &&
                feature.rotationYDominance >= thresholds.minimumRotationYDominance &&
                feature.rotationYJitterBandDominance >= thresholds.minimumRotationYJitterBandDominance &&
                feature.accelToRotation <= 0.050
            current = matches ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}
