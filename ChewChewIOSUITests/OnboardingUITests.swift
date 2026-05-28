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

    func testNameInput_advancesToTutorial() {
        app.launchArguments = ["-resetState", "-useNoopRemote"]
        app.launch()

        // Wait for the onboarding sheet
        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))

        // Tap the name text field and type a name
        let nameField = app.textFields["OnboardingNameField"]
        XCTAssert(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("테스터")

        // Tap the "시작하기" submit button on the name step
        let submitButton = app.buttons["OnboardingSubmit"]
        XCTAssert(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()

        // After saving the name the sheet stays open and advances to the usage tutorial,
        // which exposes a "건너뛰기" button.
        let skip = app.buttons["OnboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "Name entry should advance to the tutorial step")
    }

    func testTutorialSkip_dismissesOnboarding() {
        app.launchArguments = ["-resetState", "-useNoopRemote"]
        app.launch()

        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))

        let nameField = app.textFields["OnboardingNameField"]
        XCTAssert(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("테스터")
        app.buttons["OnboardingSubmit"].tap()

        // Skip the tutorial → onboarding sheet should dismiss.
        let skip = app.buttons["OnboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        let dismissed = app.buttons["OnboardingSkip"].waitForNonExistence(timeout: 10)
        XCTAssertTrue(dismissed, "Onboarding should be dismissed after skipping the tutorial")
    }
}
