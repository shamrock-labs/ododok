import XCTest

/// REQ-05: 설정 '계정 삭제' UI 진입점 검증.
/// gear 버튼 → SettingsView → '계정 삭제' 탭 → 확인 다이얼로그 표시까지.
@MainActor
final class SettingsDeleteDataUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-skipAttendanceDialog", "-useNoopRemote"]
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testSettingsSheet_opensFromGearButton() {
        app.launch()

        let gearButton = app.buttons["gearshape.fill"]
        XCTAssertTrue(gearButton.waitForExistence(timeout: 10), "gear 버튼이 HomeView에 있어야 한다")
        gearButton.tap()

        XCTAssertTrue(
            app.staticTexts["설정"].waitForExistence(timeout: 5),
            "SettingsView가 '설정' 타이틀과 함께 열려야 한다"
        )
    }

    func testDeleteMyData_showsConfirmationDialog() {
        app.launch()
        openSettingsAndTapDelete()
    }

    func testDeleteMyData_cancelDoesNothing() {
        app.launch()
        openSettingsAndTapDelete()

        // 다이얼로그 취소 (confirmationDialog는 popover로 표시 → dismiss 영역 탭이 취소)
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 3), "팝오버 dismiss 영역이 있어야 한다")
        dismissRegion.tap()

        // 설정 화면이 여전히 열려 있어야 함
        XCTAssertTrue(
            app.staticTexts["설정"].waitForExistence(timeout: 3),
            "취소 후 SettingsView가 그대로 열려 있어야 한다"
        )
    }

    /// gear → SettingsView 정착 대기 → '계정 삭제' 탭 → 확인 다이얼로그 타이틀 등장까지.
    private func openSettingsAndTapDelete() {
        let gearButton = app.buttons["gearshape.fill"]
        XCTAssertTrue(gearButton.waitForExistence(timeout: 10), "gear 버튼이 HomeView에 있어야 한다")
        gearButton.tap()

        // 설정 시트 정착 대기
        XCTAssertTrue(app.staticTexts["설정"].waitForExistence(timeout: 10), "SettingsView가 열려야 한다")

        let deleteButton = app.buttons["DeleteMyData"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "'계정 삭제' 버튼이 있어야 한다")
        deleteButton.tap()

        XCTAssertTrue(app.staticTexts["계정을 삭제할까요?"].waitForExistence(timeout: 5), "confirmationDialog 타이틀이 표시되어야 한다")
    }
}
