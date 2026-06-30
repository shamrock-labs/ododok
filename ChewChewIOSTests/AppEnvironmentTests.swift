import XCTest
@testable import ChewChewIOS

final class AppEnvironmentTests: XCTestCase {
    func testCurrentEnvironment_matchesBuildConfiguration() {
        #if DEBUG
        XCTAssertEqual(AppEnvironment.current, "dev")
        #else
        XCTAssertEqual(AppEnvironment.current, "prod")
        #endif
    }
}
