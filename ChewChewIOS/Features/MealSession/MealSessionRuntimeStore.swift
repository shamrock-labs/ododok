import CoreMotion
import Foundation
import Observation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum MealSessionRuntimeRules {
    static func shouldConfirmShortSessionStop(startedAt: Date?, now: Date = Date()) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) < 60
    }

    static func shouldAutoResume(interruptionWasCall: Bool, shouldResume: Bool) -> Bool {
        shouldResume && !interruptionWasCall
    }

    static func shouldStartImmediately(status: CMAuthorizationStatus, available: Bool) -> Bool {
        status == .authorized && available
    }
}

@Observable
@MainActor
final class MealSessionRuntimeStore {
    private static let maxIMUWaveformSamples = 54
    static let idleIMUWaveformSamples: [Double] = (0..<maxIMUWaveformSamples).map { index in
        0.05 + sin(Double(index) * 0.42) * 0.015
    }

    private static let modelVersion = "dsp-chewcounter-1"

    private(set) var phase: MealSessionPhase = .idle
    var isEating: Bool { phase.isEating }
    var eatingStartedAt: Date? { phase.startedAt }
    var imuWaveformSamples: [Double] = MealSessionRuntimeStore.idleIMUWaveformSamples
    var imuWaveformSource: IMUWaveformSource = .idle
    var imuSampleCount: Int = 0
    var lastIMUSampleAt: Date?
    var startButtonHighlighted: Bool = false
    var pendingMealStartRequest: Bool = false
    var showShortSessionConfirm: Bool {
        get { phase.isConfirmingShortStop }
        set {
            if newValue {
                requestShortSessionConfirmation()
            } else {
                dismissShortSessionConfirmation()
            }
        }
    }
    var showAirPodsConnectionPrompt: Bool = false
    var startCountdownValue: Int?

    private let analytics: AnalyticsService
    private let onChewPulse: @MainActor () -> Void
    private let onPersistSnapshot: @MainActor () -> Void
    private let onSessionReadyForUpload: @MainActor (IMUSessionRecorder.Output, SessionStats?) async -> Void
    @ObservationIgnored private let runtimeServices: MealSessionRuntimeServices

    @ObservationIgnored private lazy var headphoneMotionService = runtimeServices.makeMotionService()
    @ObservationIgnored private var chewPulseTimer: Timer?
    @ObservationIgnored private var demoIMUWaveformTimer: Timer?
    @ObservationIgnored private var imuWaveformPhase: Double = 0
    @ObservationIgnored private lazy var callMonitor = runtimeServices.makeCallInterruptionMonitor()
    @ObservationIgnored private var interruptionWasCall = false
    @ObservationIgnored private var interruptionBeganAt: Date?
    @ObservationIgnored private lazy var backgroundKeepAlive = runtimeServices.makeAudioFeedbackService()
    @ObservationIgnored private var alertVolume: Float = 0.5
    @ObservationIgnored private lazy var mealActivity = runtimeServices.makeActivityController()
    @ObservationIgnored private lazy var mealAirPodsConnectionMonitor = runtimeServices.makeAirPodsConnectionMonitor()
    @ObservationIgnored private lazy var airPodsAutoStartCoordinator: AirPodsAutoStartCoordinator = {
        let coordinator = AirPodsAutoStartCoordinator(
            monitor: runtimeServices.makeAirPodsConnectionMonitor(),
            countdown: runtimeServices.makeStartCountdownController()
        )
        coordinator.onPromptVisibilityChange = { [weak self] isVisible in
            self?.showAirPodsConnectionPrompt = isVisible
        }
        coordinator.onCountdownValueChange = { [weak self] value in
            self?.startCountdownValue = value
        }
        return coordinator
    }()
    @ObservationIgnored private var chewCounter: ChewCounter?
    @ObservationIgnored private var imuSessionRecorder: IMUSessionRecorder?

    init(
        analytics: AnalyticsService,
        onChewPulse: @escaping @MainActor () -> Void,
        onPersistSnapshot: @escaping @MainActor () -> Void,
        onSessionReadyForUpload: @escaping @MainActor (IMUSessionRecorder.Output, SessionStats?) async -> Void,
        runtimeServices: MealSessionRuntimeServices = .live
    ) {
        self.analytics = analytics
        self.onChewPulse = onChewPulse
        self.onPersistSnapshot = onPersistSnapshot
        self.onSessionReadyForUpload = onSessionReadyForUpload
        self.runtimeServices = runtimeServices
    }

    var imuWaveformStatusText: String {
        imuWaveformSource.statusText
    }

    var isIMUWaveformLive: Bool {
        isEating && (imuWaveformSource.usesRealMotion || imuWaveformSource == .demo)
    }

    func updateAlertVolume(_ volume: Double) {
        alertVolume = Self.normalizedAlertVolume(volume)
        backgroundKeepAlive.volume = alertVolume
    }

    func startEating() {
        guard !isEating else { return }
        analytics.track(.mealSessionStarted())
        let now = runtimeServices.now()
        phase = .measuring(MealSessionMeasurementContext(startedAt: now))

        prepareEatingSession(startedAt: now)
        let counter = ChewCounter()
        chewCounter = counter
        startChewAnimationLoop()

        configureCallInterruptionHandling()
        configureMealAirPodsConnectionHandling()
        Task { [notificationScheduler = runtimeServices.notificationScheduler] in
            await notificationScheduler.requestAuthorizationIfNeeded()
        }
        startAudioFeedback(counter: counter)
        mealActivity.start(startedAt: now)

        if !startHeadphoneMotionLoop() {
            startDemoIMUWaveformLoop(source: imuWaveformSource)
        }
    }

    func stopEating() {
        guard isEating else { return }
        let startedAt = eatingStartedAt
        let endedAt = runtimeServices.now()
        let sessionDurationSec = startedAt.map { Int(endedAt.timeIntervalSince($0)) } ?? 0
        if let startedAt {
            phase = .analyzing(MealSessionAnalysisContext(startedAt: startedAt, endedAt: endedAt))
        } else {
            phase = .idle
        }
        let counter = stopEatingRuntime()
        onPersistSnapshot()

        chewCounter = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            let output = recorder.finalize(endedAt: endedAt)
            guard output.sampleCount > 0 else {
                phase = .idle
                analytics.track(.mealSessionAborted(reason: "no_samples", durationSec: sessionDurationSec))
                return
            }
            phase = .idle
            Task { [weak self] in
                let stats = await counter?.sessionStats(modelVersion: Self.modelVersion)
                await self?.onSessionReadyForUpload(output, stats)
            }
        } else {
            phase = .idle
        }
    }

    func discardCurrentSession() {
        guard isEating else { return }
        let startedAt = eatingStartedAt
        let endedAt = runtimeServices.now()
        let sessionDurationSec = startedAt.map { Int(endedAt.timeIntervalSince($0)) } ?? 0
        phase = .idle
        _ = stopEatingRuntime()
        onPersistSnapshot()
        chewCounter = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            _ = recorder.finalize(endedAt: endedAt)
        }
        analytics.track(.mealSessionAborted(reason: "user_discard", durationSec: sessionDurationSec))
    }

    func toggleEating() {
        if isEating {
            stopEating()
        } else {
            startEating()
        }
    }

    func resumeMeasurement() {
        guard isEating else {
            requestStartHighlight()
            return
        }
        if let began = interruptionBeganAt {
            imuSessionRecorder?.recordInterruptionGap(began: began, ended: runtimeServices.now())
        }
        interruptionWasCall = false
        interruptionBeganAt = nil
        runtimeServices.notificationScheduler.cancelInterruptionPrompt()
        if let startedAt = eatingStartedAt {
            phase = .measuring(MealSessionMeasurementContext(startedAt: startedAt))
        }
        Task { await self.mealActivity.setPaused(false) }
        _ = startHeadphoneMotionLoop()
    }

    func stopMeasurementFromNotification() {
        runtimeServices.notificationScheduler.cancelInterruptionPrompt()
        guard isEating else { return }
        if shouldConfirmShortSessionStop {
            showShortSessionConfirm = true
            return
        }
        stopEating()
    }

    func requestStartHighlight(duration: TimeInterval = 3) {
        startButtonHighlighted = true
        Task {
            try? await Task.sleep(for: .seconds(duration))
            startButtonHighlighted = false
        }
    }

    func requestMealStart() {
        guard !isEating else { return }
        pendingMealStartRequest = true
    }

    func consumePendingMealStartRequest() -> Bool {
        guard pendingMealStartRequest else { return false }
        pendingMealStartRequest = false
        return true
    }

    func handleNotificationAction(_ action: String, deepLink: String?) {
        switch action {
        case MealNotificationService.startActionId:
            requestMealStart()
        case MealNotificationService.resumeActionId:
            resumeMeasurement()
        case MealNotificationService.stopActionId:
            stopMeasurementFromNotification()
        case UNNotificationDefaultActionIdentifier:
            switch deepLink {
            case MealNotificationService.deepLinkResume:
                resumeMeasurement()
            case MealNotificationService.deepLinkStart:
                requestMealStart()
            default:
                break
            }
        default:
            break
        }
    }

    func beginMealStartAfterAirPodsReadiness(
        onCountdownStarted: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        let decision = AirPodsAutoStartGate.decision(
            status: headphoneMotionService.authorizationStatus,
            available: headphoneMotionService.isDeviceMotionAvailable,
            hasHeadphoneAudioRoute: airPodsAutoStartCoordinator.isHeadphoneConnected
        )
        continueMealStartAfterAirPodsDecision(
            decision,
            onCountdownStarted: onCountdownStarted,
            onFinished: onFinished
        )
    }

    func dismissAirPodsConnectionPrompt() {
        airPodsAutoStartCoordinator.dismissPromptAndStop()
    }

    func requestMotionPermission(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
        headphoneMotionService.start { [weak self] _ in
            self?.headphoneMotionService.stop()
            DispatchQueue.main.async {
                self?.analytics.track(.permissionResult(type: "motion", granted: true))
                onGranted()
            }
        } onError: { [weak self] _ in
            DispatchQueue.main.async {
                self?.analytics.track(.permissionResult(type: "motion", granted: false))
                onDenied()
            }
        }
    }

    func appendIMUWaveformSample(_ energy: Double) {
        let sample = min(1.0, max(0.0, energy))
        var samples = imuWaveformSamples
        samples.append(sample)
        if samples.count > Self.maxIMUWaveformSamples {
            samples.removeFirst(samples.count - Self.maxIMUWaveformSamples)
        }
        imuWaveformSamples = samples
    }

    func recordIMUEnergy(rotationRateMagnitude: Double, userAccelerationMagnitude: Double) {
        let energy = rotationRateMagnitude * 0.12 + userAccelerationMagnitude * 0.75
        appendIMUWaveformSample(energy)
    }

    func clearTransientRuntimeState() {
        pendingMealStartRequest = false
        startButtonHighlighted = false
        dismissShortSessionConfirmation()
        showAirPodsConnectionPrompt = false
        startCountdownValue = nil
        airPodsAutoStartCoordinator.dismissPromptAndStop()
    }

    func resetRuntimeState() {
        if isEating {
            stopEating()
        }
        phase = .idle
        resetIMUWaveform()
        imuWaveformSource = .idle
        clearTransientRuntimeState()
    }

    func requestShortSessionConfirmation() {
        guard let startedAt = eatingStartedAt else { return }
        phase = .confirmingShortStop(MealSessionMeasurementContext(startedAt: startedAt))
    }

    func dismissShortSessionConfirmation() {
        guard case let .confirmingShortStop(context) = phase else { return }
        phase = .measuring(context)
    }
}

private extension MealSessionRuntimeStore {
    static func normalizedAlertVolume(_ volume: Double) -> Float {
        guard volume.isFinite else { return 0.5 }
        return Float(max(0.0, min(1.0, volume)))
    }

    var shouldConfirmShortSessionStop: Bool {
        MealSessionRuntimeRules.shouldConfirmShortSessionStop(startedAt: eatingStartedAt, now: runtimeServices.now())
    }

    func prepareEatingSession(startedAt: Date) {
        imuSampleCount = 0
        lastIMUSampleAt = nil
        imuSessionRecorder = IMUSessionRecorder(startedAt: startedAt)
        interruptionWasCall = false
        interruptionBeganAt = nil
    }

    func configureCallInterruptionHandling() {
        callMonitor.onCallStarted = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.pauseMeasurementForCall()
            }
        }
        callMonitor.onCallEnded = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.showResumePromptAfterCall()
            }
        }
        callMonitor.start()
    }

    func configureMealAirPodsConnectionHandling() {
        mealAirPodsConnectionMonitor.start { [weak self] connected in
            guard let self, self.isEating, !connected else { return }
            if self.shouldConfirmShortSessionStop {
                self.showShortSessionConfirm = true
                return
            }
            self.stopEating()
        }
    }

    func continueMealStartAfterAirPodsDecision(
        _ decision: AirPodsAutoStartDecision,
        onCountdownStarted: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        switch decision {
        case .block:
            showAirPodsConnectionPrompt = true
        case .requestPermission:
            requestMotionPermission {
                if self.airPodsAutoStartCoordinator.isHeadphoneConnected {
                    self.beginMealStartCountdown(
                        onCountdownStarted: onCountdownStarted,
                        onFinished: onFinished
                    )
                } else {
                    self.waitForAirPodsConnectionThenStart(onFinished: onFinished)
                }
            } onDenied: {
                self.showAirPodsConnectionPrompt = true
            }
        case .waitForAirPodsConnection:
            waitForAirPodsConnectionThenStart(onFinished: onFinished)
        case .startCountdown:
            beginMealStartCountdown(
                onCountdownStarted: onCountdownStarted,
                onFinished: onFinished
            )
        }
    }

    func waitForAirPodsConnectionThenStart(onFinished: @escaping () -> Void) {
        airPodsAutoStartCoordinator.waitForConnectionThenStart(onFinished: onFinished)
    }

    func beginMealStartCountdown(onCountdownStarted: @escaping () -> Void, onFinished: @escaping () -> Void) {
        onCountdownStarted()
        airPodsAutoStartCoordinator.startCountdownWithDisconnectMonitoring(onFinished: onFinished)
    }

    func pauseMeasurementForCall() async {
        guard isEating else { return }
        await withMealBackgroundTask(named: "MealCallPause") {
            interruptionWasCall = true
            let pausedAt = runtimeServices.now()
            if interruptionBeganAt == nil { interruptionBeganAt = pausedAt }
            if let startedAt = eatingStartedAt {
                phase = .paused(MealSessionPauseContext(startedAt: startedAt, pausedAt: pausedAt, reason: .call))
            }
            stopHeadphoneMotionLoop()
            await mealActivity.setPaused(true, callActive: true)
        }
    }

    func showResumePromptAfterCall() async {
        guard isEating, interruptionWasCall else { return }
        await withMealBackgroundTask(named: "MealCallEnded") {
            await mealActivity.setPaused(true, callActive: false)
            await MealNotificationService.scheduleInterruptionPrompt()
        }
    }

    func withMealBackgroundTask(named name: String, operation: () async -> Void) async {
        #if canImport(UIKit)
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: name)
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }
        #endif
        await operation()
    }

    func startAudioFeedback(counter: ChewCounter) {
        backgroundKeepAlive.volume = alertVolume
        backgroundKeepAlive.start()
        let keepAlive = backgroundKeepAlive
        Task {
            await counter.setSustainedChewingHandler {
                Task { @MainActor in
                    let isChewing = await counter.isChewing
                    let avgInterval = await counter.avgInterval
                    keepAlive.playTone(for: ChewPaceSample(isChewing: isChewing, avgInterval: avgInterval))
                }
            }
        }
    }

    func stopEatingRuntime() -> ChewCounter? {
        stopHeadphoneMotionLoop()
        stopChewAnimationLoop()
        stopDemoIMUWaveformLoop()
        let counter = chewCounter
        Task { await counter?.setSustainedChewingHandler(nil) }
        backgroundKeepAlive.stop()
        callMonitor.onCallStarted = nil
        callMonitor.onCallEnded = nil
        callMonitor.stop()
        mealAirPodsConnectionMonitor.stop()
        interruptionWasCall = false
        interruptionBeganAt = nil
        runtimeServices.notificationScheduler.cancelInterruptionPrompt()
        mealActivity.end()
        resetIMUWaveform()
        imuWaveformSource = .idle
        return counter
    }

    func startChewAnimationLoop() {
        stopChewAnimationLoop()
        chewPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onChewPulse()
            }
        }
    }

    func stopChewAnimationLoop() {
        chewPulseTimer?.invalidate()
        chewPulseTimer = nil
    }

    func startHeadphoneMotionLoop() -> Bool {
        if let unavailableSource = headphoneMotionService.liveMotionUnavailableSource {
            imuWaveformSource = unavailableSource
            return false
        }

        switch headphoneMotionService.authorizationStatus {
        case .denied:
            imuWaveformSource = .denied
            return false
        case .restricted:
            imuWaveformSource = .restricted
            return false
        case .notDetermined:
            imuWaveformSource = .idle
            return false
        case .authorized:
            break
        @unknown default:
            break
        }

        guard headphoneMotionService.isDeviceMotionAvailable else {
            imuWaveformSource = .unavailable
            return false
        }

        stopDemoIMUWaveformLoop()
        imuWaveformSource = .connecting
        headphoneMotionService.start { [weak self] sample in
            self?.handleMotionSample(sample)
        } onError: { [weak self] message in
            guard let self else { return }
            if self.isEating {
                self.startDemoIMUWaveformLoop(source: .error(message))
            } else {
                self.imuWaveformSource = .error(message)
            }
        }

        return true
    }

    func handleMotionSample(_ sample: HeadphoneMotionSample) {
        imuWaveformSource = .live
        imuSampleCount += 1
        lastIMUSampleAt = Date()
        recordIMUEnergy(
            rotationRateMagnitude: sample.rotationRateMagnitude,
            userAccelerationMagnitude: sample.userAccelerationMagnitude
        )
        guard let recorder = imuSessionRecorder else { return }
        let row = MealSessionMotionMapper.makeRow(sample: sample, startedAt: recorder.startedAt)
        recorder.append(row)
        recorder.updateSensorLocation(sample.sensorLocation)
        feedChewCounter(row)
    }

    func feedChewCounter(_ row: IMURow) {
        guard let chewCounter else { return }
        Task {
            await chewCounter.feed(
                rotX: row.rotationX,
                rotY: row.rotationY,
                rotZ: row.rotationZ,
                accelX: row.userAccelX,
                accelY: row.userAccelY,
                accelZ: row.userAccelZ
            )
        }
    }

    func stopHeadphoneMotionLoop() {
        headphoneMotionService.stop()
    }

    func startDemoIMUWaveformLoop(source: IMUWaveformSource = .demo) {
        stopDemoIMUWaveformLoop()
        if isEating, !imuWaveformSource.usesRealMotion {
            imuWaveformSource = source
        }
        imuWaveformPhase = 0
        demoIMUWaveformTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appendNextDemoIMUWaveformSample()
            }
        }
    }

    func appendNextDemoIMUWaveformSample() {
        imuWaveformPhase += 0.38

        let bitePulse = pow(max(0, sin(imuWaveformPhase)), 2.8)
        let microMotion = sin(imuWaveformPhase * 3.1) * 0.08
        let energy = 0.12 + bitePulse * 0.72 + microMotion
        appendIMUWaveformSample(energy)
    }

    func stopDemoIMUWaveformLoop() {
        demoIMUWaveformTimer?.invalidate()
        demoIMUWaveformTimer = nil
    }

    func resetIMUWaveform() {
        imuWaveformPhase = 0
        imuWaveformSamples = Self.idleIMUWaveformSamples
    }
}

private enum MealSessionMotionMapper {
    static func makeRow(sample: HeadphoneMotionSample, startedAt: Date) -> IMURow {
        IMURow(
            tMach: sample.timestamp,
            tRelSec: Date().timeIntervalSince(startedAt),
            attitudeRoll: sample.attitudeRoll,
            attitudePitch: sample.attitudePitch,
            attitudeYaw: sample.attitudeYaw,
            rotationX: sample.rotationX,
            rotationY: sample.rotationY,
            rotationZ: sample.rotationZ,
            gravityX: sample.gravityX,
            gravityY: sample.gravityY,
            gravityZ: sample.gravityZ,
            userAccelX: sample.userAccelX,
            userAccelY: sample.userAccelY,
            userAccelZ: sample.userAccelZ,
            magneticFieldX: sample.magneticFieldX,
            magneticFieldY: sample.magneticFieldY,
            magneticFieldZ: sample.magneticFieldZ,
            sensorLocation: sample.sensorLocation
        )
    }
}
