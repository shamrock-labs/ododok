import XCTest

@MainActor
final class HomeHeaderUITests: XCTestCase {
    func testEightCharacterKoreanName_isVisibleInHomeHeader() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-resetState",
            "-skipOnboarding",
            "-displayNameFixture",
            "가나다라마바사아",
            "-skipAttendanceDialog",
            "-useNoopRemote",
            "-forceLogin",
        ]

        app.launch()

        XCTAssertTrue(
            app.staticTexts["가나다라마바사아님"].waitForExistence(timeout: 10),
            "한국어 이름 8자와 '님'이 홈 헤더에 표시되어야 한다"
        )
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '오늘 ·'")).firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "QA-02-iPhone-17-Korean-8-characters"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
