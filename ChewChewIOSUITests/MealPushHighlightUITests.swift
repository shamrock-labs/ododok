import XCTest

/// REQ-13: 알림 딥링크 수신 후 시작 버튼 강조 상태 UI 검증.
/// `-highlightStart` launch arg를 주입해 앱이 startButtonHighlighted=true로 시작하도록 한다.
@MainActor
final class MealPushHighlightUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-resetState",
            "-skipOnboarding",
            "-forceLogin",
            "-skipAttendanceDialog",
            "-useNoopRemote",
            "-highlightStart",
        ]
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    /// 강조 상태에서 MealToggle 버튼이 존재하는지 확인.
    func testStartButtonExists_whenHighlighted() {
        app.launch()

        // MealToggle은 "식사 시작" label 또는 accessibilityIdentifier "MealToggle"로 쿼리.
        let startButton = app.buttons["식사 시작"]
        XCTAssertTrue(
            startButton.waitForExistence(timeout: 10),
            "강조 상태에서도 '식사 시작' 버튼이 존재해야 한다"
        )
    }

    /// 강조 상태에서 MealToggle에 accessibilityIdentifier가 설정돼 있는지 확인.
    func testMealToggleIdentifier_whenHighlighted() {
        app.launch()

        let toggle = app.buttons["MealToggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "강조 상태에서 MealToggle identifier가 쿼리돼야 한다"
        )
        XCTAssertEqual(toggle.value as? String, "강조됨", "푸시 진입 시 식사 시작 버튼이 실제 강조 상태여야 한다")
    }
}
