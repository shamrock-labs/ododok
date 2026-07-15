import Foundation
import Observation

@MainActor
@Observable
final class MeasurementOnboardingStore {
    typealias Stage = MeasurementOnboardingStage
    typealias Issue = MeasurementOnboardingIssue
    typealias Timing = MeasurementOnboardingTiming

    private(set) var stage: Stage
    private(set) var cueIndex = 0
    private(set) var cuePulseID = 0
    private(set) var cueHitID = 0
    private(set) var isMeasuring = false
    private(set) var isFinishingMeasurement = false
    private(set) var measurementCompleted = false
    private(set) var isAirPodsConnected: Bool
    private(set) var calibrationAmplitudes: [Double] = []
    private(set) var candidateMinPeakAmplitude: Double?
    private(set) var candidateGateThresholds: ChewingGateThresholds?
    private(set) var naturalChewInterval: TimeInterval?
    private(set) var profile: MeasurementCalibrationProfile?
    private(set) var issue: Issue?
    private(set) var diagnosticArtifactURLs: [URL] = []

    private let timing: Timing
    private let sampler: any MeasurementCalibrationSampling
    private let gateCalibrator: any ChewingGateCalibrating
    private let validationGateAutoAdjuster: any ValidationGateAutoAdjusting
    private let artifactUploader: any MeasurementCalibrationArtifactUploading
    private var measurementTask: Task<Void, Never>?
    private var samplerStopTask: Task<MeasurementCalibrationCapture?, Never>?
    private var calibrationId = UUID()
    private var calibrationEvents: [ChewDetectionEvent] = []
    private var validationRun = MeasurementValidationRun()
    private var baselineCapture: MeasurementCalibrationCapture?
    private var measurementCapture: MeasurementCalibrationCapture?
    private var isAcceptingValidationSignal = false

    init(
        stage: Stage = .intro,
        isAirPodsConnected: Bool = false,
        timing: Timing = .live,
        sampler: (any MeasurementCalibrationSampling)? = nil,
        gateCalibrator: (any ChewingGateCalibrating)? = nil,
        validationGateAutoAdjuster: (any ValidationGateAutoAdjusting)? = nil,
        artifactUploader: (any MeasurementCalibrationArtifactUploading)? = nil,
        cuePlayer _: (any MeasurementCuePlaying)? = nil
    ) {
        self.stage = stage
        self.isAirPodsConnected = isAirPodsConnected
        self.timing = timing
        self.sampler = sampler ?? LocalMeasurementCalibrationSampler()
        self.gateCalibrator = gateCalibrator ?? CaptureBasedChewingGateCalibrator()
        self.validationGateAutoAdjuster = validationGateAutoAdjuster
            ?? CaptureBasedValidationGateAutoAdjuster()
        self.artifactUploader = artifactUploader ?? NoopCalibrationArtifactUploader()
    }

    var cueCount: Int { timing.cueCount }
    var validationDetectedCount: Int { validationRun.finalCount }
    var validationDetectedCountBeforeAdjustment: Int? {
        validationRun.adjustment == nil ? nil : validationRun.initialCount
    }
    var validationAdjustmentApplied: Bool { validationRun.adjustmentApplied }

    var validationCueInterval: TimeInterval {
        let measured = naturalChewInterval ?? 0.75
        return min(
            max(measured, PeakAmplitudeCalibration.validationIntervalRange.lowerBound),
            PeakAmplitudeCalibration.validationIntervalRange.upperBound
        )
    }

    func setAirPodsConnected(_ connected: Bool) {
        isAirPodsConnected = connected
    }

    func moveForward() {
        guard !isMeasuring, !isFinishingMeasurement else { return }

        switch stage {
        case .intro:
            setStage(.connection)
        case .connection where isAirPodsConnected:
            setStage(.baseline)
        case .calibration where measurementCompleted:
            setStage(.validation)
        default:
            break
        }
    }

    func startMeasurement() {
        guard stage == .baseline || stage == .calibration || stage == .validation,
              !isMeasuring,
              !isFinishingMeasurement else { return }
        guard sampler.isDeviceMotionAvailable else {
            showIssue(.motionUnavailable)
            return
        }
        guard stage != .validation || (
            candidateMinPeakAmplitude != nil && candidateGateThresholds != nil
        ) else { return }

        measurementTask?.cancel()
        resetCurrentRun()
        isMeasuring = true

        let samplingMode: MeasurementCalibrationSamplingMode = switch stage {
        case .baseline:
            .captureBaseline
        case .calibration:
            .collectPersonalSignal
        default:
            .validate(
                minPeakAmplitude: candidateMinPeakAmplitude
                    ?? ChewDetectionConfiguration.standard.minPeakAmplitude,
                gateThresholds: candidateGateThresholds ?? .standard
            )
        }

        sampler.start(
            mode: samplingMode,
            onEvent: { [weak self] event in self?.handle(event) },
            onError: { [weak self] message in self?.showIssue(.sensor(message)) }
        )

        if stage == .baseline {
            measurementTask = Task { [weak self] in
                await self?.runBaseline()
            }
        } else if stage == .validation {
            measurementTask = Task { [weak self] in
                await self?.runValidation()
            }
        }
    }

    func finishNaturalMeasurement() async {
        guard stage == .calibration, isMeasuring, !isFinishingMeasurement else { return }
        isFinishingMeasurement = true
        measurementCapture = await stopSampler()
        isMeasuring = false

        guard let measurement = PeakAmplitudeCalibration.naturalMeasurement(from: calibrationEvents),
              let threshold = PeakAmplitudeCalibration.personalizedThreshold(from: measurement.amplitudes) else {
            isFinishingMeasurement = false
            enqueueArtifacts(outcome: .insufficientCalibration, validationCapture: nil)
            showIssue(.insufficientCalibration)
            return
        }

        guard let gateThresholds = gateCalibrator.thresholds(
            baseline: baselineCapture,
            measurement: measurementCapture,
            representativePeaks: measurement.representativePeaks
        ) else {
            isFinishingMeasurement = false
            enqueueArtifacts(outcome: .insufficientSeparation, validationCapture: nil)
            showIssue(.insufficientSeparation)
            return
        }

        calibrationAmplitudes = measurement.amplitudes
        candidateMinPeakAmplitude = threshold
        candidateGateThresholds = gateThresholds
        naturalChewInterval = measurement.naturalChewInterval
        measurementCompleted = true
        isFinishingMeasurement = false
    }

    func retryMeasurement() async {
        prepareToStopMeasurement()
        _ = await stopSampler()
        resetExperiment()
        setStage(.baseline)
        startMeasurement()
    }

    func retryValidation() async {
        guard stage == .signalIssue, issue == .validationOutOfRange else { return }
        prepareToStopMeasurement()
        _ = await stopSampler()
        // 실패한 검증도 별도 S3 묶음으로 보존하므로 다음 시도는 새 식별자를 사용한다.
        calibrationId = UUID()
        setStage(.validation)
        startMeasurement()
    }

    func cancelMeasurement() {
        prepareToStopMeasurement()
        beginStoppingSampler()
    }

    private func runValidation() async {
        guard await runValidationGuides() else { return }

        let validationCapture = await stopSampler()
        isAcceptingValidationSignal = false
        guard !Task.isCancelled else { return }
        isMeasuring = false
        await finishValidation(validationCapture: validationCapture)
    }

    private func runBaseline() async {
        guard await wait(for: timing.baselineDuration) else { return }
        let capture = await stopSampler()
        guard !Task.isCancelled else { return }
        isMeasuring = false
        guard let capture, !capture.samples.isEmpty else {
            showIssue(.insufficientSeparation)
            return
        }
        baselineCapture = capture
        setStage(.calibration)
    }

    private func runValidationGuides() async -> Bool {
        validationRun = MeasurementValidationRun()
        isAcceptingValidationSignal = true

        for index in 1...timing.cueCount {
            guard !Task.isCancelled else { return false }
            cueIndex = index
            cuePulseID += 1
            guard await wait(for: activeValidationCueInterval) else { return false }
            cueHitID += 1
        }
        return true
    }

    private var activeValidationCueInterval: Duration {
        timing.validationCueIntervalOverride ?? .seconds(validationCueInterval)
    }

    private func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    private func handle(_ event: ChewDetectionEvent) {
        guard isMeasuring else { return }
        switch stage {
        case .baseline:
            break
        case .calibration:
            calibrationEvents.append(event)
        case .validation where isAcceptingValidationSignal:
            validationRun.appendInitial(event)
        default:
            break
        }
    }

    private func finishValidation(validationCapture: MeasurementCalibrationCapture?) async {
        guard let candidateMinPeakAmplitude,
              let candidateGateThresholds,
              let naturalChewInterval else {
            enqueueArtifacts(outcome: .validationOutOfRange, validationCapture: validationCapture)
            showIssue(.validationOutOfRange)
            return
        }

        validationRun.begin(with: candidateGateThresholds)

        if validationRun.initialCount < PeakAmplitudeCalibration.acceptableValidationCount.lowerBound,
           let validationCapture,
           let adjustment = await validationGateAutoAdjuster.adjustment(
               for: validationCapture,
               minPeakAmplitude: candidateMinPeakAmplitude,
               initialThresholds: candidateGateThresholds
           ) {
            validationRun.record(adjustment)
            if validationRun.adjustmentApplied {
                self.candidateGateThresholds = adjustment.adjustedThresholds
            }
        }

        guard PeakAmplitudeCalibration.validationPassed(detectedCount: validationRun.finalCount) else {
            enqueueArtifacts(outcome: .validationOutOfRange, validationCapture: validationCapture)
            showIssue(.validationOutOfRange)
            return
        }

        profile = MeasurementCalibrationProfile(
            minPeakAmplitude: candidateMinPeakAmplitude,
            gateThresholds: self.candidateGateThresholds ?? candidateGateThresholds,
            calibrationAmplitudes: calibrationAmplitudes,
            naturalChewInterval: naturalChewInterval,
            validationDetectedCount: validationRun.finalCount
        )
        enqueueArtifacts(
            outcome: validationRun.adjustmentApplied ? .passedAfterAdjustment : .passed,
            validationCapture: validationCapture
        )
        setStage(.ready)
    }

    private func resetCurrentRun() {
        cueIndex = 0
        cuePulseID = 0
        cueHitID = 0
        measurementCompleted = false
        issue = nil
        diagnosticArtifactURLs = []
        isAcceptingValidationSignal = false
        if stage == .baseline {
            baselineCapture = nil
        } else if stage == .calibration {
            calibrationEvents = []
            calibrationAmplitudes = []
            candidateMinPeakAmplitude = nil
            candidateGateThresholds = nil
            naturalChewInterval = nil
            profile = nil
        } else {
            validationRun = MeasurementValidationRun()
        }
    }

    private func resetExperiment() {
        calibrationId = UUID()
        calibrationEvents = []
        validationRun = MeasurementValidationRun()
        measurementCapture = nil
        baselineCapture = nil
        calibrationAmplitudes = []
        candidateMinPeakAmplitude = nil
        candidateGateThresholds = nil
        naturalChewInterval = nil
        profile = nil
        issue = nil
        diagnosticArtifactURLs = []
    }

    private func showIssue(_ issue: Issue) {
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        isFinishingMeasurement = false
        isAcceptingValidationSignal = false
        measurementCompleted = false
        self.issue = issue
        stage = .signalIssue
        beginStoppingSampler()
    }

    private func prepareToStopMeasurement() {
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        isFinishingMeasurement = false
        isAcceptingValidationSignal = false
    }

    private func beginStoppingSampler() {
        guard samplerStopTask == nil else { return }
        samplerStopTask = Task { [weak self] in
            guard let self else { return nil }
            let capture = await sampler.stop()
            samplerStopTask = nil
            return capture
        }
    }

    private func stopSampler() async -> MeasurementCalibrationCapture? {
        beginStoppingSampler()
        let stopTask = samplerStopTask
        return await stopTask?.value
    }

    private func enqueueArtifacts(
        outcome: MeasurementCalibrationOutcome,
        validationCapture: MeasurementCalibrationCapture?
    ) {
        let input = MeasurementCalibrationArtifactFactory.Input(
            calibrationId: calibrationId,
            measurementCapture: measurementCapture,
            validationCapture: validationCapture,
            calibrationEvents: calibrationEvents,
            validationRun: validationRun,
            threshold: candidateMinPeakAmplitude,
            gateThresholds: candidateGateThresholds,
            naturalChewInterval: naturalChewInterval,
            representativeAmplitudes: calibrationAmplitudes,
            guidedExpectedCount: timing.cueCount,
            outcome: outcome
        )
        let bundle = MeasurementCalibrationArtifactFactory.makeBundle(input: input)
        if outcome != .passed, outcome != .passedAfterAdjustment {
            diagnosticArtifactURLs = MeasurementCalibrationArtifactExporter.export(bundle)
        }
        Task { await artifactUploader.enqueue(bundle) }
    }

    private func setStage(_ newStage: Stage) {
        measurementTask?.cancel()
        stage = newStage
        cueIndex = 0
        measurementCompleted = newStage == .ready
        isMeasuring = false
        isFinishingMeasurement = false
    }
}

#if DEBUG
extension MeasurementOnboardingStore {
    static func preview(
        stage: Stage,
        sampler: any MeasurementCalibrationSampling
    ) -> MeasurementOnboardingStore {
        let store = MeasurementOnboardingStore(
            stage: stage,
            isAirPodsConnected: true,
            sampler: sampler
        )
        guard stage == .validation || stage == .ready else { return store }

        let amplitudes = [0.031, 0.028, 0.034, 0.041, 0.029, 0.036, 0.033, 0.039, 0.030, 0.037]
        store.calibrationAmplitudes = amplitudes
        store.candidateMinPeakAmplitude = PeakAmplitudeCalibration.personalizedThreshold(from: amplitudes)
        store.candidateGateThresholds = .standard
        store.naturalChewInterval = 0.75
        if stage == .ready, let threshold = store.candidateMinPeakAmplitude {
            store.validationRun = MeasurementValidationRun(initialEvents: (0..<10).map { index in
                ChewDetectionEvent(count: index + 1, timestamp: Double(index), amplitude: 0.03)
            })
            store.profile = MeasurementCalibrationProfile(
                minPeakAmplitude: threshold,
                gateThresholds: .standard,
                calibrationAmplitudes: amplitudes,
                naturalChewInterval: 0.75,
                validationDetectedCount: 10
            )
        }
        return store
    }
}
#endif
