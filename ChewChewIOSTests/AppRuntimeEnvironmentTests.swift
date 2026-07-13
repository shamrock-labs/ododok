import XCTest
@testable import ChewChewIOS

final class AppRuntimeEnvironmentTests: XCTestCase {
    func testResolve_acceptsConfiguredEnvironments() {
        XCTAssertEqual(AppRuntimeEnvironment.resolve("dev"), "dev")
        XCTAssertEqual(AppRuntimeEnvironment.resolve("prod"), "prod")
    }

    func testResolve_rejectsMissingOrUnexpandedValue() {
        XCTAssertNil(AppRuntimeEnvironment.resolve(nil))
        XCTAssertNil(AppRuntimeEnvironment.resolve(""))
        XCTAssertNil(AppRuntimeEnvironment.resolve("$(APP_RUNTIME_ENVIRONMENT)"))
        XCTAssertNil(AppRuntimeEnvironment.resolve("staging"))
    }
}
