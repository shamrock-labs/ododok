import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    var app: XCUIApplication!

    private let freshMemberLaunchArguments = [
        "-resetState",
        "-forceLogin",
        "-useNoopRemote",
    ]

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
        app.launchArguments = freshMemberLaunchArguments
        app.launch()
        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))
    }

    func testNameInput_advancesToTutorial() {
        app.launchArguments = freshMemberLaunchArguments
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

    func testTutorialSkip_offersCalibrationBeforeDismissingOnboarding() {
        app.launchArguments = freshMemberLaunchArguments
        app.launch()

        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))

        let nameField = app.textFields["OnboardingNameField"]
        XCTAssert(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("테스터")
        app.buttons["OnboardingSubmit"].tap()

        // Skip the tutorial → calibration remains optional before onboarding closes.
        let skip = app.buttons["OnboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        XCTAssertTrue(app.staticTexts["내 씹기 신호에 맞춰볼까요?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["설정 > 맞춤 감지 기준에서 언제든지 할 수 있어요."].exists)
        app.buttons["다음에 할게요"].tap()

        let dismissed = app.buttons["OnboardingSkip"].waitForNonExistence(timeout: 10)
        XCTAssertTrue(dismissed, "Onboarding should be dismissed after skipping the tutorial")
    }

    func testCalibrationPrompt_startsExistingPersonalizationFlow() {
        app.launchArguments = freshMemberLaunchArguments
        app.launch()

        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))
        let nameField = app.textFields["OnboardingNameField"]
        XCTAssert(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("테스터")
        app.buttons["OnboardingSubmit"].tap()

        let skip = app.buttons["OnboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        app.buttons["지금 바로 하기"].tap()

        XCTAssertTrue(
            app.buttons["MeasurementOnboardingPrimary"].waitForExistence(timeout: 5),
            "지금 바로 하기는 기존 맞춤 측정 온보딩을 열어야 한다"
        )
    }

    func testMeasurementOnboardingPrimary_remainsReachableWithAccessibilityText() {
        app.launchArguments = [
            "-showMeasurementOnboarding",
            "-measurementOnboardingStage",
            "intro",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let primaryButton = app.buttons["MeasurementOnboardingPrimary"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 5))

        for _ in 0..<8 where !primaryButton.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(
            primaryButton.isHittable,
            "접근성 글자 크기에서도 내용을 읽은 뒤 주요 동작 버튼에 도달할 수 있어야 한다"
        )
    }
}
