import XCTest
@testable import ChewChewIOS

/// 출석 멱등키 포맷 검증 — 서버(AttendanceService)가 같은 포맷으로 키를 유도·검증하므로,
/// 이 테스트가 깨지면 양 레포 포맷이 갈라져 이중 적립/적립 거부가 날 수 있다.
final class AttendanceKeyTests: XCTestCase {
    /// 2026-06-12 14:59 UTC = KST 23:59 (아직 6/12).
    func testAttendanceKeyFormat() {
        let date = ISO8601DateFormatter().date(from: "2026-06-12T14:59:00Z")!
        XCTAssertEqual(
            AppState.attendanceKey(deviceId: "device-1", now: date),
            "app-open-device-1-20260612"
        )
    }

    /// KST 자정 경계 — UTC 15:00을 넘으면 KST 기준 다음 날 키가 나와야 한다.
    func testAttendanceKeyUsesSeoulCalendarDay() {
        let beforeMidnight = ISO8601DateFormatter().date(from: "2026-06-12T14:59:59Z")!
        let afterMidnight = ISO8601DateFormatter().date(from: "2026-06-12T15:00:01Z")!
        XCTAssertEqual(
            AppState.attendanceKey(deviceId: "d", now: beforeMidnight),
            "app-open-d-20260612"
        )
        XCTAssertEqual(
            AppState.attendanceKey(deviceId: "d", now: afterMidnight),
            "app-open-d-20260613"
        )
    }
}
