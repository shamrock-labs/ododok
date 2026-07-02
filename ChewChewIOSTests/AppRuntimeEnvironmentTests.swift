import XCTest
@testable import ChewChewIOS

final class AppRuntimeEnvironmentTests: XCTestCase {
    func testName_matchesBuildConfiguration() {
        #if DEBUG
        XCTAssertEqual(AppRuntimeEnvironment.name, "dev")
        #else
        XCTAssertEqual(AppRuntimeEnvironment.name, "prod")
        #endif
    }
}
