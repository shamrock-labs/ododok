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

    func testTutorialSkip_offersCalibrationOnHomeBeforeReward() {
        app.launchArguments = freshMemberLaunchArguments + ["-grantAttendanceReward"]
        app.launch()

        XCTAssert(app.staticTexts["처음 오셨네요!"].waitForExistence(timeout: 10))

        let nameField = app.textFields["OnboardingNameField"]
        XCTAssert(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("테스터")
        app.buttons["OnboardingSubmit"].tap()

        // Skip the tutorial → onboarding closes, then calibration is offered over Home.
        let skip = app.buttons["OnboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        XCTAssertTrue(skip.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["내 씹기 신호에 맞춰볼까요?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["설정 > 맞춤 감지 기준에서 언제든지 할 수 있어요."].exists)
        XCTAssertFalse(app.staticTexts["출석 보상"].exists, "캘리브레이션 선택 전에는 보상을 가려야 한다")
        app.buttons["다음에 할게요"].tap()

        XCTAssertTrue(
            app.staticTexts["내 씹기 신호에 맞춰볼까요?"].waitForNonExistence(timeout: 5),
            "다음에 하기를 선택하면 홈을 계속 사용할 수 있어야 한다"
        )
        XCTAssertTrue(
            app.staticTexts["출석 보상"].waitForExistence(timeout: 2),
            "캘리브레이션 선택이 끝난 뒤 대기 중인 보상을 보여줘야 한다"
        )
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
        XCTAssertTrue(skip.waitForNonExistence(timeout: 10))
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
