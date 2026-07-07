import XCTest
import CoreMotion
@testable import ChewChewIOS

/// REQ-01 — shouldStartImmediately 가드 결정 함수 단위 테스트.
/// CoreMotion 권한 status × available 조합 전체를 검증한다.
final class MotionPermissionGuardTests: XCTestCase {

    // MARK: - .authorized

    func testAuthorized_available_returnsTrue() {
        XCTAssertTrue(MealSessionRuntimeRules.shouldStartImmediately(status: .authorized, available: true))
    }

    func testAuthorized_notAvailable_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .authorized, available: false))
    }

    // MARK: - .notDetermined

    func testNotDetermined_available_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .notDetermined, available: true))
    }

    func testNotDetermined_notAvailable_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .notDetermined, available: false))
    }

    // MARK: - .denied

    func testDenied_available_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .denied, available: true))
    }

    func testDenied_notAvailable_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .denied, available: false))
    }

    // MARK: - .restricted

    func testRestricted_available_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .restricted, available: true))
    }

    func testRestricted_notAvailable_returnsFalse() {
        XCTAssertFalse(MealSessionRuntimeRules.shouldStartImmediately(status: .restricted, available: false))
    }
}
