import XCTest
@testable import ChewChewIOS

final class AppOpenAnalyticsTrackerTests: XCTestCase {
    func testFirstActiveEmitsColdStartOnlyOnce() {
        var tracker = AppOpenAnalyticsTracker()

        XCTAssertNil(tracker.transition(to: .inactive))
        XCTAssertEqual(tracker.transition(to: .active), .coldStart)
        XCTAssertNil(tracker.transition(to: .active))
    }

    func testBackgroundThenActiveEmitsForegroundOnlyOnce() {
        var tracker = AppOpenAnalyticsTracker()

        XCTAssertEqual(tracker.transition(to: .active), .coldStart)
        XCTAssertNil(tracker.transition(to: .background))
        XCTAssertEqual(tracker.transition(to: .active), .foreground)
        XCTAssertNil(tracker.transition(to: .active))
    }

    func testEventIncludesCurrentUserAndProfileState() {
        var tracker = AppOpenAnalyticsTracker()

        let event = tracker.event(
            for: .active,
            isLoggedIn: true,
            onboardingCompleted: true,
            chewProfileConfigured: false
        )

        XCTAssertEqual(event?.name, "app_opened")
        XCTAssertEqual(event?.properties["launch_type"] as? String, "cold_start")
        XCTAssertEqual(event?.properties["authentication_state"] as? String, "logged_in")
        XCTAssertEqual(event?.properties["onboarding_completed"] as? Bool, true)
        XCTAssertEqual(event?.properties["chew_profile_configured"] as? Bool, false)
    }
}
