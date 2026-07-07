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

    var isEating: Bool = false
    private(set) var eatingStartedAt: Date?
    var imuWaveformSamples: [Double] = MealSessionRuntimeStore.idleIMUWaveformSamples
    var imuWaveformSource: IMUWaveformSource = .idle
    var imuSampleCount: Int = 0
    var lastIMUSampleAt: Date?
    var startButtonHighlighted: Bool = false
    var pendingMealStartRequest: Bool = false
    var showShortSessionConfirm: Bool = false
    var showAirPodsConnectionPrompt: Bool = false

    private let analytics: AnalyticsService
    private let onChewPulse: @MainActor () -> Void
    private let onPersistSnapshot: @MainActor () -> Void
    private let onSessionReadyForUpload: @MainActor (IMUSessionRecorder.Output, SessionStats?) async -> Void

    @ObservationIgnored private lazy var headphoneMotionService = HeadphoneMotionService()
    @ObservationIgnored private var chewPulseTimer: Timer?
    @ObservationIgnored private var demoIMUWaveformTimer: Timer?
    @ObservationIgnored private var imuWaveformPhase: Double = 0
    @ObservationIgnored private let callMonitor = CallInterruptionMonitor()
    @ObservationIgnored private var interruptionWasCall = false
    @ObservationIgnored private var interruptionBeganAt: Date?
    @ObservationIgnored private let backgroundKeepAlive = BackgroundAudioKeepAlive()
    @ObservationIgnored private var alertVolume: Float = 0.5
    @ObservationIgnored private let mealActivity = MealActivityController()
    @ObservationIgnored private var chewCounter: ChewCounter?
    @ObservationIgnored private var imuSessionRecorder: IMUSessionRecorder?

    init(
        analytics: AnalyticsService,
        onChewPulse: @escaping @MainActor () -> Void,
        onPersistSnapshot: @escaping @MainActor () -> Void,
        onSessionReadyForUpload: @escaping @MainActor (IMUSessionRecorder.Output, SessionStats?) async -> Void
    ) {
        self.analytics = analytics
        self.onChewPulse = onChewPulse
        self.onPersistSnapshot = onPersistSnapshot
        self.onSessionReadyForUpload = onSessionReadyForUpload
    }

    var imuWaveformStatusText: String {
        imuWaveformSource.statusText
    }

    var isIMUWaveformLive: Bool {
        isEating && (imuWaveformSource.usesRealMotion || imuWaveformSource == .demo)
    }

    func updateAlertVolume(_ volume: Double) {
        alertVolume = Self.normalizedAlertVolume(volume)
    }

    func startEating() {
        guard !isEating else { return }
        isEating = true
        analytics.track(.mealSessionStarted())
        let now = Date()
        eatingStartedAt = now

        prepareEatingSession(startedAt: now)
        let counter = ChewCounter()
        chewCounter = counter
        startChewAnimationLoop()

        configureCallInterruptionHandling()
        Task { await MealNotificationService.requestAuthorizationIfNeeded() }
        startAudioFeedback(counter: counter)
        mealActivity.start(startedAt: now)

        if !startHeadphoneMotionLoop() {
            startDemoIMUWaveformLoop(source: imuWaveformSource)
        }
    }

    func stopEating() {
        guard isEating else { return }
        isEating = false
        let sessionDurationSec = eatingStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        eatingStartedAt = nil
        let counter = stopEatingRuntime()
        onPersistSnapshot()

        chewCounter = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            let endedAt = Date()
            let output = recorder.finalize(endedAt: endedAt)
            guard output.sampleCount > 0 else {
                analytics.track(.mealSessionAborted(reason: "no_samples", durationSec: sessionDurationSec))
                return
            }
            Task { [weak self] in
                let stats = await counter?.sessionStats(modelVersion: Self.modelVersion)
                await self?.onSessionReadyForUpload(output, stats)
            }
        }
    }

    func discardCurrentSession() {
        guard isEating else { return }
        isEating = false
        let sessionDurationSec = eatingStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        eatingStartedAt = nil
        _ = stopEatingRuntime()
        onPersistSnapshot()
        chewCounter = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            _ = recorder.finalize(endedAt: Date())
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
            imuSessionRecorder?.recordInterruptionGap(began: began, ended: Date())
        }
        interruptionWasCall = false
        interruptionBeganAt = nil
        MealNotificationService.cancelInterruptionPrompt()
        Task { await self.mealActivity.setPaused(false) }
        _ = startHeadphoneMotionLoop()
    }

    func stopMeasurementFromNotification() {
        MealNotificationService.cancelInterruptionPrompt()
        guard isEating else { return }
        if MealSessionRuntimeRules.shouldConfirmShortSessionStop(startedAt: eatingStartedAt) {
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
        showShortSessionConfirm = false
        showAirPodsConnectionPrompt = false
    }

    func resetRuntimeState() {
        if isEating {
            stopEating()
        }
        isEating = false
        eatingStartedAt = nil
        resetIMUWaveform()
        imuWaveformSource = .idle
        clearTransientRuntimeState()
    }

    private static func normalizedAlertVolume(_ volume: Double) -> Float {
        guard volume.isFinite else { return 0.5 }
        return Float(max(0.0, min(1.0, volume)))
    }

    private func prepareEatingSession(startedAt: Date) {
        imuSampleCount = 0
        lastIMUSampleAt = nil
        imuSessionRecorder = IMUSessionRecorder(startedAt: startedAt)
        interruptionWasCall = false
        interruptionBeganAt = nil
    }

    private func configureCallInterruptionHandling() {
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

    private func pauseMeasurementForCall() async {
        guard isEating else { return }
        await withMealBackgroundTask(named: "MealCallPause") {
            interruptionWasCall = true
            if interruptionBeganAt == nil { interruptionBeganAt = Date() }
            stopHeadphoneMotionLoop()
            await mealActivity.setPaused(true, callActive: true)
        }
    }

    private func showResumePromptAfterCall() async {
        guard isEating, interruptionWasCall else { return }
        await withMealBackgroundTask(named: "MealCallEnded") {
            await mealActivity.setPaused(true, callActive: false)
            await MealNotificationService.scheduleInterruptionPrompt()
        }
    }

    private func withMealBackgroundTask(named name: String, operation: () async -> Void) async {
        #if canImport(UIKit)
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: name)
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }
        #endif
        await operation()
    }

    private func startAudioFeedback(counter: ChewCounter) {
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

    private func stopEatingRuntime() -> ChewCounter? {
        stopHeadphoneMotionLoop()
        stopChewAnimationLoop()
        stopDemoIMUWaveformLoop()
        let counter = chewCounter
        Task { await counter?.setSustainedChewingHandler(nil) }
        backgroundKeepAlive.stop()
        callMonitor.onCallStarted = nil
        callMonitor.onCallEnded = nil
        callMonitor.stop()
        interruptionWasCall = false
        interruptionBeganAt = nil
        MealNotificationService.cancelInterruptionPrompt()
        mealActivity.end()
        resetIMUWaveform()
        imuWaveformSource = .idle
        return counter
    }

    private func startChewAnimationLoop() {
        stopChewAnimationLoop()
        chewPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { [weak self] _ in
            self?.onChewPulse()
        }
    }

    private func stopChewAnimationLoop() {
        chewPulseTimer?.invalidate()
        chewPulseTimer = nil
    }

    private func startHeadphoneMotionLoop() -> Bool {
        #if targetEnvironment(simulator)
        imuWaveformSource = .simulator
        return false
        #else
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
        #endif
    }

    private func handleMotionSample(_ sample: HeadphoneMotionSample) {
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

    private func feedChewCounter(_ row: IMURow) {
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

    private func stopHeadphoneMotionLoop() {
        #if !targetEnvironment(simulator)
        headphoneMotionService.stop()
        #endif
    }

    private func startDemoIMUWaveformLoop(source: IMUWaveformSource = .demo) {
        stopDemoIMUWaveformLoop()
        if isEating, !imuWaveformSource.usesRealMotion {
            imuWaveformSource = source
        }
        imuWaveformPhase = 0
        demoIMUWaveformTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.imuWaveformPhase += 0.38

            let bitePulse = pow(max(0, sin(self.imuWaveformPhase)), 2.8)
            let microMotion = sin(self.imuWaveformPhase * 3.1) * 0.08
            let energy = 0.12 + bitePulse * 0.72 + microMotion
            self.appendIMUWaveformSample(energy)
        }
    }

    private func stopDemoIMUWaveformLoop() {
        demoIMUWaveformTimer?.invalidate()
        demoIMUWaveformTimer = nil
    }

    private func resetIMUWaveform() {
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
