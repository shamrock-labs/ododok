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
            guard !Task.isCancelled else { return events }
            if let event = await engine.feed(sample.detectionSample) {
                events.append(event)
            }
        }
        guard !Task.isCancelled else { return events }
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

struct GateAdjustmentResult: Equatable {
    enum Strategy: String, Encodable, Equatable {
        case gateThresholdSearch
        case gateFreePersonalization
    }

    let initialThresholds: ChewingGateThresholds
    let adjustedThresholds: ChewingGateThresholds
    let adjustedEvents: [ChewDetectionEvent]
    let replayCount: Int
    let strategy: Strategy

    init(
        initialThresholds: ChewingGateThresholds,
        adjustedThresholds: ChewingGateThresholds,
        adjustedEvents: [ChewDetectionEvent],
        replayCount: Int,
        strategy: Strategy = .gateThresholdSearch
    ) {
        self.initialThresholds = initialThresholds
        self.adjustedThresholds = adjustedThresholds
        self.adjustedEvents = adjustedEvents
        self.replayCount = replayCount
        self.strategy = strategy
    }
}

private struct GateAdjustmentCandidateScore {
    let outsideTarget: Int
    let countDistance: Int
    let thresholdDistance: Double

    func isPreferred(over other: GateAdjustmentCandidateScore) -> Bool {
        if outsideTarget != other.outsideTarget {
            return outsideTarget < other.outsideTarget
        }
        if countDistance != other.countDistance {
            return countDistance < other.countDistance
        }
        return thresholdDistance < other.thresholdDistance
    }
}

struct MeasurementAdjustmentRun: Equatable {
    private(set) var initialEvents: [ChewDetectionEvent] = []
    private(set) var adjustment: GateAdjustmentResult?
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
    var adjustmentStrategy: GateAdjustmentResult.Strategy? { adjustment?.strategy }
    var replayCount: Int { adjustment?.replayCount ?? 0 }

    mutating func appendInitial(_ event: ChewDetectionEvent) {
        initialEvents.append(event)
    }

    mutating func begin(with thresholds: ChewingGateThresholds) {
        initialThresholds = thresholds
    }

    mutating func record(_ adjustment: GateAdjustmentResult) {
        self.adjustment = adjustment
        adjustmentApplied = switch adjustment.strategy {
        case .gateThresholdSearch:
            PeakAmplitudeCalibration.adjustmentSucceeded(
                detectedCount: adjustment.adjustedEvents.count
            )
        case .gateFreePersonalization:
            PeakAmplitudeCalibration.fallbackAdjustmentSucceeded(
                detectedCount: adjustment.adjustedEvents.count
            )
        }
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
protocol GateAdjustmentSearching {
    func adjustment(
        for capture: MeasurementCalibrationCapture,
        minPeakAmplitude: Double,
        initialThresholds: ChewingGateThresholds,
        initialCount: Int
    ) async -> GateAdjustmentResult?
}

struct CaptureBasedGateAdjustmentSearcher: GateAdjustmentSearching {
    private typealias Candidate = (
        thresholds: ChewingGateThresholds,
        events: [ChewDetectionEvent]
    )

    private let analyzer = CalibrationSignalAnalyzer()
    private let targetCenter = 9
    private let maximumReplayCount = 6
    private let minimumDominanceThreshold = 0.02
    private let maximumDominanceThreshold = 0.30

    func adjustment(
        for capture: MeasurementCalibrationCapture,
        minPeakAmplitude: Double,
        initialThresholds: ChewingGateThresholds,
        initialCount: Int
    ) async -> GateAdjustmentResult? {
        guard !capture.samples.isEmpty else { return nil }

        guard let candidates = await replayCandidates(
            capture: capture,
            minPeakAmplitude: minPeakAmplitude,
            initialThresholds: initialThresholds,
            initialCount: initialCount
        ) else { return nil }

        guard let best = candidates.min(by: {
            candidateScore($0, initial: initialThresholds).isPreferred(
                over: candidateScore($1, initial: initialThresholds)
            )
        }) else { return nil }

        if PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: best.events.count) {
            return GateAdjustmentResult(
                initialThresholds: initialThresholds,
                adjustedThresholds: best.thresholds,
                adjustedEvents: best.events,
                replayCount: candidates.count
            )
        }

        if let fallback = await gateFreeFallback(
            capture: capture,
            minPeakAmplitude: minPeakAmplitude,
            initialThresholds: initialThresholds,
            priorReplayCount: candidates.count
        ) {
            return fallback
        }

        return GateAdjustmentResult(
            initialThresholds: initialThresholds,
            adjustedThresholds: best.thresholds,
            adjustedEvents: best.events,
            replayCount: candidates.count
        )
    }

    private func replayCandidates(
        capture: MeasurementCalibrationCapture,
        minPeakAmplitude: Double,
        initialThresholds: ChewingGateThresholds,
        initialCount: Int
    ) async -> [Candidate]? {
        var candidates: [Candidate] = []
        for multiplier in adjustmentMultipliers(initialCount: initialCount).prefix(maximumReplayCount) {
            guard !Task.isCancelled else { return nil }
            let thresholds = adjustedThresholds(initialThresholds, multiplier: multiplier)
            let events = await analyzer.replay(
                capture,
                configuration: ChewDetectionConfiguration(
                    minPeakAmplitude: minPeakAmplitude,
                    gateThresholds: thresholds
                )
            )
            guard !Task.isCancelled else { return nil }
            candidates.append((thresholds, events))
        }
        return candidates
    }

    private func gateFreeFallback(
        capture: MeasurementCalibrationCapture,
        minPeakAmplitude: Double,
        initialThresholds: ChewingGateThresholds,
        priorReplayCount: Int
    ) async -> GateAdjustmentResult? {
        let events = await analyzer.replay(
            capture,
            configuration: ChewDetectionConfiguration(
                minPeakAmplitude: minPeakAmplitude,
                gateThresholds: initialThresholds,
                requiresOpenActivityGate: false
            )
        )
        guard !Task.isCancelled,
              PeakAmplitudeCalibration.fallbackAdjustmentSucceeded(
                  detectedCount: events.count
              ) else { return nil }

        let gateFeatures = analyzer.gateFeatures(
            from: capture,
            around: events.map(\.timestamp)
        )
        let personalizedThresholds = PersonalizedChewingGateCalibration.fallbackThresholds(
            from: gateFeatures,
            preserving: initialThresholds
        )

        return GateAdjustmentResult(
            initialThresholds: initialThresholds,
            adjustedThresholds: personalizedThresholds,
            adjustedEvents: events,
            replayCount: priorReplayCount + 1,
            strategy: .gateFreePersonalization
        )
    }

    private func adjustmentMultipliers(initialCount: Int) -> [Double] {
        if initialCount < PeakAmplitudeCalibration.adjustmentTargetCount.lowerBound {
            return [0.90, 0.80, 0.70, 0.60, 0.50, 0.40]
        }
        return [1.10, 1.20, 1.30, 1.40, 1.50, 1.60]
    }

    private func adjustedThresholds(
        _ initial: ChewingGateThresholds,
        multiplier: Double
    ) -> ChewingGateThresholds {
        ChewingGateThresholds(
            minimumRotationYStd: initial.minimumRotationYStd,
            minimumRotationYDominance: clamped(initial.minimumRotationYDominance * multiplier),
            minimumRotationYJitterBandDominance: clamped(
                initial.minimumRotationYJitterBandDominance * multiplier
            )
        )
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, minimumDominanceThreshold), maximumDominanceThreshold)
    }

    private func candidateScore(
        _ candidate: Candidate,
        initial: ChewingGateThresholds
    ) -> GateAdjustmentCandidateScore {
        let count = candidate.events.count
        let outsideTarget = PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: count) ? 0 : 1
        let countDistance = abs(count - targetCenter)
        let thresholdDistance = abs(
            candidate.thresholds.minimumRotationYDominance - initial.minimumRotationYDominance
        ) + abs(
            candidate.thresholds.minimumRotationYJitterBandDominance
                - initial.minimumRotationYJitterBandDominance
        )
        return GateAdjustmentCandidateScore(
            outsideTarget: outsideTarget,
            countDistance: countDistance,
            thresholdDistance: thresholdDistance
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

    static func fallbackThresholds(
        from chewing: [ChewingGateFeatures],
        preserving current: ChewingGateThresholds
    ) -> ChewingGateThresholds {
        ChewingGateThresholds(
            minimumRotationYStd: personalMinimumThreshold(
                from: chewing.map(\.rotationYStd),
                preserving: current.minimumRotationYStd,
                minimum: 0.005
            ),
            minimumRotationYDominance: personalMinimumThreshold(
                from: chewing.map(\.rotationYDominance),
                preserving: current.minimumRotationYDominance,
                minimum: 0.02
            ),
            minimumRotationYJitterBandDominance: personalMinimumThreshold(
                from: chewing.map(\.rotationYJitterBandDominance),
                preserving: current.minimumRotationYJitterBandDominance,
                minimum: 0.02
            )
        )
    }

    static func personalDominanceThreshold(from chewing: [Double]) -> Double {
        guard let chewingLow = percentile(chewing, fraction: 0.20) else {
            return ChewingGateThresholds.standard.minimumRotationYDominance
        }
        return min(max(chewingLow * 0.8, 0.02), 0.15)
    }

    private static func personalMinimumThreshold(
        from values: [Double],
        preserving current: Double,
        minimum: Double
    ) -> Double {
        guard let lowerValue = percentile(values, fraction: 0.20) else { return current }
        return min(max(lowerValue * 0.8, minimum), current)
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
