import XCTest
@testable import ChewChewIOS

final class AnalyticsEventTests: XCTestCase {
    func testMealSessionEventsIncludeStableSessionId() {
        let sessionId = UUID()
        let events = [
            AnalyticsEvent.mealSessionStarted(sessionId: sessionId),
            AnalyticsEvent.mealSessionCompleted(
                sessionId: sessionId,
                durationSec: 180,
                sampleCount: 9_000,
                chewingFraction: 0.5,
                estimatedTotalChews: 180,
                reportable: true
            ),
            AnalyticsEvent.mealSessionAborted(
                sessionId: sessionId,
                reason: "user_discard",
                durationSec: 10
            ),
            AnalyticsEvent.mealSessionFailed(sessionId: sessionId, reason: "offline")
        ]

        XCTAssertEqual(
            events.compactMap { $0.properties["meal_session_id"] as? String },
            Array(repeating: sessionId.uuidString, count: events.count)
        )
    }

    func testAppOpenedEventSchema() {
        let event = AnalyticsEvent.appOpened(
            launchType: .coldStart,
            authenticationState: .loggedIn,
            onboardingCompleted: true,
            chewProfileConfigured: true
        )

        XCTAssertEqual(event.name, "app_opened")
        XCTAssertEqual(event.properties["launch_type"] as? String, "cold_start")
        XCTAssertEqual(event.properties["authentication_state"] as? String, "logged_in")
        XCTAssertEqual(event.properties["onboarding_completed"] as? Bool, true)
        XCTAssertEqual(event.properties["chew_profile_configured"] as? Bool, true)
    }

    func testChewProfileSetupEventSchemas() {
        let offered = AnalyticsEvent.chewProfileSetupOffered(source: .onboarding)
        let started = AnalyticsEvent.chewProfileSetupStarted(source: .settings)
        let step = AnalyticsEvent.chewProfileSetupStepCompleted(
            source: .settings,
            step: .chewingSignal,
            durationSec: 12
        )
        let completed = AnalyticsEvent.chewProfileSetupCompleted(
            source: .settings,
            durationSec: 40,
            retryCount: 2
        )
        let failed = AnalyticsEvent.chewProfileSetupFailed(
            source: .onboarding,
            step: .verification,
            reason: .verificationOutOfRange,
            retryCount: 1
        )
        let dismissed = AnalyticsEvent.chewProfileSetupDismissed(
            source: .onboarding,
            step: .restingSignal
        )
        let reset = AnalyticsEvent.chewProfileReset(source: .settings)

        XCTAssertEqual(offered.name, "chew_profile_setup_offered")
        XCTAssertEqual(offered.properties["source"] as? String, "onboarding")
        XCTAssertEqual(started.name, "chew_profile_setup_started")
        XCTAssertEqual(started.properties["source"] as? String, "settings")
        XCTAssertEqual(step.name, "chew_profile_setup_step_completed")
        XCTAssertEqual(step.properties["step"] as? String, "chewing_signal")
        XCTAssertEqual(step.properties["duration_sec"] as? Int, 12)
        XCTAssertEqual(completed.name, "chew_profile_setup_completed")
        XCTAssertEqual(completed.properties["retry_count"] as? Int, 2)
        XCTAssertEqual(failed.name, "chew_profile_setup_failed")
        XCTAssertEqual(failed.properties["reason"] as? String, "verification_out_of_range")
        XCTAssertEqual(dismissed.name, "chew_profile_setup_dismissed")
        XCTAssertEqual(dismissed.properties["step"] as? String, "resting_signal")
        XCTAssertEqual(reset.name, "chew_profile_reset")
    }

    func testAuthenticationOutcomeEventSchemas() {
        let started = AnalyticsEvent.loginStarted(method: "kakao")
        let cancelled = AnalyticsEvent.loginCancelled(method: "apple")
        let failed = AnalyticsEvent.loginFailed(method: "google", reason: .offline)

        XCTAssertEqual(started.name, "login_started")
        XCTAssertEqual(started.properties["method"] as? String, "kakao")
        XCTAssertEqual(cancelled.name, "login_cancelled")
        XCTAssertEqual(cancelled.properties["method"] as? String, "apple")
        XCTAssertEqual(failed.name, "login_failed")
        XCTAssertEqual(failed.properties["reason"] as? String, "offline")
    }

    func testOnboardingEventSchemasDistinguishSkipAndNameMethod() {
        let nameStep = AnalyticsEvent.onboardingStepCompleted(
            step: .name,
            nameMethod: .generated
        )
        let completed = AnalyticsEvent.onboardingCompleted(
            completionMethod: .skipped,
            nameMethod: .generated,
            lastStep: .measurement
        )

        XCTAssertEqual(nameStep.name, "onboarding_step_completed")
        XCTAssertEqual(nameStep.properties["name_method"] as? String, "generated")
        XCTAssertEqual(completed.name, "onboarding_completed")
        XCTAssertEqual(completed.properties["completion_method"] as? String, "skipped")
        XCTAssertEqual(completed.properties["last_step"] as? String, "measurement")
    }

    func testMealStartAndPermissionEventSchemas() {
        let requested = AnalyticsEvent.mealStartRequested(source: .notification)
        let blocked = AnalyticsEvent.mealStartBlocked(
            source: .notification,
            reason: .airPodsDisconnected
        )
        let permission = AnalyticsEvent.permissionResult(
            type: .motion,
            status: .unavailable,
            source: .mealStart
        )

        XCTAssertEqual(requested.name, "meal_start_requested")
        XCTAssertEqual(requested.properties["source"] as? String, "notification")
        XCTAssertEqual(blocked.name, "meal_start_blocked")
        XCTAssertEqual(blocked.properties["reason"] as? String, "airpods_disconnected")
        XCTAssertEqual(permission.name, "permission_result")
        XCTAssertEqual(permission.properties["status"] as? String, "unavailable")
        XCTAssertEqual(permission.properties["granted"] as? Bool, false)
    }

    func testUploadRecoveryEventSchemas() {
        let sessionId = UUID()
        let failed = AnalyticsEvent.mealSessionFailed(
            sessionId: sessionId,
            reason: "offline",
            attemptNumber: 2
        )
        let retry = AnalyticsEvent.mealSessionUploadRetryRequested(
            sessionId: sessionId,
            nextAttemptNumber: 3
        )
        let abandoned = AnalyticsEvent.mealSessionUploadAbandoned(
            sessionId: sessionId,
            failedAttemptCount: 2
        )

        XCTAssertEqual(failed.properties["attempt_number"] as? Int, 2)
        XCTAssertEqual(retry.properties["next_attempt_number"] as? Int, 3)
        XCTAssertEqual(abandoned.properties["failed_attempt_count"] as? Int, 2)
        XCTAssertEqual(retry.properties["meal_session_id"] as? String, sessionId.uuidString)
    }

    func testCompositeAnalyticsAddsEnvironmentToNewFunnelEvents() {
        let provider = EnvironmentAnalyticsSpy()
        let analytics = CompositeAnalytics([provider], baseProperties: ["environment": "prod"])

        analytics.track(.appOpened(
            launchType: .coldStart,
            authenticationState: .loggedOut,
            onboardingCompleted: false,
            chewProfileConfigured: false
        ))
        analytics.track(.chewProfileSetupStarted(source: .onboarding))

        XCTAssertEqual(provider.events.count, 2)
        XCTAssertEqual(provider.events[0].properties["environment"] as? String, "prod")
        XCTAssertEqual(provider.events[1].properties["environment"] as? String, "prod")
    }

    func testReportDateSelectedEventSchema() {
        let event = AnalyticsEvent.reportDateSelected(
            source: "calendar",
            selectedDate: "2026-06-30",
            daysFromToday: 0,
            mealCount: 2
        )

        XCTAssertEqual(event.name, "report_date_selected")
        XCTAssertEqual(event.properties["source"] as? String, "calendar")
        XCTAssertEqual(event.properties["selected_date"] as? String, "2026-06-30")
        XCTAssertEqual(event.properties["days_from_today"] as? Int, 0)
        XCTAssertEqual(event.properties["meal_count"] as? Int, 2)
    }

    func testDailyReportOpenedOmitsMissingScoreFields() {
        let event = AnalyticsEvent.dailyReportOpened(
            selectedDate: "2026-06-30",
            daysFromToday: 0,
            mealCount: 0,
            sessionCount: 0,
            dayScore: nil,
            grade: nil
        )

        XCTAssertEqual(event.name, "daily_report_opened")
        XCTAssertNil(event.properties["day_score"])
        XCTAssertNil(event.properties["grade"])
        XCTAssertEqual(event.properties["session_count"] as? Int, 0)
    }

    func testMealReportOpenedIncludesOptionalAnalysisFieldsWhenPresent() {
        let event = AnalyticsEvent.mealReportOpened(
            source: "report_hub",
            selectedDate: "2026-06-30",
            daysFromToday: 0,
            mealSlot: "lunch",
            score: 84,
            estimatedTotalChews: 432,
            durationSec: 720
        )

        XCTAssertEqual(event.name, "meal_report_opened")
        XCTAssertEqual(event.properties["source"] as? String, "report_hub")
        XCTAssertEqual(event.properties["meal_slot"] as? String, "lunch")
        XCTAssertEqual(event.properties["score"] as? Int, 84)
        XCTAssertEqual(event.properties["estimated_total_chews"] as? Int, 432)
        XCTAssertEqual(event.properties["duration_sec"] as? Int, 720)
    }

    func testLogoutEventSchema() {
        let event = AnalyticsEvent.logout(source: "settings")

        XCTAssertEqual(event.name, "logout")
        XCTAssertEqual(event.properties["source"] as? String, "settings")
    }

    func testAccountDeletedEventSchema() {
        let event = AnalyticsEvent.accountDeleted(source: "settings")

        XCTAssertEqual(event.name, "account_deleted")
        XCTAssertEqual(event.properties["source"] as? String, "settings")
    }
}

private final class EnvironmentAnalyticsSpy: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func setUserId(_ userId: String?) {}
    func setUserProperty(_ key: String, _ value: Any) {}
}
