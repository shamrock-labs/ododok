# ODO-163 Amplitude App and Chew Profile Funnels Implementation Plan

> **For agentic workers:** Execute inline in this session. The user explicitly requested no subagents. Follow TDD for every behavior change.

**Goal:** Add environment-filterable app-open and personal chew-profile setup analytics while keeping one Amplitude API key and the SDK lifecycle events.

**Architecture:** All new events remain typed `AnalyticsEvent` values and pass through `CompositeAnalytics`, which owns `environment=dev|prod`. A pure lifecycle state machine prevents duplicate cold-start and foreground events. A focused chew-profile analytics tracker translates internal calibration stages/issues into stable product-analysis vocabulary and is injected into the existing onboarding/settings flow.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, AmplitudeSwift, Tuist.

## Global Constraints

- Base implementation on `origin/main`.
- Keep one Amplitude API key, EU server zone, and automatic lifecycle tracking.
- Do not use `calibration` in public analytics event names or property values.
- Do not send raw sensor messages, thresholds, or amplitude arrays.
- All new events must receive `environment` only through `CompositeAnalytics`.
- Do not create Linear subissues or use subagents.

---

### Task 1: Typed analytics contracts and lifecycle state

**Files:**
- Create: `ChewChewIOS/Analytics/AppOpenAnalyticsTracker.swift`
- Modify: `ChewChewIOS/Analytics/AnalyticsEvent.swift`
- Modify: `ChewChewIOSTests/AnalyticsEventTests.swift`
- Create: `ChewChewIOSTests/AppOpenAnalyticsTrackerTests.swift`

**Interfaces:**
- Produces: `AnalyticsEvent.appOpened(launchType:authenticationState:onboardingCompleted:chewProfileConfigured:)`.
- Produces: `AppOpenAnalyticsTracker.transition(to:) -> AppOpenLaunchType?` for `.active`, `.inactive`, and `.background` inputs.
- Produces: typed chew-profile event factories using `ChewProfileSetupSource`, `ChewProfileSetupStep`, and `ChewProfileSetupFailureReason`.

- [ ] Write schema tests for `app_opened` and all `chew_profile_setup_*` events.
- [ ] Run focused tests and confirm failures because the factories do not exist.
- [ ] Implement the enums and minimal event factories with exact snake_case values from the Dodoc spec.
- [ ] Write lifecycle sequence tests: initial inactive→active emits cold start once; repeated active emits nothing; background→active emits foreground once.
- [ ] Run lifecycle tests and confirm the missing tracker failure.
- [ ] Implement the minimal pure lifecycle tracker.
- [ ] Run focused tests and confirm they pass.

### Task 2: Environment-filterable `app_opened`

**Files:**
- Modify: `ChewChewIOS/ChewChewIOSApp.swift`
- Modify: `ChewChewIOSTests/AppOpenAnalyticsTrackerTests.swift`

**Interfaces:**
- Consumes: `AppOpenAnalyticsTracker.transition(to:)` and `AnalyticsEvent.appOpened(...)`.
- Reads: `AppState.isLoggedIn`, `hasCompletedOnboarding`, and `chewProfileManager.currentSettings`.

- [ ] Add a failing integration-level tracker test proving the generated event contains current authentication/onboarding/profile flags.
- [ ] Run the focused test and verify the expected failure.
- [ ] Keep one analytics instance when constructing `AppState`, store lifecycle tracker state in `ChewChewIOSApp`, and track on `.active` transitions.
- [ ] Ensure the existing `sceneDidChange` behavior remains unchanged.
- [ ] Run focused lifecycle and analytics tests.

### Task 3: Personal chew-profile setup flow analytics

**Files:**
- Create: `ChewChewIOS/Features/MeasurementOnboarding/ChewProfileSetupAnalyticsTracker.swift`
- Modify: `ChewChewIOS/Features/MeasurementOnboarding/MeasurementPersonalizationFlow.swift`
- Modify: `ChewChewIOS/ContentView.swift`
- Modify: `ChewChewIOS/Views/Components/ChewDetectionPersonalizationSettingsControls.swift`
- Modify: `ChewChewIOS/Views/SettingsView.swift`
- Create: `ChewChewIOSTests/ChewProfileSetupAnalyticsTrackerTests.swift`

**Interfaces:**
- Produces: `ChewProfileSetupAnalyticsTracker` with `start()`, `transition(from:to:issue:)`, `complete()`, `failSave()`, and `dismiss()`.
- Consumes: source `.onboarding` or `.settings`, an `AnalyticsService`, and an injectable clock.
- Maps: baseline→resting_signal, calibration→chewing_signal, adjustment→verification; sensor text→sensor_error.

- [ ] Write failing tracker tests for start, stage completion, failure mapping, retry count, successful completion, save failure, and dismissal.
- [ ] Run focused tests and confirm failures because the tracker is missing.
- [ ] Implement the tracker with stable mappings and no raw sensor payloads.
- [ ] Inject source and analytics into `MeasurementPersonalizationFlow`; send completed only after `onSaved` succeeds.
- [ ] Track offer/dismiss in `ContentView`, use `.onboarding` there and `.settings` in settings controls.
- [ ] Track `chew_profile_reset` only after reset succeeds.
- [ ] Run tracker, measurement onboarding, and settings-related tests.

### Task 4: Documentation and verification

**Files:**
- Modify: `docs/amplitude-basic-user-flow.md`

**Interfaces:**
- Documents: `app_opened` as the environment-filterable funnel event and `chew_profile_setup_*` funnels with `environment=prod` default filters.

- [ ] Update the repository tracking reference to match the Dodoc event contract.
- [ ] Run `tuist generate --no-open`.
- [ ] Run all unit tests with `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOSUnitTests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`.
- [ ] Inspect the final diff for secrets, raw sensor values, naming drift, and unrelated changes.
- [ ] Report verification evidence in the final chat response; do not write to Linear.
