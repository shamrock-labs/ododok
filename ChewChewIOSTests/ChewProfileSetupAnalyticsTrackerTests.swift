import XCTest
@testable import ChewChewIOS

@MainActor
final class ChewProfileSetupAnalyticsTrackerTests: XCTestCase {
    func testStartAndStageTransitionsUseProductVocabulary() {
        let analytics = ChewProfileAnalyticsSpy()
        var now = Date(timeIntervalSince1970: 100)
        let tracker = ChewProfileSetupAnalyticsTracker(
            source: .onboarding,
            analytics: analytics,
            now: { now }
        )

        tracker.start()
        now.addTimeInterval(3)
        tracker.transition(from: .connection, to: .baseline, issue: nil)
        now.addTimeInterval(5)
        tracker.transition(from: .baseline, to: .calibration, issue: nil)
        now.addTimeInterval(12)
        tracker.transition(from: .calibration, to: .adjustment, issue: nil)
        now.addTimeInterval(8)
        tracker.transition(from: .adjustment, to: .ready, issue: nil)

        XCTAssertEqual(analytics.events.map(\.name), [
            "chew_profile_setup_started",
            "chew_profile_setup_step_completed",
            "chew_profile_setup_step_completed",
            "chew_profile_setup_step_completed",
            "chew_profile_setup_step_completed"
        ])
        XCTAssertEqual(analytics.events[1].properties["step"] as? String, "connection")
        XCTAssertEqual(analytics.events[2].properties["step"] as? String, "resting_signal")
        XCTAssertEqual(analytics.events[3].properties["step"] as? String, "chewing_signal")
        XCTAssertEqual(analytics.events[4].properties["step"] as? String, "verification")
    }

    func testFailureUsesStableReasonAndDoesNotIncludeSensorMessage() {
        let analytics = ChewProfileAnalyticsSpy()
        let tracker = ChewProfileSetupAnalyticsTracker(source: .settings, analytics: analytics)

        tracker.start()
        tracker.transition(
            from: .calibration,
            to: .signalIssue,
            issue: .sensor("raw device detail must not leave the app")
        )

        let event = analytics.events.last
        XCTAssertEqual(event?.name, "chew_profile_setup_failed")
        XCTAssertEqual(event?.properties["source"] as? String, "settings")
        XCTAssertEqual(event?.properties["step"] as? String, "chewing_signal")
        XCTAssertEqual(event?.properties["reason"] as? String, "sensor_error")
        XCTAssertFalse(String(describing: event?.properties).contains("raw device detail"))
    }

    func testRetryCountFlowsIntoCompletionAfterSave() {
        let analytics = ChewProfileAnalyticsSpy()
        var now = Date(timeIntervalSince1970: 200)
        let tracker = ChewProfileSetupAnalyticsTracker(
            source: .settings,
            analytics: analytics,
            now: { now }
        )

        tracker.start()
        tracker.transition(from: .adjustment, to: .signalIssue, issue: .adjustmentNeeded)
        tracker.transition(from: .signalIssue, to: .adjustment, issue: nil)
        now.addTimeInterval(42)
        tracker.complete()

        let event = analytics.events.last
        XCTAssertEqual(event?.name, "chew_profile_setup_completed")
        XCTAssertEqual(event?.properties["duration_sec"] as? Int, 42)
        XCTAssertEqual(event?.properties["retry_count"] as? Int, 1)
    }

    func testSaveFailureAndDismissalAreDistinct() {
        let failedAnalytics = ChewProfileAnalyticsSpy()
        let failedTracker = ChewProfileSetupAnalyticsTracker(source: .settings, analytics: failedAnalytics)
        failedTracker.start()
        failedTracker.failSave()

        XCTAssertEqual(failedAnalytics.events.last?.name, "chew_profile_setup_failed")
        XCTAssertEqual(failedAnalytics.events.last?.properties["reason"] as? String, "profile_save_failed")

        let dismissedAnalytics = ChewProfileAnalyticsSpy()
        let dismissedTracker = ChewProfileSetupAnalyticsTracker(source: .onboarding, analytics: dismissedAnalytics)
        dismissedTracker.start()
        dismissedTracker.dismiss(at: .baseline)

        XCTAssertEqual(dismissedAnalytics.events.last?.name, "chew_profile_setup_dismissed")
        XCTAssertEqual(dismissedAnalytics.events.last?.properties["step"] as? String, "resting_signal")
    }
}

private final class ChewProfileAnalyticsSpy: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}
