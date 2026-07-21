import Foundation

/// 제품·리텐션 분석 이벤트 정의.
///
/// `track(_:)` 한 번 호출이 등록된 모든 provider(Amplitude·후속 Firebase)로 동시에 나간다.
/// 이름·속성 스키마를 이 한 곳에서 관리해 provider 간 드리프트·오타를 막는다(타입 안전 팩토리).
struct AnalyticsEvent {
    let name: String
    let properties: [String: Any]

    init(_ name: String, _ properties: [String: Any] = [:]) {
        self.name = name
        self.properties = properties
    }
}

enum AppOpenLaunchType: String {
    case coldStart = "cold_start"
    case foreground
}

enum AnalyticsAuthenticationState: String {
    case loggedIn = "logged_in"
    case loggedOut = "logged_out"
}

enum ChewProfileSetupSource: String {
    case onboarding
    case settings
}

enum ChewProfileSetupStep: String {
    case intro
    case connection
    case restingSignal = "resting_signal"
    case chewingSignal = "chewing_signal"
    case verification
    case ready
}

enum ChewProfileSetupFailureReason: String {
    case motionUnavailable = "motion_unavailable"
    case insufficientChewingSignal = "insufficient_chewing_signal"
    case insufficientSignalSeparation = "insufficient_signal_separation"
    case verificationOutOfRange = "verification_out_of_range"
    case sensorError = "sensor_error"
    case profileSaveFailed = "profile_save_failed"
}

enum LoginFailureReason: String {
    case missingIdToken = "missing_id_token"
    case provider
    case offline
    case server
    case malformedResponse = "malformed_response"
    case unknown
}

enum OnboardingStepName: String {
    case name
    case airPods = "airpods"
    case measurement
    case rewards
    case streak
}

enum OnboardingNameMethod: String {
    case custom
    case generated
    case existing
}

enum OnboardingCompletionMethod: String {
    case finished
    case skipped
}

enum OnboardingFailureReason: String {
    case offline
    case server
    case authExpired = "auth_expired"
    case malformedResponse = "malformed_response"
    case unknown
}

enum MealStartSource: String {
    case home
    case notification
}

enum MealStartBlockReason: String {
    case airPodsDisconnected = "airpods_disconnected"
    case routePreparationFailed = "route_preparation_failed"
    case motionUnavailable = "motion_unavailable"
    case permissionDenied = "permission_denied"
    case permissionRestricted = "permission_restricted"
    case authorizationUnknown = "authorization_unknown"
}

enum MealStartCancellationStage: String {
    case connectionPrompt = "connection_prompt"
    case countdown
}

enum AnalyticsPermissionType: String {
    case motion
    case notification
}

enum AnalyticsPermissionStatus: String {
    case authorized
    case denied
    case restricted
    case unavailable
    case error
}

enum AnalyticsPermissionSource: String {
    case mealStart = "meal_start"
    case reminderSettings = "reminder_settings"
    case mealSession = "meal_session"
}

// MARK: - 표준 이벤트 팩토리 (v1 트래킹 플랜)

extension AnalyticsEvent {
    static func appOpened(
        launchType: AppOpenLaunchType,
        authenticationState: AnalyticsAuthenticationState,
        onboardingCompleted: Bool,
        chewProfileConfigured: Bool
    ) -> AnalyticsEvent {
        .init("app_opened", [
            "launch_type": launchType.rawValue,
            "authentication_state": authenticationState.rawValue,
            "onboarding_completed": onboardingCompleted,
            "chew_profile_configured": chewProfileConfigured
        ])
    }

    static func chewProfileSetupOffered(source: ChewProfileSetupSource) -> AnalyticsEvent {
        .init("chew_profile_setup_offered", ["source": source.rawValue])
    }

    static func chewProfileSetupStarted(source: ChewProfileSetupSource) -> AnalyticsEvent {
        .init("chew_profile_setup_started", ["source": source.rawValue])
    }

    static func chewProfileSetupStepCompleted(
        source: ChewProfileSetupSource,
        step: ChewProfileSetupStep,
        durationSec: Int
    ) -> AnalyticsEvent {
        .init("chew_profile_setup_step_completed", [
            "source": source.rawValue,
            "step": step.rawValue,
            "duration_sec": durationSec
        ])
    }

    static func chewProfileSetupCompleted(
        source: ChewProfileSetupSource,
        durationSec: Int,
        retryCount: Int
    ) -> AnalyticsEvent {
        .init("chew_profile_setup_completed", [
            "source": source.rawValue,
            "duration_sec": durationSec,
            "retry_count": retryCount
        ])
    }

    static func chewProfileSetupFailed(
        source: ChewProfileSetupSource,
        step: ChewProfileSetupStep,
        reason: ChewProfileSetupFailureReason,
        retryCount: Int
    ) -> AnalyticsEvent {
        .init("chew_profile_setup_failed", [
            "source": source.rawValue,
            "step": step.rawValue,
            "reason": reason.rawValue,
            "retry_count": retryCount
        ])
    }

    static func chewProfileSetupDismissed(
        source: ChewProfileSetupSource,
        step: ChewProfileSetupStep
    ) -> AnalyticsEvent {
        .init("chew_profile_setup_dismissed", [
            "source": source.rawValue,
            "step": step.rawValue
        ])
    }

    static func chewProfileReset(source: ChewProfileSetupSource) -> AnalyticsEvent {
        .init("chew_profile_reset", ["source": source.rawValue])
    }

    static func loginStarted(method: String) -> AnalyticsEvent {
        .init("login_started", ["method": method])
    }

    static func loginCancelled(method: String) -> AnalyticsEvent {
        .init("login_cancelled", ["method": method])
    }

    static func loginFailed(method: String, reason: LoginFailureReason) -> AnalyticsEvent {
        .init("login_failed", ["method": method, "reason": reason.rawValue])
    }

    static func onboardingStarted() -> AnalyticsEvent {
        .init("onboarding_started")
    }

    static func onboardingStepCompleted(
        step: OnboardingStepName,
        nameMethod: OnboardingNameMethod? = nil
    ) -> AnalyticsEvent {
        var properties: [String: Any] = ["step": step.rawValue]
        if let nameMethod { properties["name_method"] = nameMethod.rawValue }
        return .init("onboarding_step_completed", properties)
    }

    static func onboardingStepFailed(
        step: OnboardingStepName,
        reason: OnboardingFailureReason
    ) -> AnalyticsEvent {
        .init("onboarding_step_failed", [
            "step": step.rawValue,
            "reason": reason.rawValue
        ])
    }

    /// 온보딩(닉네임 입력 + 튜토리얼)을 완료하거나 건너뜀. 활성화 깔때기의 핵심 전환점.
    static func onboardingCompleted(
        completionMethod: OnboardingCompletionMethod,
        nameMethod: OnboardingNameMethod,
        lastStep: OnboardingStepName
    ) -> AnalyticsEvent {
        .init("onboarding_completed", [
            "completion_method": completionMethod.rawValue,
            "name_method": nameMethod.rawValue,
            "last_step": lastStep.rawValue
        ])
    }

    static func mealStartRequested(source: MealStartSource) -> AnalyticsEvent {
        .init("meal_start_requested", ["source": source.rawValue])
    }

    static func mealStartBlocked(
        source: MealStartSource,
        reason: MealStartBlockReason
    ) -> AnalyticsEvent {
        .init("meal_start_blocked", [
            "source": source.rawValue,
            "reason": reason.rawValue
        ])
    }

    static func mealStartCancelled(
        source: MealStartSource,
        stage: MealStartCancellationStage
    ) -> AnalyticsEvent {
        .init("meal_start_cancelled", [
            "source": source.rawValue,
            "stage": stage.rawValue
        ])
    }

    /// 식사 측정 세션 시작.
    static func mealSessionStarted(
        sessionId: UUID,
        source: MealStartSource = .home
    ) -> AnalyticsEvent {
        .init("meal_session_started", [
            "meal_session_id": sessionId.uuidString,
            "source": source.rawValue
        ])
    }

    /// 식사 측정 세션 종료 + 서버 저장 성공. 리텐션·참여도 분석의 주 이벤트.
    static func mealSessionCompleted(
        sessionId: UUID,
        durationSec: Int,
        sampleCount: Int,
        chewingFraction: Double?,
        estimatedTotalChews: Int?,
        reportable: Bool
    ) -> AnalyticsEvent {
        var p: [String: Any] = [
            "meal_session_id": sessionId.uuidString,
            "duration_sec": durationSec,
            "sample_count": sampleCount,
            "reportable": reportable
        ]
        if let chewingFraction { p["chewing_fraction"] = chewingFraction }
        if let estimatedTotalChews { p["estimated_total_chews"] = estimatedTotalChews }
        return .init("meal_session_completed", p)
    }

    /// 도토리(포인트) 적립. 세션 종료 적립·출석 보너스 등 실제 포인트가 지급된 경우만.
    static func rewardEarned(amount: Int, kind: String) -> AnalyticsEvent {
        .init("reward_earned", ["amount": amount, "kind": kind])
    }

    /// 스트릭 상태 이벤트(마일스톤·방어·리셋·첫날). 포인트 지급과 무관한 스트릭 변화 추적.
    static func streakEvent(type: String, amount: Int) -> AnalyticsEvent {
        .init("streak_event", ["type": type, "amount": amount])
    }

    /// 친구 초대 코드 수신(딥링크/공유). 로그인 여부로 즉시 수락 vs 보류를 구분.
    static func friendInviteReceived(loggedIn: Bool) -> AnalyticsEvent {
        .init("friend_invite_received", ["logged_in": loggedIn])
    }

    /// 소셜 로그인 성공. method(apple/google/kakao) 분포·전환을 본다.
    /// 서버에 신규가입 플래그가 없어 signup은 별도 계측하지 않는다 — 가입 전환은 onboarding_completed로.
    static func login(method: String, onboardingCompleted: Bool) -> AnalyticsEvent {
        .init("login", ["method": method, "onboarding_completed": onboardingCompleted])
    }

    /// 사용자가 명시적으로 로그아웃함. source: settings.
    static func logout(source: String) -> AnalyticsEvent {
        .init("logout", ["source": source])
    }

    /// 사용자가 명시적으로 계정 탈퇴/데이터 삭제를 요청함. source: settings.
    static func accountDeleted(source: String) -> AnalyticsEvent {
        .init("account_deleted", ["source": source])
    }

    /// 측정 세션이 서버 저장 없이 종료됨. reason: user_discard(사용자 그만두기) | no_samples(IMU 0개).
    /// 저장 성공한 세션은 meal_session_completed, 저장 실패는 meal_session_failed로 별도 구분.
    static func mealSessionAborted(sessionId: UUID, reason: String, durationSec: Int) -> AnalyticsEvent {
        .init("meal_session_aborted", [
            "meal_session_id": sessionId.uuidString,
            "reason": reason,
            "duration_sec": durationSec
        ])
    }

    /// 측정은 끝났으나 서버 저장 실패. reason은 오류 분류(offline/server/http/malformed/...).
    /// 저장 실패 세션이 통계에서 증발하지 않도록(생존편향 방지) 기록한다.
    static func mealSessionFailed(
        sessionId: UUID,
        reason: String,
        attemptNumber: Int = 1
    ) -> AnalyticsEvent {
        .init("meal_session_failed", [
            "meal_session_id": sessionId.uuidString,
            "reason": reason,
            "attempt_number": attemptNumber
        ])
    }

    static func mealSessionUploadRetryRequested(
        sessionId: UUID,
        nextAttemptNumber: Int
    ) -> AnalyticsEvent {
        .init("meal_session_upload_retry_requested", [
            "meal_session_id": sessionId.uuidString,
            "next_attempt_number": nextAttemptNumber
        ])
    }

    static func mealSessionUploadAbandoned(
        sessionId: UUID,
        failedAttemptCount: Int
    ) -> AnalyticsEvent {
        .init("meal_session_upload_abandoned", [
            "meal_session_id": sessionId.uuidString,
            "failed_attempt_count": failedAttemptCount
        ])
    }

    /// 권한 요청 결과. 권한 거부와 센서 미지원·시스템 오류를 status로 분리한다.
    static func permissionResult(
        type: AnalyticsPermissionType,
        status: AnalyticsPermissionStatus,
        source: AnalyticsPermissionSource
    ) -> AnalyticsEvent {
        .init("permission_result", [
            "type": type.rawValue,
            "status": status.rawValue,
            "granted": status == .authorized,
            "source": source.rawValue
        ])
    }

    /// 상점 꾸미기 아이템 구매(포인트 소비). 적립(reward_earned)과 짝을 이뤄 포인트 경제를 본다.
    static func shopItemPurchased(itemId: String, itemType: String, price: Int) -> AnalyticsEvent {
        .init("shop_item_purchased", ["item_id": itemId, "item_type": itemType, "price": price])
    }

    /// 기록/리포트 탭 진입. 리포트 허브 퍼널의 시작점.
    static func reportTabViewed(selectedDate: String, daysFromToday: Int, mealCount: Int) -> AnalyticsEvent {
        .init("report_tab_viewed", [
            "selected_date": selectedDate,
            "days_from_today": daysFromToday,
            "meal_count": mealCount
        ])
    }

    /// 리포트 탭에서 날짜를 선택함. source: date_ring | trend_chart | calendar.
    static func reportDateSelected(
        source: String,
        selectedDate: String,
        daysFromToday: Int,
        mealCount: Int
    ) -> AnalyticsEvent {
        .init("report_date_selected", [
            "source": source,
            "selected_date": selectedDate,
            "days_from_today": daysFromToday,
            "meal_count": mealCount
        ])
    }

    /// 날짜 선택 달력 sheet 열기.
    static func reportCalendarOpened(selectedDate: String, daysFromToday: Int, mealCount: Int) -> AnalyticsEvent {
        .init("report_calendar_opened", [
            "selected_date": selectedDate,
            "days_from_today": daysFromToday,
            "meal_count": mealCount
        ])
    }

    /// 하루 종합 리포트 열기.
    static func dailyReportOpened(
        selectedDate: String,
        daysFromToday: Int,
        mealCount: Int,
        sessionCount: Int,
        dayScore: Int?,
        grade: String?
    ) -> AnalyticsEvent {
        var properties: [String: Any] = [
            "selected_date": selectedDate,
            "days_from_today": daysFromToday,
            "meal_count": mealCount,
            "session_count": sessionCount
        ]
        if let dayScore { properties["day_score"] = dayScore }
        if let grade { properties["grade"] = grade }
        return .init("daily_report_opened", properties)
    }

    /// 단건 식사 리포트 열기. source: report_hub | daily_report.
    static func mealReportOpened(
        source: String,
        selectedDate: String,
        daysFromToday: Int,
        mealSlot: String,
        score: Int?,
        estimatedTotalChews: Int?,
        durationSec: Int
    ) -> AnalyticsEvent {
        var properties: [String: Any] = [
            "source": source,
            "selected_date": selectedDate,
            "days_from_today": daysFromToday,
            "meal_slot": mealSlot,
            "duration_sec": durationSec
        ]
        if let score { properties["score"] = score }
        if let estimatedTotalChews { properties["estimated_total_chews"] = estimatedTotalChews }
        return .init("meal_report_opened", properties)
    }
}
