import XCTest

@MainActor
final class StreakDetailUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testDebugProfileLoginOpensPopulatedStreakHistoryWithoutOAuth() {
        app.launchArguments = ["-resetState", "-useNoopRemote", "-skipAttendanceDialog"]
        app.launch()

        let debugLogin = app.buttons["DebugProfileLoginButton"]
        XCTAssertTrue(debugLogin.waitForExistence(timeout: 10))
        debugLogin.tap()

        let streakButton = app.buttons["StreakDetailButton"]
        XCTAssertTrue(streakButton.waitForExistence(timeout: 5))
        tapWhenHittable(streakButton)

        XCTAssertTrue(app.buttons["StreakDetailCloseButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["18일째"].exists)
        XCTAssertTrue(app.staticTexts["6월 29일부터 이어가는 중"].exists)
        XCTAssertTrue(app.staticTexts["2026년 7월"].exists)
        XCTAssertTrue(app.otherElements["StreakSummaryCard"].exists)
        XCTAssertTrue(app.otherElements["StreakMonthGrid"].exists)
        XCTAssertTrue(app.otherElements["StreakDay-2026-07-03"].exists)
        XCTAssertTrue(app.otherElements["StreakDay-2026-07-16"].exists)

        let legend = app.otherElements["StreakLegend"]
        XCTAssertTrue(legend.exists)
        XCTAssertTrue(
            app.windows.firstMatch.frame.intersects(legend.frame),
            "기본 시트 높이에서 캘린더 범례까지 보여야 한다"
        )

        let guideButton = app.buttons["FreezeAwardGuideButton"]
        XCTAssertTrue(guideButton.exists)
        tapWhenHittable(guideButton)
        XCTAssertTrue(app.staticTexts["프리즈는 이렇게 받아요"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["스트릭 7일, 30일, 100일을 처음 달성할 때마다 프리즈 1개를 받아요."].exists)
        XCTAssertTrue(app.staticTexts["프리즈는 최대 3개까지 보유할 수 있어요."].exists)

        app.buttons["확인"].tap()
        XCTAssertTrue(app.staticTexts["프리즈는 이렇게 받아요"].waitForNonExistence(timeout: 3))
    }

    func testFreezeRecoveryAvailableRequiresExplicitUse() {
        launch(recoveryArgument: "-showFreezeRecoveryAvailable")

        assertAvailableDialog()
        app.buttons["프리즈 2개 사용하기"].tap()

        XCTAssertTrue(app.staticTexts["스트릭을 이어갈까요?"].waitForNonExistence(timeout: 3))
    }

    func testFreezeRecoveryAvailableIgnoresBackdropAndAllowsSkip() {
        launch(recoveryArgument: "-showFreezeRecoveryAvailable")

        assertAvailableDialog()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        XCTAssertTrue(app.staticTexts["스트릭을 이어갈까요?"].exists)

        app.buttons["사용하지 않기"].tap()
        XCTAssertTrue(app.staticTexts["스트릭을 이어갈까요?"].waitForNonExistence(timeout: 3))
    }

    func testInsufficientRecoveryHasOnlyExplicitConfirmation() {
        launch(recoveryArgument: "-showFreezeRecoveryInsufficient")

        XCTAssertTrue(app.staticTexts["스트릭이 새로 시작돼요"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["프리즈는 부분 사용하지 않아요"].exists)
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS '7월 14일' AND label CONTAINS '7월 15일'"))
                .firstMatch.exists
        )
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '필요 2개' AND label CONTAINS '보유 1개'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["사용하지 않기"].exists)
        XCTAssertFalse(app.buttons["프리즈 2개 사용하기"].exists)
        XCTAssertFalse(app.buttons["닫기"].exists)

        app.buttons["확인"].tap()
        XCTAssertTrue(app.staticTexts["스트릭이 새로 시작돼요"].waitForNonExistence(timeout: 3))
    }

    func testLongInsufficientRecoveryKeepsConfirmationPinnedAtAccessibilityTextSize() {
        launch(
            recoveryArgument: "-showFreezeRecoveryLongInsufficient",
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )

        XCTAssertTrue(app.staticTexts["스트릭이 새로 시작돼요"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '6월 1일' AND label CONTAINS '7월 15일'")).firstMatch.exists)
        XCTAssertTrue(
            app.scrollViews["FreezeRecoveryContentScroll"].exists,
            "긴 누락 목록은 고정 동작 위의 bounded scroll region에 있어야 한다"
        )

        let confirmButton = app.buttons["확인"]
        XCTAssertTrue(confirmButton.exists)
        XCTAssertTrue(
            confirmButton.isHittable,
            "긴 누락 목록과 접근성 글자 크기에서도 확인 동작은 화면에 고정되어야 한다"
        )
    }

    private func launch(recoveryArgument: String? = nil, additionalArguments: [String] = []) {
        app.launchArguments = [
            "-resetState", "-skipOnboarding", "-forceLogin", "-useNoopRemote",
        ] + (recoveryArgument.map { [$0] } ?? []) + additionalArguments
        app.launch()
    }

    private func assertAvailableDialog() {
        XCTAssertTrue(app.staticTexts["스트릭을 이어갈까요?"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS '7월 14일' AND label CONTAINS '7월 15일'"))
                .firstMatch.exists
        )
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '필요 2개' AND label CONTAINS '보유 2개'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["프리즈 2개 사용하기"].exists)
        XCTAssertTrue(app.buttons["사용하지 않기"].exists)
        XCTAssertFalse(app.buttons["닫기"].exists)
    }

    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
        element.tap()
    }

}
