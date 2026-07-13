import XCTest
@testable import ChewChewIOS

@MainActor
final class MeasurementOnboardingStoreTests: XCTestCase {
    func testConnectedUserCanMoveFromIntroToRestMeasurement() {
        let store = MeasurementOnboardingStore(isAirPodsConnected: true)

        store.moveForward()
        XCTAssertEqual(store.stage, .connection)

        store.moveForward()
        XCTAssertEqual(store.stage, .rest)
    }

    func testDisconnectedUserCannotLeaveConnectionStep() {
        let store = MeasurementOnboardingStore(isAirPodsConnected: false)

        store.moveForward()
        store.moveForward()

        XCTAssertEqual(store.stage, .connection)
    }

    func testMeasurementMustFinishBeforeMovingForward() async {
        let store = MeasurementOnboardingStore(
            stage: .rest,
            isAirPodsConnected: true,
            timing: .init(tickCount: 1, tickInterval: .milliseconds(1))
        )

        store.moveForward()
        XCTAssertEqual(store.stage, .rest)

        store.startMeasurement()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(store.measurementCompleted)

        store.moveForward()
        XCTAssertEqual(store.stage, .chew)
    }
}
