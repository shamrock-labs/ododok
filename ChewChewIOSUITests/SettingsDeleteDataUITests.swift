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
        app.launchArguments = [
            "-resetState",
            "-skipOnboarding",
            "-skipAttendanceDialog",
            "-useNoopRemote",
            "-forceLogin",
        ]
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testSettingsSheet_opensFromGearButton() {
        app.launch()

        let gearButton = app.buttons["gearshape"]
        XCTAssertTrue(gearButton.waitForExistence(timeout: 10), "gear 버튼이 HomeView에 있어야 한다")
        gearButton.tap()

        XCTAssertTrue(
            app.staticTexts["설정"].waitForExistence(timeout: 5),
            "SettingsView가 '설정' 타이틀과 함께 열려야 한다"
        )
        let personalizationButton = app.buttons["ChewDetectionPersonalization"]
        XCTAssertTrue(
            personalizationButton.waitForExistence(timeout: 5),
            "씹기 감지 맞추기 진입점이 측정 설정에 있어야 한다"
        )
        personalizationButton.tap()
        let primaryButton = app.buttons["MeasurementOnboardingPrimary"]
        XCTAssertTrue(
            primaryButton.waitForExistence(timeout: 5),
            "씹기 감지 맞추기 화면이 열려야 한다"
        )
        primaryButton.tap()
        XCTAssertTrue(
            app.staticTexts["AirPods가 준비됐어요"].waitForExistence(timeout: 5),
            "준비음을 확인한 뒤 AirPods 준비 완료 상태가 보여야 한다"
        )
        XCTAssertTrue(primaryButton.isEnabled, "AirPods 준비 완료 후 다음 단계로 이동할 수 있어야 한다")
        primaryButton.tap()
        XCTAssertTrue(
            app.staticTexts["5초 동안 편하게\n멈춰 있어 주세요"].waitForExistence(timeout: 5),
            "AirPods 준비 후 정지 상태 측정 화면이 보여야 한다"
        )
        primaryButton.tap()
        XCTAssertTrue(
            app.staticTexts["평소처럼 자연스럽게\n10번 씹어보세요"].waitForExistence(timeout: 10),
            "정지 상태 측정 후 자연스러운 씹기 측정 화면이 보여야 한다"
        )
    }

    func testDeleteMyData_showsConfirmationDialog() {
        app.launch()
        openSettingsAndTapDelete()
    }

    func testDeleteMyData_cancelDoesNothing() {
        app.launch()
        openSettingsAndTapDelete()

        let cancelButton = app.buttons["취소"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), "계정 삭제 다이얼로그에 취소 버튼이 있어야 한다")
        cancelButton.tap()

        XCTAssertTrue(
            app.staticTexts["계정을 삭제할까요?"].waitForNonExistence(timeout: 3),
            "취소 후 계정 삭제 다이얼로그가 닫혀야 한다"
        )

        // 설정 화면이 여전히 열려 있어야 함
        XCTAssertTrue(
            app.staticTexts["설정"].waitForExistence(timeout: 3),
            "취소 후 SettingsView가 그대로 열려 있어야 한다"
        )
    }

    /// gear → SettingsView 정착 대기 → '계정 삭제' 탭 → 확인 다이얼로그 타이틀 등장까지.
    private func openSettingsAndTapDelete() {
        let gearButton = app.buttons["gearshape"]
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
