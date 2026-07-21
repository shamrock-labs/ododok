import XCTest
@testable import ChewChewIOS

final class AppsFlyerServiceTests: XCTestCase {
    func testConfiguration_acceptsUsableValues() {
        let configuration = AppsFlyerConfiguration.resolve(
            infoDictionary: [
                "AppsFlyerDevKey": "dev-key",
                "AppsFlyerAppleAppID": "6784962920"
            ],
            isRunningTests: false
        )

        XCTAssertEqual(
            configuration,
            AppsFlyerConfiguration(devKey: "dev-key", appleAppID: "6784962920")
        )
    }

    func testConfiguration_rejectsMissingPlaceholderAndTestRuns() {
        XCTAssertNil(AppsFlyerConfiguration.resolve(
            infoDictionary: [:],
            isRunningTests: false
        ))
        XCTAssertNil(AppsFlyerConfiguration.resolve(
            infoDictionary: [
                "AppsFlyerDevKey": "REPLACE_WITH_APPSFLYER_DEV_KEY",
                "AppsFlyerAppleAppID": "$(APPSFLYER_APP_ID)"
            ],
            isRunningTests: false
        ))
        XCTAssertNil(AppsFlyerConfiguration.resolve(
            infoDictionary: [
                "AppsFlyerDevKey": "dev-key",
                "AppsFlyerAppleAppID": "6784962920"
            ],
            isRunningTests: true
        ))
    }

    func testConfiguration_rejectsMalformedAppleAppID() {
        XCTAssertNil(AppsFlyerConfiguration.resolve(
            infoDictionary: [
                "AppsFlyerDevKey": "dev-key",
                "AppsFlyerAppleAppID": "id6784962920"
            ],
            isRunningTests: false
        ))
    }

    func testDeepLinkDestination_acceptsOnlySupportedRoutes() {
        XCTAssertEqual(AppsFlyerDeepLinkDestination.resolve("home"), .home)
        XCTAssertEqual(AppsFlyerDeepLinkDestination.resolve("START"), .start)
        XCTAssertNil(AppsFlyerDeepLinkDestination.resolve("invite"))
        XCTAssertNil(AppsFlyerDeepLinkDestination.resolve(nil))
    }
}
