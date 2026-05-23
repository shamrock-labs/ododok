import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
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

    func testOnboardingShown_onFreshLaunch() {
        app.launchArguments = ["-resetState", "-useNoopRemote"]
        app.launch()
        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))
    }

    func testNameInput_dismissesSheet() {
        app.launchArguments = ["-resetState", "-useNoopRemote"]
        app.launch()

        // Wait for the onboarding sheet
        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))

        // Tap the name text field and type a name
        let nameField = app.textFields["OnboardingNameField"]
        XCTAssert(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("테스터")

        // Tap the "시작하기" submit button
        let submitButton = app.buttons["OnboardingSubmit"]
        XCTAssert(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()

        // Verify the onboarding sheet is dismissed
        let onboardingText = app.staticTexts["처음 오셨네요!"]
        let dismissed = onboardingText.waitForNonExistence(timeout: 10)
        XCTAssertTrue(dismissed, "Onboarding sheet should be dismissed after submitting name")
    }
}
