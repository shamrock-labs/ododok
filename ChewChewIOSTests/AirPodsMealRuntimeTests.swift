import CoreMotion
import Foundation
import XCTest
@testable import ChewChewIOS

@MainActor
final class AirPodsMealRuntimeTests: XCTestCase {
    func testChewPulseDeliveryGateCoalescesBackloggedVisualEvents() {
        var gate = ChewPulseDeliveryGate(minimumInterval: 0.2)

        XCTAssertTrue(gate.shouldDeliver(at: 10))
        XCTAssertFalse(gate.shouldDeliver(at: 10.05))
        XCTAssertFalse(gate.shouldDeliver(at: 10.19))
        XCTAssertTrue(gate.shouldDeliver(at: 10.2))
    }

    func testChewPulseDeliveryGateResetAllowsFirstEventOfNewSession() {
        var gate = ChewPulseDeliveryGate(minimumInterval: 0.2)

        XCTAssertTrue(gate.shouldDeliver(at: 10))
        gate.reset()

        XCTAssertTrue(gate.shouldDeliver(at: 10.01))
    }

    func testUpdatingAlertVolumeAlsoUpdatesRunningAudioFeedback() {
        let runtime = FakeAirPodsMealRuntimeServices()
        let store = makeStore(runtime: runtime)

        store.startEating()
        store.updateAlertVolume(0)

        XCTAssertEqual(runtime.audio.volume, 0, accuracy: 0.0001)
    }

    func testDisconnectingAirPodsBeforeThirtySecondsShowsShortSessionConfirm() {
        let runtime = FakeAirPodsMealRuntimeServices(now: Date(timeIntervalSince1970: 1_000))
        let store = makeStore(runtime: runtime)

        store.startEating()
        runtime.now = runtime.now.addingTimeInterval(29)

        XCTAssertTrue(store.isEating)

        runtime.airPodsMonitor.emitConnectionChanged(false)

        XCTAssertTrue(store.isEating)
        XCTAssertTrue(store.showShortSessionConfirm)
    }

    func testDisconnectingAirPodsAtThirtySecondsStopsMeasurement() {
        let runtime = FakeAirPodsMealRuntimeServices(now: Date(timeIntervalSince1970: 2_000))
        let store = makeStore(runtime: runtime)

        store.startEating()
        runtime.now = runtime.now.addingTimeInterval(30)

        XCTAssertTrue(store.isEating)

        runtime.airPodsMonitor.emitConnectionChanged(false)

        XCTAssertFalse(store.isEating)
        XCTAssertFalse(store.showShortSessionConfirm)
    }

    func testDSPChewDetectionTriggersChewPulse() async {
        let runtime = FakeAirPodsMealRuntimeServices()
        var pulseCount = 0
        let store = makeStore(runtime: runtime, onChewPulse: {
            pulseCount += 1
        })

        store.startEating()
        emitChewingMotionSamples(runtime.motion)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertGreaterThan(pulseCount, 0)

        store.discardCurrentSession()
    }

    func testFlatMotionDoesNotTriggerChewPulse() async {
        let runtime = FakeAirPodsMealRuntimeServices()
        var pulseCount = 0
        let store = makeStore(runtime: runtime, onChewPulse: {
            pulseCount += 1
        })

        store.startEating()
        for index in 0..<500 {
            runtime.motion.emit(makeSample(index: index, rotationY: 0))
        }
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(pulseCount, 0)

        store.discardCurrentSession()
    }

    func testMealSessionUsesPersonalizedPeakAmplitudeConfiguration() async {
        let runtime = FakeAirPodsMealRuntimeServices()
        var pulseCount = 0
        let store = makeStore(
            runtime: runtime,
            configuration: ChewDetectionConfiguration(minPeakAmplitude: 1),
            onChewPulse: { pulseCount += 1 }
        )

        store.startEating()
        emitChewingMotionSamples(runtime.motion)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(pulseCount, 0)
        store.discardCurrentSession()
    }

    func testStoppedSessionDoesNotTriggerChewPulseFromLaterSamples() async {
        let runtime = FakeAirPodsMealRuntimeServices()
        var pulseCount = 0
        let store = makeStore(runtime: runtime, onChewPulse: {
            pulseCount += 1
        })

        store.startEating()
        store.discardCurrentSession()
        emitChewingMotionSamples(runtime.motion)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(pulseCount, 0)
    }

    func testStoppingSessionDrainsQueuedSamplesBeforeBuildingStats() async {
        let runtime = FakeAirPodsMealRuntimeServices()
        let uploadFinished = expectation(description: "session stats uploaded")
        var uploadedStats: SessionStats?
        let store = makeStore(runtime: runtime, onSessionReadyForUpload: { _, stats in
            uploadedStats = stats
            uploadFinished.fulfill()
        })

        store.startEating()
        emitChewingMotionSamples(runtime.motion)
        store.stopEating()

        await fulfillment(of: [uploadFinished], timeout: 10)

        let totalAnalyzedSeconds = (uploadedStats?.chewingSeconds ?? 0) +
            (uploadedStats?.restSeconds ?? 0)
        XCTAssertEqual(totalAnalyzedSeconds, 10, accuracy: 0.0001)
        XCTAssertEqual(uploadedStats?.modelVersion, ChewDetectionEngine.modelVersion)
    }

    func testMealStartFreezesProfileIdEvenIfTheCacheContextChangesLater() async {
        let runtime = FakeAirPodsMealRuntimeServices()
        let firstProfileId = UUID()
        let secondProfileId = UUID()
        var context = MealChewDetectionContext(configuration: .standard, profileId: firstProfileId)
        let uploadFinished = expectation(description: "session output uploaded")
        var uploadedProfileId: UUID?
        let store = MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { output, _ in
                uploadedProfileId = output.chewDetectionProfileId
                uploadFinished.fulfill()
            },
            chewDetectionContext: { context },
            runtimeServices: runtime.services
        )

        store.startEating()
        context = MealChewDetectionContext(configuration: .standard, profileId: secondProfileId)
        emitChewingMotionSamples(runtime.motion)
        store.stopEating()

        await fulfillment(of: [uploadFinished], timeout: 3)
        XCTAssertEqual(uploadedProfileId, firstProfileId)
    }

    private func makeStore(
        runtime: FakeAirPodsMealRuntimeServices,
        configuration: ChewDetectionConfiguration = .standard,
        onSessionReadyForUpload: @escaping @MainActor (
            IMUSessionRecorder.Output,
            SessionStats?
        ) async -> Void = { _, _ in },
        onChewPulse: @escaping @MainActor () -> Void = {}
    ) -> MealSessionRuntimeStore {
        MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: onChewPulse,
            onPersistSnapshot: {},
            onSessionReadyForUpload: onSessionReadyForUpload,
            chewDetectionConfiguration: { configuration },
            runtimeServices: runtime.services
        )
    }

    private func emitChewingMotionSamples(_ motion: FakeAirPodsMotionService) {
        for index in 0..<500 {
            motion.emit(makeSample(index: index, rotationY: chewingRotationY(index: index)))
        }
    }

    private func chewingRotationY(index: Int) -> Double {
        let elapsed = Double(index) / 50.0
        return 0.08 * sin(2 * Double.pi * 1.4 * elapsed)
    }

    private func makeSample(index: Int, rotationY: Double) -> HeadphoneMotionSample {
        HeadphoneMotionSample(
            timestamp: Double(index) / 50.0,
            rotationRateMagnitude: abs(rotationY),
            userAccelerationMagnitude: 0,
            attitudeRoll: 0,
            attitudePitch: 0,
            attitudeYaw: 0,
            rotationX: 0,
            rotationY: rotationY,
            rotationZ: 0,
            gravityX: 0,
            gravityY: 0,
            gravityZ: 0,
            userAccelX: 0,
            userAccelY: 0,
            userAccelZ: 0,
            magneticFieldX: 0,
            magneticFieldY: 0,
            magneticFieldZ: 0,
            sensorLocation: "headphone_right"
        )
    }
}

@MainActor
private final class FakeAirPodsMealRuntimeServices {
    let motion = FakeAirPodsMotionService()
    let audio = FakeAirPodsAudioFeedbackService()
    let callMonitor = FakeAirPodsCallInterruptionMonitor()
    let activity = FakeAirPodsMealActivityController()
    let airPodsMonitor = FakeAirPodsConnectionMonitor()
    let readiness = FakeAirPodsMealReadinessService()
    let notification = FakeAirPodsInterruptionNotifier()
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    var services: MealSessionRuntimeServices {
        MealSessionRuntimeServices(
            makeMotionService: { self.motion },
            makeAudioFeedbackService: { self.audio },
            makeCallInterruptionMonitor: { self.callMonitor },
            makeActivityController: { self.activity },
            makeAirPodsConnectionMonitor: { self.airPodsMonitor },
            makeAirPodsAudioReadinessService: { self.readiness },
            makeStartCountdownController: { StartCountdownController() },
            notificationScheduler: notification,
            now: { self.now }
        )
    }
}

@MainActor
private final class FakeAirPodsMealReadinessService: AirPodsAudioReadinessServicing {
    func prepareAirPods() async -> Bool { true }
    func playCalibrationCue() {}
    func stop(deactivatingSession: Bool) {}
}

private final class FakeAirPodsMotionService: MealMotionServicing {
    var liveMotionUnavailableSource: IMUWaveformSource?
    var isDeviceMotionAvailable = true
    var authorizationStatus = CMAuthorizationStatus.authorized
    private var onSample: ((HeadphoneMotionSample) -> Void)?

    func start(
        onSample: @escaping (HeadphoneMotionSample) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onSample = onSample
    }

    func stop() {
        onSample = nil
    }

    func emit(_ sample: HeadphoneMotionSample) {
        onSample?(sample)
    }
}

private final class FakeAirPodsAudioFeedbackService: MealAudioFeedbackServicing {
    var volume: Float = 0.5

    func start() {}
    func stop() {}
    func playTone(for pace: ChewPaceSample) {}
}

private final class FakeAirPodsCallInterruptionMonitor: MealCallInterruptionMonitoring {
    var onCallStarted: (() -> Void)?
    var onCallEnded: (() -> Void)?

    func start() {}
    func stop() {}
}

private final class FakeAirPodsMealActivityController: MealActivityControlling {
    func start(startedAt: Date) {}
    func setPaused(_ paused: Bool, callActive: Bool) async {}
    func end() async {}
}

private final class FakeAirPodsInterruptionNotifier: MealInterruptionNotificationScheduling {
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func scheduleInterruptionPrompt() async {}
    func cancelInterruptionPrompt() {}
}

private final class FakeAirPodsConnectionMonitor: AirPodsConnectionMonitoring {
    var isConnected = true
    private var onRouteConnectionChanged: ((Bool) -> Void)?

    func start(onRouteConnectionChanged: @escaping (Bool) -> Void) {
        self.onRouteConnectionChanged = onRouteConnectionChanged
    }

    func stop() {
        onRouteConnectionChanged = nil
    }

    func emitConnectionChanged(_ connected: Bool) {
        isConnected = connected
        onRouteConnectionChanged?(connected)
    }
}
