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
    private(set) var isRestartingMeasurement = false
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
    private let gateAdjustmentSearcher: any GateAdjustmentSearching
    private let artifactUploader: any MeasurementCalibrationArtifactUploading
    private var measurementTask: Task<Void, Never>?
    private var samplerStopTask: Task<MeasurementCalibrationCapture?, Never>?
    private var calibrationId = UUID()
    private var calibrationEvents: [ChewDetectionEvent] = []
    private var adjustmentRun = MeasurementAdjustmentRun()
    private var baselineCapture: MeasurementCalibrationCapture?
    private var measurementCapture: MeasurementCalibrationCapture?
    private var isAcceptingAdjustmentSignal = false
    private var activeRunID: UUID?
    private var activeRestartID: UUID?

    init(
        stage: Stage = .intro,
        isAirPodsConnected: Bool = false,
        timing: Timing = .live,
        sampler: (any MeasurementCalibrationSampling)? = nil,
        gateCalibrator: (any ChewingGateCalibrating)? = nil,
        gateAdjustmentSearcher: (any GateAdjustmentSearching)? = nil,
        artifactUploader: (any MeasurementCalibrationArtifactUploading)? = nil,
        cuePlayer _: (any MeasurementCuePlaying)? = nil
    ) {
        self.stage = stage
        self.isAirPodsConnected = isAirPodsConnected
        self.timing = timing
        self.sampler = sampler ?? LocalMeasurementCalibrationSampler()
        self.gateCalibrator = gateCalibrator ?? CaptureBasedChewingGateCalibrator()
        self.gateAdjustmentSearcher = gateAdjustmentSearcher
            ?? CaptureBasedGateAdjustmentSearcher()
        self.artifactUploader = artifactUploader ?? NoopCalibrationArtifactUploader()
    }

    var cueCount: Int { timing.cueCount }
    var adjustmentDetectedCount: Int { adjustmentRun.finalCount }
    var detectedCountBeforeAdjustment: Int? {
        adjustmentRun.adjustment == nil ? nil : adjustmentRun.initialCount
    }
    var gateAdjustmentApplied: Bool { adjustmentRun.adjustmentApplied }

    var adjustmentCueInterval: TimeInterval {
        let measured = naturalChewInterval ?? 0.75
        return min(
            max(measured, PeakAmplitudeCalibration.adjustmentIntervalRange.lowerBound),
            PeakAmplitudeCalibration.adjustmentIntervalRange.upperBound
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
            setStage(.adjustment)
        default:
            break
        }
    }

    func startMeasurement() {
        guard stage == .baseline || stage == .calibration || stage == .adjustment,
              !isMeasuring,
              !isFinishingMeasurement,
              !isRestartingMeasurement else { return }
        guard sampler.isDeviceMotionAvailable else {
            showIssue(.motionUnavailable)
            return
        }
        guard stage != .adjustment || (
            candidateMinPeakAmplitude != nil && candidateGateThresholds != nil
        ) else { return }

        guard samplerStopTask == nil else {
            queueMeasurementAfterSamplerStops(for: stage)
            return
        }

        beginMeasurement()
    }

    private func queueMeasurementAfterSamplerStops(for requestedStage: Stage) {
        measurementTask?.cancel()
        measurementTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.stopSampler()
            guard !Task.isCancelled, self.stage == requestedStage else { return }
            self.measurementTask = nil
            self.beginMeasurement()
        }
    }

    private func beginMeasurement() {
        guard stage == .baseline || stage == .calibration || stage == .adjustment,
              !isMeasuring,
              !isFinishingMeasurement,
              samplerStopTask == nil else { return }

        measurementTask?.cancel()
        resetCurrentRun()
        isMeasuring = true
        let runID = UUID()
        activeRunID = runID

        let samplingMode: MeasurementCalibrationSamplingMode = switch stage {
        case .baseline:
            .captureBaseline
        case .calibration:
            .collectPersonalSignal
        default:
            .adjust(
                minPeakAmplitude: candidateMinPeakAmplitude
                    ?? ChewDetectionConfiguration.standard.minPeakAmplitude,
                gateThresholds: candidateGateThresholds ?? .standard
            )
        }

        sampler.start(
            mode: samplingMode,
            onEvent: { [weak self] event in self?.handle(event, runID: runID) },
            onError: { [weak self] message in self?.handleSensorError(message, runID: runID) }
        )

        if stage == .baseline {
            measurementTask = Task { [weak self] in
                await self?.runBaseline(runID: runID)
            }
        } else if stage == .adjustment {
            measurementTask = Task { [weak self] in
                await self?.runAdjustment(runID: runID)
            }
        }
    }

    func finishNaturalMeasurement() async {
        guard stage == .calibration,
              isMeasuring,
              !isFinishingMeasurement,
              let runID = activeRunID else { return }
        isFinishingMeasurement = true
        let capture = await stopSampler()
        guard isCurrentRun(runID, stage: .calibration), !Task.isCancelled else { return }
        measurementCapture = capture
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
        activeRunID = nil
    }

    func retryMeasurement() async {
        guard let restartID = beginRestart() else { return }
        defer { finishRestart(restartID) }
        prepareToStopMeasurement()
        _ = await stopSampler()
        guard activeRestartID == restartID, !Task.isCancelled else { return }
        resetExperiment()
        setStage(.baseline)
        finishRestart(restartID)
        startMeasurement()
    }

    func retryAdjustment() async {
        guard stage == .signalIssue,
              issue == .adjustmentNeeded,
              let restartID = beginRestart() else { return }
        defer { finishRestart(restartID) }
        prepareToStopMeasurement()
        _ = await stopSampler()
        guard activeRestartID == restartID, !Task.isCancelled else { return }
        // 완료하지 못한 조정도 별도 S3 묶음으로 보존하므로 다음 시도는 새 식별자를 사용한다.
        calibrationId = UUID()
        setStage(.adjustment)
        finishRestart(restartID)
        startMeasurement()
    }

    func cancelMeasurement() {
        invalidateRestart()
        prepareToStopMeasurement()
        beginStoppingSampler()
    }

    private func runAdjustment(runID: UUID) async {
        guard await runAdjustmentGuides(runID: runID) else { return }

        let adjustmentCapture = await stopSampler()
        guard isCurrentRun(runID, stage: .adjustment), !Task.isCancelled else { return }
        isAcceptingAdjustmentSignal = false
        isMeasuring = false
        await finishAdjustment(capture: adjustmentCapture, runID: runID)
    }

    private func runBaseline(runID: UUID) async {
        guard await wait(for: timing.baselineDuration) else { return }
        let capture = await stopSampler()
        guard isCurrentRun(runID, stage: .baseline), !Task.isCancelled else { return }
        isMeasuring = false
        guard let capture, !capture.samples.isEmpty else {
            showIssue(.insufficientSeparation)
            return
        }
        baselineCapture = capture
        setStage(.calibration)
    }

    private func runAdjustmentGuides(runID: UUID) async -> Bool {
        adjustmentRun = MeasurementAdjustmentRun()
        isAcceptingAdjustmentSignal = true

        for index in 1...timing.cueCount {
            guard isCurrentRun(runID, stage: .adjustment), !Task.isCancelled else { return false }
            cueIndex = index
            cuePulseID += 1
            guard await wait(for: activeAdjustmentCueInterval) else { return false }
            cueHitID += 1
        }
        return true
    }

    private var activeAdjustmentCueInterval: Duration {
        timing.adjustmentCueIntervalOverride ?? .seconds(adjustmentCueInterval)
    }

    private func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    private func handle(_ event: ChewDetectionEvent, runID: UUID) {
        guard activeRunID == runID, isMeasuring else { return }
        switch stage {
        case .baseline:
            break
        case .calibration:
            calibrationEvents.append(event)
        case .adjustment where isAcceptingAdjustmentSignal:
            adjustmentRun.appendInitial(event)
        default:
            break
        }
    }

    private func handleSensorError(_ message: String, runID: UUID) {
        guard activeRunID == runID else { return }
        showIssue(.sensor(message))
    }

    private func finishAdjustment(
        capture: MeasurementCalibrationCapture?,
        runID: UUID
    ) async {
        guard isCurrentRun(runID, stage: .adjustment), !Task.isCancelled else { return }
        guard let candidateMinPeakAmplitude,
              let candidateGateThresholds,
              let naturalChewInterval else {
            enqueueArtifacts(outcome: .validationOutOfRange, validationCapture: capture)
            showIssue(.adjustmentNeeded)
            return
        }

        adjustmentRun.begin(with: candidateGateThresholds)

        if !PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: adjustmentRun.initialCount),
           let capture,
           let adjustment = await gateAdjustmentSearcher.adjustment(
               for: capture,
               minPeakAmplitude: candidateMinPeakAmplitude,
               initialThresholds: candidateGateThresholds,
               initialCount: adjustmentRun.initialCount
           ) {
            guard isCurrentRun(runID, stage: .adjustment), !Task.isCancelled else { return }
            adjustmentRun.record(adjustment)
            if adjustmentRun.adjustmentApplied {
                self.candidateGateThresholds = adjustment.adjustedThresholds
            }
        }

        guard PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: adjustmentRun.finalCount)
            || adjustmentRun.adjustmentApplied else {
            enqueueArtifacts(outcome: .validationOutOfRange, validationCapture: capture)
            showIssue(.adjustmentNeeded)
            return
        }

        profile = MeasurementCalibrationProfile(
            minPeakAmplitude: candidateMinPeakAmplitude,
            gateThresholds: self.candidateGateThresholds ?? candidateGateThresholds,
            calibrationAmplitudes: calibrationAmplitudes,
            naturalChewInterval: naturalChewInterval,
            validationDetectedCount: adjustmentRun.finalCount
        )
        enqueueArtifacts(
            outcome: adjustmentRun.adjustmentApplied ? .passedAfterAdjustment : .passed,
            validationCapture: capture
        )
        setStage(.ready)
    }

    private func isCurrentRun(_ runID: UUID, stage expectedStage: Stage) -> Bool {
        activeRunID == runID && stage == expectedStage
    }

    private func beginRestart() -> UUID? {
        guard !isRestartingMeasurement else { return nil }
        let restartID = UUID()
        activeRestartID = restartID
        isRestartingMeasurement = true
        return restartID
    }

    private func finishRestart(_ restartID: UUID) {
        guard activeRestartID == restartID else { return }
        activeRestartID = nil
        isRestartingMeasurement = false
    }

    private func invalidateRestart() {
        activeRestartID = nil
        isRestartingMeasurement = false
    }
}

private extension MeasurementOnboardingStore {
    func resetCurrentRun() {
        cueIndex = 0
        cuePulseID = 0
        cueHitID = 0
        measurementCompleted = false
        issue = nil
        diagnosticArtifactURLs = []
        isAcceptingAdjustmentSignal = false
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
            adjustmentRun = MeasurementAdjustmentRun()
        }
    }

    func resetExperiment() {
        calibrationId = UUID()
        calibrationEvents = []
        adjustmentRun = MeasurementAdjustmentRun()
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

    func showIssue(_ issue: Issue) {
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        isFinishingMeasurement = false
        invalidateRestart()
        isAcceptingAdjustmentSignal = false
        activeRunID = nil
        measurementCompleted = false
        self.issue = issue
        stage = .signalIssue
        beginStoppingSampler()
    }

    func prepareToStopMeasurement() {
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        isFinishingMeasurement = false
        isAcceptingAdjustmentSignal = false
        activeRunID = nil
    }

    func beginStoppingSampler() {
        guard samplerStopTask == nil else { return }
        samplerStopTask = Task { [weak self] in
            guard let self else { return nil }
            let capture = await sampler.stop()
            samplerStopTask = nil
            return capture
        }
    }

    func stopSampler() async -> MeasurementCalibrationCapture? {
        beginStoppingSampler()
        let stopTask = samplerStopTask
        return await stopTask?.value
    }

    func enqueueArtifacts(
        outcome: MeasurementCalibrationOutcome,
        validationCapture: MeasurementCalibrationCapture?
    ) {
        let input = MeasurementCalibrationArtifactFactory.Input(
            calibrationId: calibrationId,
            measurementCapture: measurementCapture,
            validationCapture: validationCapture,
            calibrationEvents: calibrationEvents,
            adjustmentRun: adjustmentRun,
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

    func setStage(_ newStage: Stage) {
        measurementTask?.cancel()
        activeRunID = nil
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
        guard stage == .adjustment || stage == .ready else { return store }

        let amplitudes = [0.031, 0.028, 0.034, 0.041, 0.029, 0.036, 0.033, 0.039, 0.030, 0.037]
        store.calibrationAmplitudes = amplitudes
        store.candidateMinPeakAmplitude = PeakAmplitudeCalibration.personalizedThreshold(from: amplitudes)
        store.candidateGateThresholds = .standard
        store.naturalChewInterval = 0.75
        if stage == .ready, let threshold = store.candidateMinPeakAmplitude {
            store.adjustmentRun = MeasurementAdjustmentRun(initialEvents: (0..<10).map { index in
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
