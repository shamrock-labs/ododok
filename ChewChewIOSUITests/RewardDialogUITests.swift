import XCTest

@MainActor
final class RewardDialogUITests: XCTestCase {
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

    func testAttendanceBonus_onFirstForeground() {
        // Fresh state + skip onboarding so the main screen loads immediately.
        // On first foreground with a displayName set, grantDailyAttendanceIfNeeded fires
        // and pendingRewardGrant is set → RewardDialogView appears showing "출석 보상!" and "+2".
        app.launchArguments = ["-resetState", "-skipOnboarding"]
        app.launch()

        // Look for either the reward dialog title or the "+2" acorn amount
        let rewardTitle = app.staticTexts["출석 보상!"]
        let acornAmount = app.staticTexts["+2"]

        let appeared = rewardTitle.waitForExistence(timeout: 5)
            || acornAmount.waitForExistence(timeout: 5)
        XCTAssertTrue(appeared,
            "Expected attendance reward dialog ('출석 보상!' or '+2') to appear on first foreground")
    }
}
