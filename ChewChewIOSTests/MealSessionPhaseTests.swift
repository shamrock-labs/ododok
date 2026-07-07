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

        store.showShortSessionConfirm = true

        guard case let .confirmingShortStop(context) = store.phase else {
            return XCTFail("Expected confirmingShortStop phase, got \(store.phase)")
        }
        XCTAssertTrue(store.isEating)
        XCTAssertEqual(store.eatingStartedAt, context.startedAt)
        XCTAssertTrue(store.showShortSessionConfirm)

        store.showShortSessionConfirm = false

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
        store.showShortSessionConfirm = true

        store.discardCurrentSession()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.isEating)
        XCTAssertNil(store.eatingStartedAt)
        XCTAssertFalse(store.showShortSessionConfirm)
    }

    private func makeStore() -> MealSessionRuntimeStore {
        MealSessionRuntimeStore(
            analytics: NoopAnalytics(),
            onChewPulse: {},
            onPersistSnapshot: {},
            onSessionReadyForUpload: { _, _ in }
        )
    }
}
