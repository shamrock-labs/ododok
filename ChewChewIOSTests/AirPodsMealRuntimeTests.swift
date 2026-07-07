import XCTest
@testable import ChewChewIOS

@MainActor
final class AirPodsMealRuntimeTests: XCTestCase {
    func testDisconnectingAirPodsDuringMealStopsMeasurement() {
        let monitor = FakeAirPodsConnectionMonitor()
        let store = MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { _, _ in },
            mealAirPodsConnectionMonitor: monitor
        )

        store.startEating()

        XCTAssertTrue(store.isEating)

        monitor.emitConnectionChanged(false)

        XCTAssertFalse(store.isEating)
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
