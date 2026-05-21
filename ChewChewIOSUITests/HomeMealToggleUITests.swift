import XCTest

/// HomeView 식사 시작/종료 토글 e2e. 시뮬레이터에선 AirPods 가드 skip 분기를 타고
/// 데모 흐름이 동작하므로 button tap 만으로 isEating 전이가 일어난다.
///
/// 검증 전략은 accessibility identifier가 아니라 **button label 기반 query**다.
/// MealToggle은 토글 state에 따라 label이 "식사 시작" / "식사 종료"로 바뀌고,
/// SwiftUI re-render 직후엔 같은 accessibility identifier로 묶인 두 element가
/// staleness window 동안 공존할 수 있어 identifier 단독 query는 race가 잡힌다.
@MainActor
final class HomeMealToggleUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding"]
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testStartEating_changesButtonLabel() {
        app.launch()
        dismissAttendanceDialogIfPresent()

        let startButton = app.buttons["식사 시작"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "초기 '식사 시작' 버튼이 나타나야 한다")
        tapMealToggle(startButton)

        let stopButton = app.buttons["식사 종료"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "tap 후 '식사 종료' 라벨로 전환되어야 한다")
    }

    func testStopEating_returnsToStart() {
        app.launch()
        dismissAttendanceDialogIfPresent()

        let startButton = app.buttons["식사 시작"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        tapMealToggle(startButton)

        let stopButton = app.buttons["식사 종료"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        tapMealToggle(stopButton)

        let backToStart = app.buttons["식사 시작"]
        XCTAssertTrue(backToStart.waitForExistence(timeout: 10), "두 번째 tap 후 '식사 시작'으로 되돌아와야 한다")
    }

    /// ScrollView 안에 묻혀 hit testing이 잘 안 잡히는 케이스 회피용 — element의
    /// frame 중앙 좌표로 직접 tap. `XCUIElement.tap()`이 frame을 못 잡으면 noop가
    /// 되는데 좌표 tap은 항상 hit 보장.
    private func tapMealToggle(_ button: XCUIElement) {
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// foreground 첫 진입 시 자동 표시되는 RewardDialogView가 MealToggle 위에 깔려
    /// hit testing을 가린다. 빠른 dismiss 위해 dialog 텍스트가 보이면 tap. 안 보여도
    /// 2.5s 자동 dismiss 되니까 무한 대기는 안 함.
    private func dismissAttendanceDialogIfPresent() {
        let attendance = app.staticTexts["출석 보상!"]
        if attendance.waitForExistence(timeout: 2) {
            attendance.tap()
            _ = attendance.waitForNonExistence(timeout: 3)
        }
    }
}
