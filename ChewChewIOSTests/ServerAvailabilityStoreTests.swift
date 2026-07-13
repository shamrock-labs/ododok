import XCTest
@testable import ChewChewIOS

@MainActor
final class ServerAvailabilityStoreTests: XCTestCase {
    func testMonitor_retriesUntilDevServerBecomesAvailable() async {
        let checker = SequenceServerHealthChecker(results: [false, true])
        let store = ServerAvailabilityStore(
            environment: "dev",
            checker: checker,
            sleep: { _ in }
        )

        await store.monitor()

        XCTAssertEqual(store.status, .available)
        let callCount = await checker.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testMonitor_skipsProbeForProd() async {
        let checker = SequenceServerHealthChecker(results: [false])
        let store = ServerAvailabilityStore(
            environment: "prod",
            checker: checker,
            sleep: { _ in }
        )

        await store.monitor()

        XCTAssertEqual(store.status, .available)
        let callCount = await checker.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testRetryNow_keepsPreparingStateWhenServerIsUnavailable() async {
        let checker = SequenceServerHealthChecker(results: [false])
        let store = ServerAvailabilityStore(
            environment: "dev",
            checker: checker,
            sleep: { _ in }
        )

        await store.retryNow()

        XCTAssertEqual(store.status, .preparing)
    }
}

private actor SequenceServerHealthChecker: ServerHealthChecking {
    private var results: [Bool]
    private(set) var callCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func isAvailable() async -> Bool {
        callCount += 1
        return results.isEmpty ? false : results.removeFirst()
    }
}
