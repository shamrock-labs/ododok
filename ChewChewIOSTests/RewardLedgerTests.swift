import XCTest
@testable import ChewChewIOS

final class RewardLedgerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RewardLedger.resetAll()
    }

    // MARK: - Attendance

    func testAttendanceFirstClaim_grants2() {
        let result = RewardLedger.claimDailyAttendance()
        XCTAssertEqual(result, 2)
    }

    func testAttendanceSameDayIdempotent() {
        let first = RewardLedger.claimDailyAttendance()
        let second = RewardLedger.claimDailyAttendance()
        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 0)
    }

    // MARK: - Session accrual

    func testAccrueWithChewCount300_grants15() {
        // 300 × 0.05 = 15
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        XCTAssertEqual(result, 15)
    }

    func testAccrueWithChewCountNil_grants0() {
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: nil)
        XCTAssertEqual(result, 0)
    }

    func testAccrueWithChewCountZero_grants0() {
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: 0)
        XCTAssertEqual(result, 0)
    }

    func testAccrueSameSessionIdempotent() {
        let id = UUID()
        let first = RewardLedger.accrue(forSession: id, chewCount: 300)
        let second = RewardLedger.accrue(forSession: id, chewCount: 300)
        XCTAssertEqual(first, 15)
        XCTAssertEqual(second, 0)
    }

    // MARK: - Daily cap

    func testDailyCapAt500() {
        // Accrue 495 via multiple sessions, then try to add 15 more → only 5 granted
        // 33 sessions × 15 = 495
        for _ in 0..<33 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        }
        // Daily total is now 495; next 15-point attempt should only yield 5
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        XCTAssertEqual(result, 5)
    }
}
