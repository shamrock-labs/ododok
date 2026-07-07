import CoreMotion
@testable import ChewChewIOS
import XCTest

final class AirPodsAutoStartGateTests: XCTestCase {

    func testDeniedPermission_blocksEvenWhenAirPodsConnected() {
        let decision = AirPodsAutoStartGate.decision(
            status: .denied,
            available: true,
            hasHeadphoneAudioRoute: true
        )

        XCTAssertEqual(decision, .block)
    }

    func testRestrictedPermission_blocksEvenWhenAirPodsConnected() {
        let decision = AirPodsAutoStartGate.decision(
            status: .restricted,
            available: true,
            hasHeadphoneAudioRoute: true
        )

        XCTAssertEqual(decision, .block)
    }

    func testUnavailableMotion_blocksEvenWhenAirPodsConnected() {
        let decision = AirPodsAutoStartGate.decision(
            status: .authorized,
            available: false,
            hasHeadphoneAudioRoute: true
        )

        XCTAssertEqual(decision, .block)
    }

    func testNotDetermined_requestsPermissionBeforeAnyAutoStart() {
        let decision = AirPodsAutoStartGate.decision(
            status: .notDetermined,
            available: true,
            hasHeadphoneAudioRoute: true
        )

        XCTAssertEqual(decision, .requestPermission)
    }

    func testAuthorizedWithoutAirPods_waitsForConnection() {
        let decision = AirPodsAutoStartGate.decision(
            status: .authorized,
            available: true,
            hasHeadphoneAudioRoute: false
        )

        XCTAssertEqual(decision, .waitForAirPodsConnection)
    }

    func testAuthorizedWithAirPods_startsCountdown() {
        let decision = AirPodsAutoStartGate.decision(
            status: .authorized,
            available: true,
            hasHeadphoneAudioRoute: true
        )

        XCTAssertEqual(decision, .startCountdown)
    }
}
