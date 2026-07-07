import CoreMotion
import XCTest
@testable import ChewChewIOS

@MainActor
final class MealSessionPhaseTests: XCTestCase {
    func testInitialPhaseIsIdle() {
        let store = makeStore()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.isEating)
        XCTAssertNil(store.eatingStartedAt)
        XCTAssertFalse(store.showShortSessionConfirm)
    }

    func testStartEatingTransitionsToMeasuring() {
        let store = makeStore()

        store.startEating()

        guard case let .measuring(context) = store.phase else {
            return XCTFail("Expected measuring phase, got \(store.phase)")
        }
        XCTAssertTrue(store.isEating)
        XCTAssertEqual(store.eatingStartedAt, context.startedAt)

        store.discardCurrentSession()
    }

    func testShortSessionConfirmationIsPhaseDerived() {
        let store = makeStore()
        store.startEating()

        store.requestShortSessionConfirmation()

        guard case let .confirmingShortStop(context) = store.phase else {
            return XCTFail("Expected confirmingShortStop phase, got \(store.phase)")
        }
        XCTAssertTrue(store.isEating)
        XCTAssertEqual(store.eatingStartedAt, context.startedAt)
        XCTAssertTrue(store.showShortSessionConfirm)

        store.dismissShortSessionConfirmation()

        XCTAssertFalse(store.showShortSessionConfirm)
        guard case let .measuring(measuringContext) = store.phase else {
            return XCTFail("Expected measuring phase after dismiss, got \(store.phase)")
        }
        XCTAssertEqual(measuringContext.startedAt, context.startedAt)

        store.discardCurrentSession()
    }

    func testNotificationStopForSubMinuteSessionTransitionsToConfirmingShortStop() {
        let store = makeStore()
        store.startEating()

        store.stopMeasurementFromNotification()

        XCTAssertTrue(store.isEating)
        XCTAssertTrue(store.showShortSessionConfirm)
        guard case .confirmingShortStop = store.phase else {
            return XCTFail("Expected confirmingShortStop phase, got \(store.phase)")
        }

        store.discardCurrentSession()
    }

    func testDiscardCurrentSessionReturnsToIdle() {
        let store = makeStore()
        store.startEating()
        store.requestShortSessionConfirmation()

        store.discardCurrentSession()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.isEating)
        XCTAssertNil(store.eatingStartedAt)
        XCTAssertFalse(store.showShortSessionConfirm)
    }

    func testStartEatingUsesInjectedRuntimeServices() async {
        let runtime = FakeMealSessionRuntimeServices()
        let store = makeStore(runtime: runtime)

        store.startEating()
        await Task.yield()

        XCTAssertEqual(runtime.motion.startCallCount, 1)
        XCTAssertEqual(runtime.audio.startCallCount, 1)
        XCTAssertEqual(runtime.callMonitor.startCallCount, 1)
        XCTAssertNotNil(runtime.activity.startedAt)
        XCTAssertEqual(runtime.notification.requestAuthorizationCallCount, 1)

        store.discardCurrentSession()
    }

    func testCallInterruptionEventPausesInjectedRuntimeServices() async {
        let runtime = FakeMealSessionRuntimeServices()
        let store = makeStore(runtime: runtime)
        store.startEating()

        runtime.callMonitor.onCallStarted?()
        try? await Task.sleep(for: .milliseconds(20))

        guard case .paused = store.phase else {
            return XCTFail("Expected paused phase, got \(store.phase)")
        }
        XCTAssertEqual(runtime.motion.stopCallCount, 1)
        XCTAssertEqual(runtime.activity.pauseEvents, [.init(paused: true, callActive: true)])

        store.discardCurrentSession()
    }

    private func makeStore(runtime: FakeMealSessionRuntimeServices = FakeMealSessionRuntimeServices()) -> MealSessionRuntimeStore {
        MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { _, _ in },
            runtimeServices: runtime.services
        )
    }
}

private final class FakeMealSessionRuntimeServices {
    let motion = FakeMotionService()
    let audio = FakeAudioFeedbackService()
    let callMonitor = FakeCallInterruptionMonitor()
    let activity = FakeMealActivityController()
    let airPodsMonitor = FakeAirPodsConnectionMonitor()
    let notification = FakeInterruptionNotifier()
    var currentDate = Date()

    var services: MealSessionRuntimeServices {
        MealSessionRuntimeServices(
            makeMotionService: { self.motion },
            makeAudioFeedbackService: { self.audio },
            makeCallInterruptionMonitor: { self.callMonitor },
            makeActivityController: { self.activity },
            makeAirPodsConnectionMonitor: { self.airPodsMonitor },
            makeStartCountdownController: { StartCountdownController() },
            notificationScheduler: notification,
            now: { self.currentDate }
        )
    }
}

private final class FakeMotionService: MealMotionServicing {
    var liveMotionUnavailableSource: IMUWaveformSource?
    var isDeviceMotionAvailable = true
    var authorizationStatus: CMAuthorizationStatus = .authorized
    var startCallCount = 0
    var stopCallCount = 0

    func start(
        onSample: @escaping (HeadphoneMotionSample) -> Void,
        onError: @escaping (String) -> Void
    ) {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class FakeAudioFeedbackService: MealAudioFeedbackServicing {
    var volume: Float = 0.5
    var startCallCount = 0
    var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func playTone(for pace: ChewPaceSample) {}
}

private final class FakeCallInterruptionMonitor: MealCallInterruptionMonitoring {
    var onCallStarted: (() -> Void)?
    var onCallEnded: (() -> Void)?
    var startCallCount = 0
    var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
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

private final class FakeMealActivityController: MealActivityControlling {
    struct PauseEvent: Equatable {
        let paused: Bool
        let callActive: Bool
    }

    var startedAt: Date?
    var pauseEvents: [PauseEvent] = []
    var endCallCount = 0

    func start(startedAt: Date) {
        self.startedAt = startedAt
    }

    func setPaused(_ paused: Bool, callActive: Bool) async {
        pauseEvents.append(.init(paused: paused, callActive: callActive))
    }

    func end() {
        endCallCount += 1
    }
}

private final class FakeInterruptionNotifier: MealInterruptionNotificationScheduling {
    var requestAuthorizationCallCount = 0

    func requestAuthorizationIfNeeded() async -> Bool {
        requestAuthorizationCallCount += 1
        return true
    }

    func scheduleInterruptionPrompt() async {}

    func cancelInterruptionPrompt() {}
}
