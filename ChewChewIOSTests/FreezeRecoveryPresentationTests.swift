import XCTest
@testable import ChewChewIOS

final class FreezeRecoveryPresentationTests: XCTestCase {
    func testRecoveryAvailableOffersUseAndSkipWithEveryMissedDate() {
        let presentation = FreezeRecoveryPresentation.make(status: status(
            .recoveryAvailable,
            missedDates: ["2026-07-14", "2026-07-15"],
            required: 2,
            inventory: 2
        ))

        XCTAssertEqual(presentation.title, "스트릭을 이어갈까요?")
        XCTAssertEqual(presentation.primaryTitle, "프리즈 2개 사용하기")
        XCTAssertEqual(presentation.secondaryTitle, "사용하지 않기")
        XCTAssertEqual(presentation.quantityText, "필요 2개 · 보유 2개")
        XCTAssertEqual(presentation.missedDateTexts, ["7월 14일", "7월 15일"])
    }

    func testInsufficientOffersOnlyConfirmationAndExplainsNoPartialUse() {
        let presentation = FreezeRecoveryPresentation.make(status: status(
            .insufficient,
            missedDates: ["2026-07-14", "2026-07-15"],
            required: 2,
            inventory: 1
        ))

        XCTAssertEqual(presentation.title, "스트릭이 새로 시작돼요")
        XCTAssertEqual(presentation.supportingText, "프리즈는 부분 사용하지 않아요")
        XCTAssertEqual(presentation.primaryTitle, "확인")
        XCTAssertNil(presentation.secondaryTitle)
        XCTAssertEqual(presentation.quantityText, "필요 2개 · 보유 1개")
        XCTAssertEqual(presentation.missedDateTexts, ["7월 14일", "7월 15일"])
    }

    private func status(
        _ recoveryStatus: AttendanceRecoveryStatus,
        missedDates: [String],
        required: Int,
        inventory: Int
    ) -> AttendanceStatusDTO {
        AttendanceStatusDTO(
            asOf: "2026-07-16",
            status: recoveryStatus,
            missedDates: missedDates,
            requiredFreezes: required,
            freezeInventory: inventory
        )
    }
}
