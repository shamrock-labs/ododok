import XCTest
import AVFoundation
@testable import ChewChewIOS

/// AirPods/블루투스/유선 헤드폰 라우트 판정 순수 함수 테스트.
/// `AVAudioSessionPortDescription`은 직접 생성할 수 없으므로, portType만 비교하는
/// `AirPodsRouteDetector.isHeadphoneRoute(_:)` 최소 단위로 쪼개 테스트한다.
final class AirPodsRouteDetectionTests: XCTestCase {

    func testBluetoothA2DP_isHeadphoneRoute() {
        XCTAssertTrue(AirPodsRouteDetector.isHeadphoneRoute(.bluetoothA2DP))
    }

    func testBluetoothLE_isHeadphoneRoute() {
        XCTAssertTrue(AirPodsRouteDetector.isHeadphoneRoute(.bluetoothLE))
    }

    func testBluetoothHFP_isHeadphoneRoute() {
        XCTAssertTrue(AirPodsRouteDetector.isHeadphoneRoute(.bluetoothHFP))
    }

    func testHeadphones_isHeadphoneRoute() {
        XCTAssertTrue(AirPodsRouteDetector.isHeadphoneRoute(.headphones))
    }

    func testHeadsetMic_isHeadphoneRoute() {
        XCTAssertTrue(AirPodsRouteDetector.isHeadphoneRoute(.headsetMic))
    }

    func testBuiltInSpeaker_isNotHeadphoneRoute() {
        XCTAssertFalse(AirPodsRouteDetector.isHeadphoneRoute(.builtInSpeaker))
    }

    func testBuiltInReceiver_isNotHeadphoneRoute() {
        XCTAssertFalse(AirPodsRouteDetector.isHeadphoneRoute(.builtInReceiver))
    }
}
