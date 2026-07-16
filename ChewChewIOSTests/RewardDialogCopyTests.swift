import XCTest
@testable import ChewChewIOS

final class RewardDialogCopyTests: XCTestCase {
    func testFreezeGrantCopyShowsMilestoneAmountAndCurrentInventory() {
        let grant = RewardGrant(
            amount: 1,
            kind: .streakFreezeGranted(streakCount: 7, granted: 1, inventory: 2)
        )

        XCTAssertEqual(grant.title, "7일 연속 접속!")
        XCTAssertEqual(grant.amountText, "+1")
        XCTAssertEqual(grant.detailText, "프리즈를 받았어요")
        XCTAssertEqual(grant.inventoryText, "현재 프리즈 2개")
    }

    func testFreezeUseCopyShowsEveryDefendedDayAndCurrentInventory() {
        let grant = RewardGrant(
            amount: 2,
            kind: .streakFreezeUsed(consumed: 2, inventory: 1)
        )

        XCTAssertEqual(grant.title, "스트릭을 지켰어요")
        XCTAssertEqual(grant.amountText, "-2")
        XCTAssertEqual(grant.detailText, "2일을 쉬어 프리즈 2개를 사용했어요")
        XCTAssertEqual(grant.inventoryText, "현재 프리즈 1개")
    }

    func testCombinedFreezeCopyCommunicatesUseAndGrantInOneDialog() {
        let grant = RewardGrant(
            amount: 1,
            kind: .streakFreezeUsedAndGranted(
                consumed: 2,
                granted: 1,
                inventory: 1,
                streakCount: 7
            )
        )

        XCTAssertEqual(grant.title, "스트릭을 지키고 보상도 받았어요")
        XCTAssertNil(grant.amountText)
        XCTAssertEqual(grant.detailText, "2개 사용 · 1개 획득")
        XCTAssertEqual(grant.inventoryText, "현재 프리즈 1개")
    }

    func testExistingResetAndFirstDayCopyRemainUnchanged() {
        let reset = RewardGrant(amount: 0, kind: .streakReset)
        let firstDay = RewardGrant(amount: 0, kind: .streakFirstDay)

        XCTAssertEqual(reset.title, "스트릭이 끊겼어요")
        XCTAssertEqual(reset.detailText, "다시 시작해 볼까요?")
        XCTAssertNil(reset.inventoryText)
        XCTAssertEqual(firstDay.title, "1일째")
        XCTAssertEqual(firstDay.detailText, "스트릭을 시작했어요")
        XCTAssertNil(firstDay.inventoryText)
    }
}
