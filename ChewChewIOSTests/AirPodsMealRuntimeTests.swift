import XCTest
@testable import ChewChewIOS

@MainActor
final class AirPodsMealRuntimeTests: XCTestCase {
    func testUpdatingAlertVolumeAlsoUpdatesRunningAudioFeedback() {
        let keepAlive = FakeMealAudioFeedbackKeepAlive()
        let store = MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { _, _ in },
            backgroundKeepAlive: keepAlive
        )

        store.startEating()
        store.updateAlertVolume(0)

        XCTAssertEqual(keepAlive.volume, 0, accuracy: 0.0001)
    }

    func testDisconnectingAirPodsWithinOneMinuteShowsShortSessionConfirm() {
        let monitor = FakeAirPodsConnectionMonitor()
        var now = Date(timeIntervalSince1970: 1_000)
        let store = MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { _, _ in },
            mealAirPodsConnectionMonitor: monitor,
            dateProvider: { now }
        )

        store.startEating()
        now = now.addingTimeInterval(59)

        XCTAssertTrue(store.isEating)

        monitor.emitConnectionChanged(false)

        XCTAssertTrue(store.isEating)
        XCTAssertTrue(store.showShortSessionConfirm)
    }

    func testDisconnectingAirPodsAfterOneMinuteStopsMeasurement() {
        let monitor = FakeAirPodsConnectionMonitor()
        var now = Date(timeIntervalSince1970: 2_000)
        let store = MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { _, _ in },
            mealAirPodsConnectionMonitor: monitor,
            dateProvider: { now }
        )

        store.startEating()
        now = now.addingTimeInterval(60)

        XCTAssertTrue(store.isEating)

        monitor.emitConnectionChanged(false)

        XCTAssertFalse(store.isEating)
        XCTAssertFalse(store.showShortSessionConfirm)
    }
}

private final class FakeMealAudioFeedbackKeepAlive: MealAudioFeedbackKeeping {
    var volume: Float = 0.5

    func start() {}
    func stop() {}
    func playTone(for pace: ChewPaceSample) {}
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
