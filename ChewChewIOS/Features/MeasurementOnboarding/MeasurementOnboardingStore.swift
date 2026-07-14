import Foundation
import Observation

@MainActor
@Observable
final class MeasurementOnboardingStore {
    enum Stage: String, CaseIterable {
        case intro
        case connection
        case calibration
        case validation
        case ready
        case signalIssue

        var progressIndex: Int {
            switch self {
            case .intro, .connection: 0
            case .calibration: 1
            case .validation: 2
            case .ready: 3
            case .signalIssue: 2
            }
        }
    }

    enum Issue: Equatable {
        case motionUnavailable
        case insufficientCalibration(detected: Int)
        case validationOutOfRange(detected: Int)
        case sensor(String)

        var message: String {
            switch self {
            case .motionUnavailable:
                return "AirPods 움직임 센서를 사용할 수 없어요."
            case let .insufficientCalibration(detected):
                return "10번 중 \(detected)번만 기준 신호를 찾았어요."
            case let .validationOutOfRange(detected):
                return "10번을 씹는 동안 \(detected)번 감지했어요."
            case let .sensor(message):
                return message
            }
        }
    }

    struct Timing {
        let cueCount: Int
        let cueInterval: Duration
        let cueApproachDuration: Duration
        let cueResponseDuration: Duration

        init(
            cueCount: Int,
            cueInterval: Duration,
            cueApproachDuration: Duration = .zero,
            cueResponseDuration: Duration? = nil
        ) {
            self.cueCount = cueCount
            self.cueInterval = cueInterval
            self.cueApproachDuration = cueApproachDuration
            self.cueResponseDuration = cueResponseDuration ?? cueInterval
        }

        static let live = Timing(
            cueCount: 10,
            cueInterval: .milliseconds(1_200),
            cueApproachDuration: .milliseconds(1_200),
            cueResponseDuration: .milliseconds(600)
        )
    }

    private(set) var stage: Stage
    private(set) var cueIndex = 0
    private(set) var cuePulseID = 0
    private(set) var cueHitID = 0
    private(set) var isMeasuring = false
    private(set) var measurementCompleted = false
    private(set) var isAirPodsConnected: Bool
    private(set) var calibrationAmplitudes: [Double] = []
    private(set) var candidateMinPeakAmplitude: Double?
    private(set) var validationDetectedCount = 0
    private(set) var profile: MeasurementCalibrationProfile?
    private(set) var issue: Issue?

    private let timing: Timing
    private let sampler: any MeasurementCalibrationSampling
    private let cuePlayer: (any MeasurementCuePlaying)?
    private var measurementTask: Task<Void, Never>?
    private var strongestPeakInCurrentCue: Double?
    private var isAcceptingCalibrationSignal = false

    init(
        stage: Stage = .intro,
        isAirPodsConnected: Bool = false,
        timing: Timing = .live,
        sampler: (any MeasurementCalibrationSampling)? = nil,
        cuePlayer: (any MeasurementCuePlaying)? = nil
    ) {
        self.stage = stage
        self.isAirPodsConnected = isAirPodsConnected
        self.timing = timing
        self.sampler = sampler ?? LocalMeasurementCalibrationSampler()
        self.cuePlayer = cuePlayer
    }

    var cueCount: Int { timing.cueCount }

    func setAirPodsConnected(_ connected: Bool) {
        isAirPodsConnected = connected
    }

    func moveForward() {
        guard !isMeasuring else { return }

        switch stage {
        case .intro:
            setStage(.connection)
        case .connection where isAirPodsConnected:
            setStage(.calibration)
        case .calibration where measurementCompleted:
            setStage(.validation)
        default:
            break
        }
    }

    func startMeasurement() {
        guard stage == .calibration || stage == .validation, !isMeasuring else { return }
        guard sampler.isDeviceMotionAvailable else {
            showIssue(.motionUnavailable)
            return
        }
        guard stage != .validation || candidateMinPeakAmplitude != nil else { return }

        measurementTask?.cancel()
        resetCurrentRun()
        isMeasuring = true

        let samplingMode: MeasurementCalibrationSamplingMode = if stage == .calibration {
            .collectPersonalSignal
        } else {
            .validate(
                minPeakAmplitude: candidateMinPeakAmplitude
                    ?? ChewDetectionConfiguration.standard.minPeakAmplitude
            )
        }

        sampler.start(
            mode: samplingMode,
            onEvent: { [weak self] event in self?.handle(event) },
            onError: { [weak self] message in self?.showIssue(.sensor(message)) }
        )

        measurementTask = Task { [weak self] in
            await self?.runCues()
        }
    }

    func retryMeasurement() {
        resetExperiment()
        setStage(.calibration)
        startMeasurement()
    }

    func cancelMeasurement() {
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        Task { await sampler.stop() }
    }

    private func runCues() async {
        if stage == .calibration {
            guard await runCalibrationCues() else { return }
        } else {
            guard await runValidationCues() else { return }
        }

        await sampler.stop()
        guard !Task.isCancelled else { return }
        isMeasuring = false

        switch stage {
        case .calibration:
            finishCalibration()
        case .validation:
            finishValidation()
        default:
            break
        }
    }

    private func runCalibrationCues() async -> Bool {
        cueIndex = 1
        cuePulseID += 1
        guard await wait(for: timing.cueApproachDuration) else { return false }

        for cue in 1...timing.cueCount {
            guard !Task.isCancelled else { return false }
            cueIndex = cue
            strongestPeakInCurrentCue = nil
            cuePlayer?.playCalibrationCue()
            cueHitID = cue
            isAcceptingCalibrationSignal = true

            if cue < timing.cueCount {
                cuePulseID += 1
            }

            guard await wait(for: timing.cueResponseDuration) else { return false }
            isAcceptingCalibrationSignal = false

            if let strongestPeakInCurrentCue {
                calibrationAmplitudes.append(strongestPeakInCurrentCue)
            }

            if cue < timing.cueCount {
                let remainingInterval = timing.cueInterval - timing.cueResponseDuration
                guard await wait(for: remainingInterval) else { return false }
            }
        }
        return true
    }

    private func runValidationCues() async -> Bool {
        for cue in 1...timing.cueCount {
            guard !Task.isCancelled else { return false }
            cueIndex = cue
            cuePulseID += 1
            guard await wait(for: timing.cueInterval) else { return false }
        }
        return true
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
        case .calibration:
            guard isAcceptingCalibrationSignal else { return }
            strongestPeakInCurrentCue = max(strongestPeakInCurrentCue ?? 0, event.amplitude)
        case .validation:
            validationDetectedCount += 1
        default:
            break
        }
    }

    private func finishCalibration() {
        guard let threshold = PeakAmplitudeCalibration.personalizedThreshold(from: calibrationAmplitudes) else {
            showIssue(.insufficientCalibration(detected: calibrationAmplitudes.count))
            return
        }
        candidateMinPeakAmplitude = threshold
        measurementCompleted = true
    }

    private func finishValidation() {
        guard PeakAmplitudeCalibration.validationPassed(detectedCount: validationDetectedCount),
              let candidateMinPeakAmplitude else {
            showIssue(.validationOutOfRange(detected: validationDetectedCount))
            return
        }

        profile = MeasurementCalibrationProfile(
            minPeakAmplitude: candidateMinPeakAmplitude,
            calibrationAmplitudes: calibrationAmplitudes,
            validationDetectedCount: validationDetectedCount
        )
        setStage(.ready)
    }

    private func resetCurrentRun() {
        cueIndex = 0
        cueHitID = 0
        measurementCompleted = false
        issue = nil
        strongestPeakInCurrentCue = nil
        isAcceptingCalibrationSignal = false
        if stage == .calibration {
            calibrationAmplitudes = []
            candidateMinPeakAmplitude = nil
            profile = nil
        } else {
            validationDetectedCount = 0
        }
    }

    private func resetExperiment() {
        calibrationAmplitudes = []
        candidateMinPeakAmplitude = nil
        validationDetectedCount = 0
        profile = nil
        issue = nil
    }

    private func showIssue(_ issue: Issue) {
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        measurementCompleted = false
        self.issue = issue
        stage = .signalIssue
        Task { await sampler.stop() }
    }

    private func setStage(_ newStage: Stage) {
        measurementTask?.cancel()
        stage = newStage
        cueIndex = 0
        measurementCompleted = newStage == .ready
        isMeasuring = false
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
        if stage == .ready, let threshold = store.candidateMinPeakAmplitude {
            store.validationDetectedCount = 10
            store.profile = MeasurementCalibrationProfile(
                minPeakAmplitude: threshold,
                calibrationAmplitudes: amplitudes,
                validationDetectedCount: 10
            )
        }
        return store
    }
}
#endif
