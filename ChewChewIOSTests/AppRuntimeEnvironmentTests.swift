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

    func testBuildChannelResolveAcceptsConfiguredChannels() {
        XCTAssertEqual(AppBuildChannel.resolve("debug"), "debug")
        XCTAssertEqual(AppBuildChannel.resolve("testflight"), "testflight")
        XCTAssertEqual(AppBuildChannel.resolve("app_store"), "app_store")
    }

    func testBuildChannelResolveRejectsMissingOrUnknownValue() {
        XCTAssertNil(AppBuildChannel.resolve(nil))
        XCTAssertNil(AppBuildChannel.resolve(""))
        XCTAssertNil(AppBuildChannel.resolve("$(APP_BUILD_CHANNEL)"))
        XCTAssertNil(AppBuildChannel.resolve("release"))
    }
}
