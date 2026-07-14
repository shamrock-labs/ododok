# ODO-146 iOS meal-score-v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decode, validate, and display server-stored `meal-score-v1` reports, including the 56–130 chews/min recommendation range, without adding local scoring.

**Architecture:** Extend the existing v1 DTO contract with optional legacy target and v1 min/max values. Validate generated reports according to `scorePolicyVersion`, then map the stored metrics and baseline into a range-aware display model. All server axis scores, total score, and grade remain opaque snapshots.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Tuist, Xcode iOS Simulator.

## Global Constraints

- Base branch is `feat/odo-145-server-meal-report`; review only `e257e3b..HEAD`.
- No `SessionScore`, Gaussian formula, weighted average, or grade calculation may be added.
- `legacy-ios-v1` continues to require `legacyMealRatePerMin` and `{target: 28}` semantics.
- `meal-score-v1` requires `chewingRatePerMin` and `{min: 56, max: 130}` semantics.
- Unknown generated policy versions are rejected as malformed server reports.
- Existing `UNREPORTABLE` reason-specific copy remains unchanged.
- Production code is written only after the corresponding test was observed failing.

---

### Task 1: policy-aware DTO decoding and validation

**Files:**
- Modify: `ChewChewIOS/Models/DTO/SessionDTO.swift`
- Modify: `ChewChewIOS/Models/MealSessionReportability.swift`
- Test: `ChewChewIOSTests/MealReportDTOTests.swift`
- Test: `ChewChewIOSTests/MealSessionUploadRepositoryTests.swift`

**Interfaces:**
- Consumes: server JSON with `scorePolicyVersion`, policy-specific metrics, and rate baseline.
- Produces: `MealReportRateBaselineDTO(target:min:max:)` and policy-aware `completeGeneratedReport`.

- [ ] **Step 1: Write failing v1 decode tests**

```swift
func testDecodeMealScoreV1RangeBaseline() throws {
    let report = try JSONDecoder().decode(MealReportDTO.self, from: Data(v1JSON.utf8))
    XCTAssertEqual(report.scorePolicyVersion, "meal-score-v1")
    XCTAssertEqual(report.metrics?.chewingRatePerMin, 100)
    XCTAssertNil(report.metrics?.legacyMealRatePerMin)
    XCTAssertNil(report.recommendedBaseline?.chewingRatePerMin.target)
    XCTAssertEqual(report.recommendedBaseline?.chewingRatePerMin.min, 56)
    XCTAssertEqual(report.recommendedBaseline?.chewingRatePerMin.max, 130)
}
```

Add upload contract cases that reject v1 with missing `chewingRatePerMin`, missing min/max, reversed range, or a legacy target; keep a valid v1 fixture accepted.

- [ ] **Step 2: Run RED**

Run:

```bash
xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOSTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ChewChewIOSTests/MealReportDTOTests \
  -only-testing:ChewChewIOSTests/MealSessionUploadRepositoryTests
```

Expected: compile/decode failure because legacy rate and target are non-optional and min/max do not exist.

- [ ] **Step 3: Extend DTOs without changing legacy JSON**

```swift
struct MealReportMetricsDTO: Codable, Equatable {
    var chewingRatePerMin: Double?
    var legacyMealRatePerMin: Double?
    var chewingTimeRatio: Double
    var totalChewCount: Int
    var mealDurationSec: Double
}

struct MealReportRateBaselineDTO: Codable, Equatable {
    var target: Double?
    var min: Double?
    var max: Double?
}

struct MealReportRecommendedBaselineDTO: Codable, Equatable {
    var chewingRatePerMin: MealReportRateBaselineDTO
    var chewingTimeRatio: Double
    var totalChewCount: Int
    var mealDurationSec: Double
}
```

- [ ] **Step 4: Add policy-specific completeness validation**

```swift
private static func policySpecificMetricsAreValid(
    policy: String?, metrics: MealReportMetricsDTO,
    baseline: MealReportRecommendedBaselineDTO
) -> Bool {
    switch policy {
    case "legacy-ios-v1":
        return finiteNonNegative(metrics.legacyMealRatePerMin)
            && metrics.chewingRatePerMin == nil
            && positive(baseline.chewingRatePerMin.target)
            && baseline.chewingRatePerMin.min == nil
            && baseline.chewingRatePerMin.max == nil
    case "meal-score-v1":
        return finiteNonNegative(metrics.chewingRatePerMin)
            && metrics.legacyMealRatePerMin == nil
            && baseline.chewingRatePerMin.target == nil
            && validRange(min: baseline.chewingRatePerMin.min, max: baseline.chewingRatePerMin.max)
    default:
        return false
    }
}
```

Keep axis, grade, ratio, count, and duration validation shared.

- [ ] **Step 5: Run GREEN**

Run the focused command from Step 2.

Expected: legacy and v1 decode/validation cases PASS.

- [ ] **Step 6: Commit**

```bash
git add ChewChewIOS/Models/DTO/SessionDTO.swift \
  ChewChewIOS/Models/MealSessionReportability.swift \
  ChewChewIOSTests/MealReportDTOTests.swift \
  ChewChewIOSTests/MealSessionUploadRepositoryTests.swift
git commit -m "feat(ODO-146): 신규 리포트 응답 계약 지원"
```

### Task 2: range-aware report card mapping

**Files:**
- Modify: `ChewChewIOS/Views/ReportCardView.swift`
- Test: `ChewChewIOSTests/ReportCardModelTests.swift`

**Interfaces:**
- Consumes: a complete legacy or v1 `MealReportDTO`.
- Produces: `ReportCardModel.RateRecommendation` whose delta is zero inside a recommended range and is measured from the nearest bound outside it.

- [ ] **Step 1: Write failing v1 mapping tests**

```swift
func testFromMealScoreV1_usesStoredRateAndRange() {
    let report = makeGeneratedReport(
        policy: "meal-score-v1",
        metrics: .init(chewingRatePerMin: 100, legacyMealRatePerMin: nil,
                       chewingTimeRatio: 0.6, totalChewCount: 300, mealDurationSec: 720),
        recommendedBaseline: .init(
            chewingRatePerMin: .init(target: nil, min: 56, max: 130),
            chewingTimeRatio: 0.6, totalChewCount: 300, mealDurationSec: 720)
    )
    let model = ReportCardModel.from(makeDTO(mealReport: report))
    XCTAssertEqual(model?.chewsPerMinute, 100)
    XCTAssertEqual(model?.rateRecommendation.displayText, "56~130")
    XCTAssertEqual(model?.rateRecommendation.delta(from: 100), 0)
}

func testRateRangeDelta_usesNearestBoundaryOutsideRange() {
    let range = ReportCardModel.RateRecommendation(min: 56, max: 130)
    XCTAssertEqual(range.delta(from: 40), -16)
    XCTAssertEqual(range.delta(from: 100), 0)
    XCTAssertEqual(range.delta(from: 150), 20)
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOSTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ChewChewIOSTests/ReportCardModelTests
```

Expected: compilation fails because `RateRecommendation` does not exist and mapping still requires legacy rate.

- [ ] **Step 3: Add the display-only recommendation model**

```swift
extension ReportCardModel {
    struct RateRecommendation: Equatable {
        let min: Double
        let max: Double

        init(target: Double) { self.min = target; self.max = target }
        init(min: Double, max: Double) { self.min = min; self.max = max }

        var displayText: String {
            min == max ? formatRecommendedChewsPerMinute(min) : "\(Int(min.rounded()))~\(Int(max.rounded()))"
        }

        func delta(from value: Double) -> Double {
            if value < min { return value - min }
            if value > max { return value - max }
            return 0
        }

        func normalizedDelta(from value: Double) -> Double {
            let boundary = value < min ? min : value > max ? max : max
            return delta(from: value) / max(boundary * 0.5, 1)
        }
    }
}
```

Replace scalar `recommendedChewsPerMinute` with `rateRecommendation`. The mapper switches only on the stored policy:

```swift
let rate: Double
let recommendation: RateRecommendation
switch report.scorePolicyVersion {
case "legacy-ios-v1":
    rate = metrics.legacyMealRatePerMin!
    recommendation = .init(target: baseline.chewingRatePerMin.target!)
case "meal-score-v1":
    rate = metrics.chewingRatePerMin!
    recommendation = .init(min: baseline.chewingRatePerMin.min!, max: baseline.chewingRatePerMin.max!)
default:
    return nil
}
```

- [ ] **Step 4: Update range-aware labels and comparisons**

Use `rateRecommendation.displayText` for “권장 …회/분”. Use `delta(from:)` for signed delta and summary classification, and `normalizedDelta(from:)` for the bar. Do not derive any score from these values.

- [ ] **Step 5: Run GREEN**

Run the focused command from Step 2.

Expected: legacy snapshot tests and new v1 range tests PASS.

- [ ] **Step 6: Commit**

```bash
git add ChewChewIOS/Views/ReportCardView.swift ChewChewIOSTests/ReportCardModelTests.swift
git commit -m "feat(ODO-146): 신규 저작 속도 권장 범위 표시"
```

### Task 3: daily, hub, and reason regression coverage

**Files:**
- Modify: `ChewChewIOSTests/DailyReportServerMealReportTests.swift`
- Modify: `ChewChewIOSTests/ReportHubServerMealReportTests.swift`
- Modify: `ChewChewIOSTests/DailyReportContractTests.swift`
- Verify: `ChewChewIOS/Views/SessionResultSheet.swift`
- Verify: `ChewChewIOS/Views/DailyReportView.swift`
- Verify: `ChewChewIOS/Views/ReportHubView.swift`

**Interfaces:**
- Consumes: mixed stored reports returned by ODO-145 daily/session APIs.
- Produces: proof that screens do not normalize or recalculate mixed policies.

- [ ] **Step 1: Add mixed-policy fixtures**

Create one legacy and one v1 generated report with deliberately different server scores. Assert daily/hub selection preserves each `scorePolicyVersion`, `totalScore`, and axis scores. Assert v1 remains reportable without a legacy rate.

- [ ] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOSTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ChewChewIOSTests/DailyReportServerMealReportTests \
  -only-testing:ChewChewIOSTests/ReportHubServerMealReportTests \
  -only-testing:ChewChewIOSTests/DailyReportContractTests
```

Expected: PASS after Tasks 1–2; if RED, correct only DTO fixture/mapping assumptions, never add local scoring.

- [ ] **Step 3: Lock existing reason-specific copy**

Assert `MealReportUnavailableContent.from` for all four known reasons, including `unsupportedModelVersion`, and the unknown fallback. No production copy change is expected.

- [ ] **Step 4: Run GREEN and commit tests**

Run the focused command from Step 2 plus `-only-testing:ChewChewIOSTests/MealReportDTOTests`.

```bash
git add ChewChewIOSTests/DailyReportServerMealReportTests.swift \
  ChewChewIOSTests/ReportHubServerMealReportTests.swift \
  ChewChewIOSTests/DailyReportContractTests.swift
git commit -m "test(ODO-146): 혼합 정책 화면 계약 고정"
```

### Task 4: iOS completion gate

**Files:**
- Verify all files changed after `e257e3b`.

**Interfaces:**
- Produces: review-ready stacked iOS branch.

- [ ] **Step 1: Regenerate project**

Run: `tuist generate --no-open`

Expected: success.

- [ ] **Step 2: Restart simulator test runner if needed**

Run:

```bash
xcrun simctl shutdown 'iPhone 17' || true
xcrun simctl boot 'iPhone 17'
xcrun simctl bootstatus 'iPhone 17' -b
```

Expected: simulator reports booted. This addresses the observed baseline worker-materialization stall; it does not hide a test failure.

- [ ] **Step 3: Run the full unit suite**

Run:

```bash
xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOSTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ChewChewIOSTests
```

Expected: all unit tests PASS with zero failures.

- [ ] **Step 4: Run unsigned simulator build**

Run:

```bash
xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run no-local-scoring search and diff checks**

Run:

```bash
! rg -n 'SessionScore|Math\.exp|exp\(|sqrt\(|totalScore\s*=' ChewChewIOS
git diff --check e257e3b...HEAD
git diff --stat e257e3b...HEAD
```

Expected: no local score formula, clean stacked diff.

