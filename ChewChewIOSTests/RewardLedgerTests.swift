import XCTest
@testable import ChewChewIOS

final class RewardLedgerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RewardLedger.resetAll()
    }

    // MARK: - Attendance

    func testAttendanceFirstClaim_grants10() {
        let result = RewardLedger.claimDailyAttendance()
        XCTAssertEqual(result, 10)
    }

    func testAttendanceSameDayIdempotent() {
        let first = RewardLedger.claimDailyAttendance()
        let second = RewardLedger.claimDailyAttendance()
        XCTAssertEqual(first, 10)
        XCTAssertEqual(second, 0)
    }

    // MARK: - Session accrual

    func testAccrueWithChewCount300_grants45() {
        // 300 × 0.15 = 45
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        XCTAssertEqual(result, 45)
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
        XCTAssertEqual(first, 45)
        XCTAssertEqual(second, 0)
    }

    // MARK: - Daily cap

    func testDailyCapAt300() {
        // Accrue 270 via 6 sessions × 45, then try 45 more → cap leaves only 30 grantable.
        for _ in 0..<6 {
            RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        }
        let result = RewardLedger.accrue(forSession: UUID(), chewCount: 300)
        XCTAssertEqual(result, 30)
    }
}
