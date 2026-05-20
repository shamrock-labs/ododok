import XCTest

@MainActor
final class HomeMealToggleUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testStartEating_changesButtonLabel() {
        // -skipOnboarding sets displayName="테스터" so the onboarding sheet is bypassed
        app.launchArguments = ["-resetState", "-skipOnboarding"]
        app.launch()

        // Wait for the home screen meal toggle button
        let toggleButton = app.buttons["MealToggle"]
        XCTAssert(toggleButton.waitForExistence(timeout: 10))

        // Initially should show "식사 시작"
        XCTAssertTrue(toggleButton.label.contains("식사 시작"),
            "Button should initially show '식사 시작' but shows: \(toggleButton.label)")

        toggleButton.tap()

        // After tap, should show "식사 종료"
        let stoppedLabel = app.buttons["MealToggle"]
        let changed = stoppedLabel.waitForExistence(timeout: 5)
        XCTAssertTrue(changed)
        XCTAssertTrue(stoppedLabel.label.contains("식사 종료"),
            "Button should show '식사 종료' after tap but shows: \(stoppedLabel.label)")
    }

    func testStopEating_returnsToStart() {
        app.launchArguments = ["-resetState", "-skipOnboarding"]
        app.launch()

        let toggleButton = app.buttons["MealToggle"]
        XCTAssert(toggleButton.waitForExistence(timeout: 10))

        // Start eating
        toggleButton.tap()

        // Wait for "식사 종료" state
        let stoppedButton = app.buttons["MealToggle"]
        XCTAssert(stoppedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(stoppedButton.label.contains("식사 종료"),
            "Expected '식사 종료' but got: \(stoppedButton.label)")

        // Stop eating
        stoppedButton.tap()

        // Wait for "식사 시작" to return
        let startButton = app.buttons["MealToggle"]
        XCTAssert(startButton.waitForExistence(timeout: 10))
        XCTAssertTrue(startButton.label.contains("식사 시작"),
            "Button should return to '식사 시작' but shows: \(startButton.label)")
    }
}
