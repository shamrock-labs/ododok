# AirPods 자동 시작 플로우 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Task는 반드시 순서대로(1→6) 진행한다 — Task 3은 Task 2가 만든 프로퍼티를, Task 4는 Task 2·3이 만든 메서드를 그대로 소비한다.

**Goal:** 식사 시작 시 AirPods가 미연결이면 시스템 alert 대신 커스텀 팝업(도토리 팝업 톤)을 띄우고, 팝업이 떠 있는 동안 연결이 감지되면 팝업을 닫고 3-2-1 카운트다운 후 자동으로 측정을 시작한다.

**Architecture:** `AppState`에 라우트 감지용 순수 함수 + 카운트다운 상태 전이용 순수 함수 + 타이머 제어 메서드 + `NotificationCenter` 구독 기반 실시간 관찰 메서드를 추가한다. `HomeView.handleMealToggle()`은 판정 로직만 유지하고 팝업 트리거만 남긴다. `ContentView`는 기존 `.appDialog` 오버레이를 새 커스텀 팝업 뷰 + 카운트다운 오버레이 뷰로 교체한다. 화면(View)은 상태를 관찰만 하고, 라우트 구독/타이머는 `AppState` 안에서 관리한다(README "AppState 경계 규칙" 준수 — View에 외부 효과를 넣지 않는다).

**Tech Stack:** SwiftUI, `@Observable` AppState, AVFoundation(`AVAudioSession`), CoreMotion(`CMHeadphoneMotionManager`), XCTest.

## Global Constraints

- 빌드 전 항상 `tuist generate --no-open` 먼저 실행 (`Project.swift` → `ChewChewIOS.xcworkspace`).
- 시뮬레이터 무서명 빌드: `xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
- 테스트: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16'`.
- 새 코드는 `#if !targetEnvironment(simulator)` 가드가 걸린 실기기 전용 경로에 들어간다(시뮬레이터는 데모 흐름 유지, 이 플로우 자체를 타지 않음) — 기존 `HomeView.handleMealToggle()` 패턴 유지.
- 디자인 토큰만 사용한다: 색은 `Colors.swift`, 폰트는 `Font.appFont(.role)`(`DesignSystem/AppFont.swift`), 간격은 `AppSpacing`, radius는 `AppRadius`, 크기는 `AppSize`, 애니메이션 duration은 `AppMotion`(전부 `DesignSystem/Tokens.swift`). 매직넘버 금지.
- 카드 컨테이너 중첩 금지, 드롭섀도우 대신 `appElevation(.flat)`/`.floating)` 사용, 색은 상태(valence)에만 사용 — `ododok/CLAUDE.md` 디자인 규칙.
- 커밋 메시지: `type(ODO-NN): 요약` 형식. 이번 작업엔 Linear 이슈 키가 없으므로 `feat: 요약` 형식으로 커밋한다(사용자가 이슈 키를 알려주면 그걸로 대체).
- 커밋만 하고 push/PR은 하지 않는다(사용자가 명시적으로 요청할 때만).

---

## File Structure

- **Modify:** `ChewChewIOS/Models/AppState.swift` — 라우트 판정 순수 함수, 카운트다운 상태(순수 함수 + 프로퍼티 + 타이머 제어), 라우트 실시간 구독 시작/중단.
- **Modify:** `ChewChewIOS/Views/HomeView.swift` — `hasHeadphoneAudioRoute`를 `AppState`의 순수 함수 호출로 교체, 시작 가드 로직에서 팝업 트리거 + 구독 시작만 남김.
- **Create:** `ChewChewIOS/Views/AirPodsPromptDialogView.swift` — `RewardDialogView` 톤 팝업 + 우상단 "다음에 할게요" 버튼.
- **Create:** `ChewChewIOS/Views/StartCountdownView.swift` — 3-2-1 카운트다운 오버레이.
- **Modify:** `ChewChewIOS/ContentView.swift` — 기존 `airPodsPromptBinding` + `.appDialog(...)`를 새 팝업/카운트다운 오버레이로 교체.
- **Create:** `ChewChewIOSTests/AirPodsRouteDetectionTests.swift` — 라우트 판정 순수 함수 테스트.
- **Create:** `ChewChewIOSTests/StartCountdownStateTests.swift` — 카운트다운 상태 전이 순수 함수 테스트.

---

### Task 1: AirPods 라우트 판정을 AppState의 순수 함수로 추출

**Files:**
- Modify: `ChewChewIOS/Models/AppState.swift`
- Modify: `ChewChewIOS/Views/HomeView.swift:106-119` (`hasHeadphoneAudioRoute` 제거, 호출부 교체)
- Test: `ChewChewIOSTests/AirPodsRouteDetectionTests.swift`

**Interfaces:**
- Consumes: 없음 (신규 순수 함수)
- Produces: `AppState.hasHeadphoneAudioRoute(outputs: [AVAudioSessionPortDescription]) -> Bool` — Task 3이 사용

현재 `HomeView.swift:109-119`의 `hasHeadphoneAudioRoute`는 `AVAudioSession.sharedInstance().currentRoute.outputs`를 직접 읽는 인스턴스 프로퍼티라 단위 테스트가 불가능하다. 판정 로직만 순수 함수로 뽑아 `AppState`에 static 함수로 옮긴다(`AppState.shouldStartImmediately`와 동일 패턴).

- [ ] **Step 1: 실패하는 테스트 작성**

`ChewChewIOSTests/AirPodsRouteDetectionTests.swift` 새로 생성:

```swift
import XCTest
import AVFoundation
@testable import ChewChewIOS

/// AirPods/블루투스/유선 헤드폰 라우트 판정 순수 함수 테스트.
/// `AVAudioSessionPortDescription`은 직접 생성할 수 없으므로, portType만 비교하는
/// `AppState.isHeadphoneRoute(_:)` 최소 단위로 쪼개 테스트한다.
final class AirPodsRouteDetectionTests: XCTestCase {

    func testBluetoothA2DP_isHeadphoneRoute() {
        XCTAssertTrue(AppState.isHeadphoneRoute(.bluetoothA2DP))
    }

    func testBluetoothLE_isHeadphoneRoute() {
        XCTAssertTrue(AppState.isHeadphoneRoute(.bluetoothLE))
    }

    func testBluetoothHFP_isHeadphoneRoute() {
        XCTAssertTrue(AppState.isHeadphoneRoute(.bluetoothHFP))
    }

    func testHeadphones_isHeadphoneRoute() {
        XCTAssertTrue(AppState.isHeadphoneRoute(.headphones))
    }

    func testHeadsetMic_isHeadphoneRoute() {
        XCTAssertTrue(AppState.isHeadphoneRoute(.headsetMic))
    }

    func testBuiltInSpeaker_isNotHeadphoneRoute() {
        XCTAssertFalse(AppState.isHeadphoneRoute(.builtInSpeaker))
    }

    func testBuiltInReceiver_isNotHeadphoneRoute() {
        XCTAssertFalse(AppState.isHeadphoneRoute(.builtInReceiver))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ChewChewIOSTests/AirPodsRouteDetectionTests`
Expected: FAIL — `AppState`에 `isHeadphoneRoute`가 없어 컴파일 에러.

- [ ] **Step 3: 최소 구현 작성**

`ChewChewIOS/Models/AppState.swift`에서 `static func shouldStartImmediately(...)` 바로 아래(989번째 줄, `private func startHeadphoneMotionLoop()` 위)에 추가:

```swift
    /// 오디오 출력 포트가 AirPods/블루투스/유선 헤드폰류인지 판정하는 순수 함수.
    /// `CMHeadphoneMotionManager.isDeviceMotionAvailable`이 미연결 상태에서도 true를
    /// 반환하는 케이스를 라우트 체크로 보완하는 데 쓴다.
    static func isHeadphoneRoute(_ portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones, .headsetMic:
            return true
        default:
            return false
        }
    }

    /// 현재 오디오 출력 라우트에 AirPods/헤드폰류가 하나라도 포함되어 있는지.
    static func hasHeadphoneAudioRoute(outputs: [AVAudioSessionPortDescription]) -> Bool {
        outputs.contains { isHeadphoneRoute($0.portType) }
    }
```

`AppState.swift` 최상단 import에 `AVFoundation`이 없으면 추가한다 (현재 import 목록: `Foundation`, `Observation`, `CoreMotion`, `UserNotifications`, `UIKit` — `AVFoundation` 추가 필요).

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ChewChewIOSTests/AirPodsRouteDetectionTests`
Expected: PASS (7 tests)

- [ ] **Step 5: HomeView의 기존 호출부를 새 함수로 교체**

`ChewChewIOS/Views/HomeView.swift:106-119`의 기존 코드:

```swift
    private var hasHeadphoneAudioRoute: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones, .headsetMic:
                return true
            default:
                return false
            }
        }
    }
```

를 다음으로 교체:

```swift
    private var hasHeadphoneAudioRoute: Bool {
        AppState.hasHeadphoneAudioRoute(outputs: AVAudioSession.sharedInstance().currentRoute.outputs)
    }
```

- [ ] **Step 6: 시뮬레이터 빌드로 회귀 확인**

Run: `tuist generate --no-open && xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: 커밋**

```bash
git add ChewChewIOS/Models/AppState.swift ChewChewIOS/Views/HomeView.swift ChewChewIOSTests/AirPodsRouteDetectionTests.swift
git commit -m "feat: AirPods 라우트 판정을 AppState 순수 함수로 추출"
```

---

### Task 2: 카운트다운 상태 전이 순수 함수 + AppState 프로퍼티

**Files:**
- Modify: `ChewChewIOS/Models/AppState.swift`
- Test: `ChewChewIOSTests/StartCountdownStateTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `AppState.nextCountdownValue(from: Int) -> Int?` (순수 함수), `AppState.startCountdownValue: Int?` (프로퍼티, nil = 카운트다운 중이 아님), `AppState.beginStartCountdown(onFinished: @escaping () -> Void)`, `AppState.cancelStartCountdown()` — Task 3, Task 4, Task 6이 사용

카운트다운은 3 → 2 → 1 → nil(완료) 순서로 진행한다. 전이 자체는 순수 함수로 테스트하고, 타이머 구동은 `AppState`가 담당한다. 이 Task는 라우트 구독(Task 3)과 독립적으로 완결된 기능이다 — `beginStartCountdown`은 완료 시 자기 자신의 타이머만 정리하고, 구독 해제는 Task 3에서 이 메서드를 감싸는 형태로 처리한다(아래 Task 3 참고).

- [ ] **Step 1: 실패하는 테스트 작성**

`ChewChewIOSTests/StartCountdownStateTests.swift` 새로 생성:

```swift
import XCTest
@testable import ChewChewIOS

/// 3-2-1 카운트다운 상태 전이 순수 함수 테스트.
final class StartCountdownStateTests: XCTestCase {

    func testFromThree_returnsTwo() {
        XCTAssertEqual(AppState.nextCountdownValue(from: 3), 2)
    }

    func testFromTwo_returnsOne() {
        XCTAssertEqual(AppState.nextCountdownValue(from: 2), 1)
    }

    func testFromOne_returnsNil_meaningFinished() {
        XCTAssertNil(AppState.nextCountdownValue(from: 1))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ChewChewIOSTests/StartCountdownStateTests`
Expected: FAIL — `nextCountdownValue`가 없어 컴파일 에러.

- [ ] **Step 3: 최소 구현 작성**

`ChewChewIOS/Models/AppState.swift`에서 Task 1이 추가한 `hasHeadphoneAudioRoute(outputs:)` 아래에 순수 함수 추가:

```swift
    /// 카운트다운 다음 값. 1 다음은 nil(=측정 시작 트리거).
    static func nextCountdownValue(from value: Int) -> Int? {
        value > 1 ? value - 1 : nil
    }
```

`showAirPodsConnectionPrompt` 프로퍼티(322번째 줄) 근처에 프로퍼티 추가:

```swift
    /// 3-2-1 자동 시작 카운트다운 현재 값. nil이면 카운트다운 중이 아님.
    /// AirPods 연결이 감지되면 3에서 시작해 1초 간격으로 감소, nil이 되는 순간 측정을 시작한다.
    var startCountdownValue: Int?

    private var startCountdownTimer: Timer?
```

같은 파일에 제어 메서드 추가(`isHeadphoneRoute`/`hasHeadphoneAudioRoute` 아래, `startHeadphoneMotionLoop` 위):

```swift
    /// 카운트다운 시작. 이미 진행 중이면 무시. 1초 간격으로 감소하다 nil이 되면
    /// 타이머를 정리하고 `onFinished`를 호출한다.
    func beginStartCountdown(onFinished: @escaping () -> Void) {
        guard startCountdownValue == nil else { return }
        startCountdownValue = 3
        startCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let current = self.startCountdownValue else { return }
            let next = Self.nextCountdownValue(from: current)
            self.startCountdownValue = next
            if next == nil {
                self.cancelStartCountdown()
                onFinished()
            }
        }
    }

    /// 카운트다운 중단(연결 해제 또는 완료). 타이머 무효화 + 값 초기화.
    func cancelStartCountdown() {
        startCountdownTimer?.invalidate()
        startCountdownTimer = nil
        startCountdownValue = nil
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ChewChewIOSTests/StartCountdownStateTests`
Expected: PASS (3 tests)

- [ ] **Step 5: 시뮬레이터 빌드로 회귀 확인**

Run: `tuist generate --no-open && xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: 커밋**

```bash
git add ChewChewIOS/Models/AppState.swift ChewChewIOSTests/StartCountdownStateTests.swift
git commit -m "feat: 3-2-1 자동 시작 카운트다운 상태 추가"
```

---

### Task 3: AirPods 라우트 실시간 구독 추가

**Files:**
- Modify: `ChewChewIOS/Models/AppState.swift`

**Interfaces:**
- Consumes: `AppState.hasHeadphoneAudioRoute(outputs:)` (Task 1), `AppState.startCountdownValue`/`cancelStartCountdown()` (Task 2)
- Produces: `AppState.startWatchingAirPodsConnection(onConnected: @escaping () -> Void)`, `AppState.stopWatchingAirPodsConnection()` — Task 6이 사용

`AVAudioSession.routeChangeNotification`을 구독해, 라우트가 바뀔 때마다 헤드폰 라우트 포함 여부를 재판정한다. 연결되면 콜백을 호출하고, 카운트다운 진행 중에 연결이 끊기면 자동으로 카운트다운을 취소하고 팝업 상태로 되돌린다. 구독은 `NotificationCenter` 토큰으로 관리하고, `stopWatchingAirPodsConnection()`에서 반드시 해제한다(중복 구독·누수 방지). 카운트다운이 정상 완료됐을 때도 구독 해제가 필요하므로, Task 2의 `beginStartCountdown`을 이 Task에서 한 번 더 손봐 완료 훅에 구독 해제를 끼워 넣는다.

- [ ] **Step 1: `AppState`에 구독 관리 프로퍼티와 메서드 추가**

`ChewChewIOS/Models/AppState.swift`에서 `showAirPodsConnectionPrompt` 선언부(322번째 줄) 근처, Task 2에서 추가한 `startCountdownTimer` 프로퍼티 아래에 추가:

```swift
    /// AirPods 연결 실시간 감지용 알림 구독 토큰. nil이면 구독 중이 아님.
    private var airPodsRouteObserver: NSObjectProtocol?
```

같은 파일에서 Task 2가 추가한 `beginStartCountdown`/`cancelStartCountdown` 아래에 메서드 추가:

```swift
    /// AirPods 연결 팝업이 떠 있거나 카운트다운이 진행 중인 동안 라우트 변경을 실시간 관찰한다.
    /// 연결되는 순간 `onConnected`를 호출하고, 카운트다운 진행 중 연결이 끊기면 카운트다운을
    /// 취소하고 팝업 상태(`showAirPodsConnectionPrompt`)로 되돌린다.
    func startWatchingAirPodsConnection(onConnected: @escaping () -> Void) {
        stopWatchingAirPodsConnection()
        airPodsRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            let connected = AppState.hasHeadphoneAudioRoute(outputs: outputs)
            if connected {
                onConnected()
            } else if self.startCountdownValue != nil {
                self.cancelStartCountdown()
                self.showAirPodsConnectionPrompt = true
            }
        }
    }

    /// 팝업 dismiss(연결 감지든 "다음에 할게요"든) 또는 카운트다운 완료 시 반드시 호출해 구독을 해제한다.
    func stopWatchingAirPodsConnection() {
        if let airPodsRouteObserver {
            NotificationCenter.default.removeObserver(airPodsRouteObserver)
        }
        airPodsRouteObserver = nil
    }
```

- [ ] **Step 2: `beginStartCountdown` 완료 훅에 구독 해제 추가**

Task 2에서 추가한 `beginStartCountdown(onFinished:)`을 다음 최종형으로 교체(카운트다운이 끝나 측정이 시작될 때 구독도 함께 정리):

```swift
    /// 카운트다운 시작. 이미 진행 중이면 무시. 1초 간격으로 감소하다 nil이 되면
    /// 타이머와 라우트 구독을 정리하고 `onFinished`를 호출한다.
    func beginStartCountdown(onFinished: @escaping () -> Void) {
        guard startCountdownValue == nil else { return }
        startCountdownValue = 3
        startCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let current = self.startCountdownValue else { return }
            let next = Self.nextCountdownValue(from: current)
            self.startCountdownValue = next
            if next == nil {
                self.cancelStartCountdown()
                self.stopWatchingAirPodsConnection()
                onFinished()
            }
        }
    }
```

- [ ] **Step 3: 시뮬레이터 빌드로 컴파일 확인**

Run: `tuist generate --no-open && xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

이 메서드는 실시간 `NotificationCenter` 콜백에 의존해 XCTest로 직접 검증하기 어렵다(실기기 라우트 변경 필요). 빌드 성공 + Task 6의 통합 지점에서 수동 검증(실기기)으로 커버한다.

- [ ] **Step 4: 커밋**

```bash
git add ChewChewIOS/Models/AppState.swift
git commit -m "feat: AirPods 라우트 변경 실시간 구독 추가"
```

---

### Task 4: AirPodsPromptDialogView 신규 뷰

**Files:**
- Create: `ChewChewIOS/Views/AirPodsPromptDialogView.swift`

**Interfaces:**
- Consumes: `RewardDialogView`와 동일한 카드 톤 토큰(`Color.bgPopover`, `AppRadius.page`, `.appElevation(.floating)`), `OnboardingTutorialView.skipBar`와 동일 규격의 버튼 스타일(`Font.appFont(.boldLabel)`, `Color.textMuted`, `AppSpacing.oneHalf`/`.inner`)
- Produces: `AirPodsPromptDialogView(onDismissTapped: () -> Void)` — Task 6(ContentView)이 사용

`RewardDialogView.swift`의 카드 구조(이미지 + 제목 + 서브타이틀, `bgPopover` 배경, `AppRadius.page`, `.appElevation(.floating)`)를 따르되 자동 dismiss는 없다. 우상단에 "다음에 할게요" 버튼을 오버레이한다.

- [ ] **Step 1: 뷰 파일 작성**

`ChewChewIOS/Views/AirPodsPromptDialogView.swift` 새로 생성:

```swift
import SwiftUI

/// AirPods 미연결 시 표시하는 팝업. `RewardDialogView`와 같은 카드 톤(다람이 이미지 +
/// 타이틀 + 서브타이틀)이되, 자동 dismiss가 없고 우상단에 온보딩 `skipBar`와 동일 규격의
/// "다음에 할게요" 버튼을 둔다. 연결이 감지되면 호출부(ContentView)가 이 뷰를 내리고
/// 카운트다운으로 전환한다.
struct AirPodsPromptDialogView: View {
    let onDismissTapped: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: AppSpacing.cell) {
                Image("DaramHi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.image, height: Metrics.image)

                Text("에어팟을 착용해주세요!")
                    .font(.appFont(.heavyHeadlineLarge))
                    .foregroundStyle(Color.textDefault)
                    .multilineTextAlignment(.center)

                Text("AirPods Pro · 3·4세대 중 하나를 연결하면 자동으로 측정이 시작돼요")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, Metrics.contentTopPadding)
            .padding(.bottom, AppSpacing.dialogContentV)
            .padding(.horizontal, AppSpacing.dialogContentH)
            .frame(maxWidth: AppSize.dialogMaxWidth)
            .background(Color.bgPopover, in: RoundedRectangle(cornerRadius: AppRadius.page))
            .appElevation(.floating)

            skipButton
        }
    }

    private var skipButton: some View {
        Button(action: onDismissTapped) {
            Text("다음에 할게요")
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textMuted)
                .padding(.vertical, AppSpacing.oneHalf)
                .padding(.horizontal, AppSpacing.inner)
        }
        .accessibilityIdentifier("AirPodsPromptSkip")
        .padding(.trailing, AppSpacing.three)
        .padding(.top, AppSpacing.three)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        AirPodsPromptDialogView(onDismissTapped: {})
            .padding(.horizontal, AppSpacing.overlayH)
    }
}

private enum Metrics {
    static let image: CGFloat = 110
    static let contentTopPadding: CGFloat = 40
}
```

- [ ] **Step 2: 시뮬레이터 빌드로 컴파일 확인**

Run: `tuist generate --no-open && xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Xcode 프리뷰로 시각 확인**

Xcode에서 `AirPodsPromptDialogView.swift`를 열고 캔버스 프리뷰 실행. 다람이 이미지, 타이틀, 서브타이틀, 우상단 "다음에 할게요" 버튼이 온보딩 건너뛰기 버튼과 같은 룩인지 육안 확인.

- [ ] **Step 4: 커밋**

```bash
git add ChewChewIOS/Views/AirPodsPromptDialogView.swift
git commit -m "feat: AirPods 연결 안내 팝업 뷰 추가"
```

---

### Task 5: StartCountdownView 신규 뷰

**Files:**
- Create: `ChewChewIOS/Views/StartCountdownView.swift`

**Interfaces:**
- Consumes: `AppState.startCountdownValue: Int?` (Task 2)
- Produces: `StartCountdownView(value: Int)` — Task 6(ContentView)이 사용

3, 2, 1 숫자가 순서대로 큼직하게 나타나는 오버레이. 숫자가 바뀔 때마다 스케일+페이드 트랜지션을 준다.

- [ ] **Step 1: 뷰 파일 작성**

`ChewChewIOS/Views/StartCountdownView.swift` 새로 생성:

```swift
import SwiftUI

/// AirPods 연결 감지 후 자동 측정 시작 전 3-2-1 카운트다운 오버레이.
/// `AppState.startCountdownValue`가 nil이 아닌 동안 ContentView가 이 뷰를 그린다.
struct StartCountdownView: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.bgPopover)
                .frame(width: Metrics.circle, height: Metrics.circle)
                .appElevation(.floating)

            Text("\(value)")
                .font(.appFont(.heavyDisplay))
                .foregroundStyle(Color.textActionStrong)
                .monospacedDigit()
                .id(value)
                .transition(.scale(scale: 1.3).combined(with: .opacity))
        }
        .animation(.spring(response: AppMotion.springResponse, dampingFraction: AppMotion.springDampingFraction), value: value)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        StartCountdownView(value: 3)
    }
}

private enum Metrics {
    static let circle: CGFloat = 120
}
```

- [ ] **Step 2: 시뮬레이터 빌드로 컴파일 확인**

Run: `tuist generate --no-open && xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Xcode 프리뷰로 시각 확인**

Xcode에서 `StartCountdownView.swift`를 열고 캔버스 프리뷰 실행. 숫자가 원형 배경 위에 큼직하게 표시되는지 확인.

- [ ] **Step 4: 커밋**

```bash
git add ChewChewIOS/Views/StartCountdownView.swift
git commit -m "feat: 3-2-1 자동 시작 카운트다운 뷰 추가"
```

---

### Task 6: HomeView + ContentView 통합 배선

**Files:**
- Modify: `ChewChewIOS/Views/HomeView.swift:74-104` (`handleMealToggle()`)
- Modify: `ChewChewIOS/ContentView.swift:119-124` (`airPodsPromptBinding` + `.appDialog`), `ContentView.swift:168-173` (`airPodsPromptBinding` 정의)

**Interfaces:**
- Consumes: `AppState.showAirPodsConnectionPrompt` (기존), `AppState.startWatchingAirPodsConnection(onConnected:)`/`stopWatchingAirPodsConnection()` (Task 3), `AppState.startCountdownValue`/`beginStartCountdown(onFinished:)`/`cancelStartCountdown()` (Task 2·3), `AirPodsPromptDialogView` (Task 4), `StartCountdownView` (Task 5), `AppState.toggleEating()` (기존)
- Produces: 없음 (최종 통합 지점)

전체 상태 흐름을 배선한다. 두 경로 모두 카운트다운을 거친다:
- **미연결 경로**: 팝업 표시 + 구독 시작 → 연결 감지 시 팝업 닫고 카운트다운 시작 → 완료 시 `toggleEating()`
- **연결됨 경로**: 팝업 없이 바로 구독 시작 + 카운트다운 시작 → 완료 시 `toggleEating()`

두 경로 모두 카운트다운 중 연결이 끊기면 Task 3의 `startWatchingAirPodsConnection` 콜백이 자동으로 카운트다운을 취소하고 `showAirPodsConnectionPrompt = true`로 되돌린다(팝업이 그제서야 뜬다).

- [ ] **Step 1: `HomeView.handleMealToggle()`에서 미연결 시 팝업 표시 + 구독 시작**

`ChewChewIOS/Views/HomeView.swift:83-86`의 기존 코드:

```swift
        if status == .denied || status == .restricted || !available || !hasHeadphoneAudioRoute {
            state.showAirPodsConnectionPrompt = true
            return
        }
```

를 다음으로 교체:

```swift
        if status == .denied || status == .restricted || !available || !hasHeadphoneAudioRoute {
            state.showAirPodsConnectionPrompt = true
            state.startWatchingAirPodsConnection { [weak state] in
                guard let state else { return }
                state.showAirPodsConnectionPrompt = false
                state.beginStartCountdown {
                    state.toggleEating()
                }
            }
            return
        }
```

`HomeView.swift:94-96`의 기존 코드:

```swift
            } onDenied: {
                state.showAirPodsConnectionPrompt = true
            }
```

도 동일 패턴으로 교체:

```swift
            } onDenied: {
                state.showAirPodsConnectionPrompt = true
                state.startWatchingAirPodsConnection { [weak state] in
                    guard let state else { return }
                    state.showAirPodsConnectionPrompt = false
                    state.beginStartCountdown {
                        state.toggleEating()
                    }
                }
            }
```

참고: `state.stopWatchingAirPodsConnection()`은 여기서 호출하지 않는다 — 카운트다운 도중 연결이 끊기는 경우를 계속 감지해야 하므로 구독은 Task 3의 `beginStartCountdown` 완료 훅(측정 시작 시점) 또는 Step 2에서 배선할 "다음에 할게요" 탭에서만 해제된다.

- [ ] **Step 2: 이미 연결된 경로도 팝업 없이 카운트다운을 거치도록 교체**

`HomeView.handleMealToggle()`에서 REQ-01 권한 가드를 통과한 뒤 즉시 시작하던 두 지점을 카운트다운 경유로 바꾼다.

`ChewChewIOS/Views/HomeView.swift:89-98`의 기존 코드(notDetermined → 권한 허용된 케이스):

```swift
        // REQ-01: notDetermined이면 즉시 시작하지 않고 권한 요청 → 결과에 따라 분기.
        if !AppState.shouldStartImmediately(status: status, available: available) {
            state.requestMotionPermission {
                // 권한 허용됨 — 햅틱 + 측정 시작
                hapticTrigger.toggle()
                state.startEating()
            } onDenied: {
                state.showAirPodsConnectionPrompt = true
                state.startWatchingAirPodsConnection { [weak state] in
                    guard let state else { return }
                    state.showAirPodsConnectionPrompt = false
                    state.beginStartCountdown {
                        state.toggleEating()
                    }
                }
            }
            return
        }
        #endif

        // 차단 안 됐을 때만 햅틱 + 시작
        hapticTrigger.toggle()
        state.toggleEating()
    }
```

를 다음으로 교체(마지막 `#endif`와 메서드 닫는 중괄호까지 포함):

```swift
        // REQ-01: notDetermined이면 즉시 시작하지 않고 권한 요청 → 결과에 따라 분기.
        if !AppState.shouldStartImmediately(status: status, available: available) {
            state.requestMotionPermission {
                // 권한 허용됨 — 햅틱 + 연결 상태 감지하며 카운트다운 시작
                hapticTrigger.toggle()
                // onConnected는 "미연결→연결" 전환에만 반응하므로 이미 연결된 이 경로에선
                // 실질적으로 호출되지 않는다 — startWatchingAirPodsConnection의 시그니처를
                // 맞추기 위한 no-op 콜백이며, 실제 취소/복귀 처리는 라우트 콜백 내부의
                // "연결 안 됨 + 카운트다운 중" 분기(Task 3)가 담당한다.
                state.startWatchingAirPodsConnection { }
                state.beginStartCountdown {
                    state.toggleEating()
                }
            } onDenied: {
                state.showAirPodsConnectionPrompt = true
                state.startWatchingAirPodsConnection { [weak state] in
                    guard let state else { return }
                    state.showAirPodsConnectionPrompt = false
                    state.beginStartCountdown {
                        state.toggleEating()
                    }
                }
            }
            return
        }
        #endif

        // 이미 연결·권한 OK — 팝업 없이 바로 카운트다운. 카운트다운 중 연결이 끊기면
        // startWatchingAirPodsConnection 콜백 내부의 "연결 안 됨 + 카운트다운 중" 분기가
        // 자동으로 카운트다운을 취소하고 showAirPodsConnectionPrompt를 true로 되돌려 팝업을 띄운다.
        hapticTrigger.toggle()
        state.startWatchingAirPodsConnection { }
        state.beginStartCountdown {
            state.toggleEating()
        }
    }
```

- [ ] **Step 3: `ContentView`의 alert를 커스텀 팝업 + 카운트다운 오버레이로 교체**

`ChewChewIOS/ContentView.swift:119-124`의 기존 코드:

```swift
        .appDialog(
            isPresented: airPodsPromptBinding,
            title: "AirPods를 연결해 주세요",
            message: "AirPods Pro · 3·4세대 중 하나를 연결하고 착용해 주세요.",
            primary: .init("확인") {}
        )
```

를 제거한다.

같은 파일의 `RewardDialogView` overlay 블록(145-158번째 줄) 바로 아래에 새 오버레이 두 개를 추가:

```swift
        .overlay(alignment: .center) {
            if state.showAirPodsConnectionPrompt {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    AirPodsPromptDialogView {
                        state.showAirPodsConnectionPrompt = false
                        state.stopWatchingAirPodsConnection()
                    }
                    .padding(.horizontal, AppSpacing.overlayH)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(10)
            }
        }
        .overlay(alignment: .center) {
            if let countdownValue = state.startCountdownValue {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    StartCountdownView(value: countdownValue)
                }
                .transition(.opacity)
                .zIndex(11)
            }
        }
        .animation(.spring(response: AppMotion.springFastResponse, dampingFraction: AppMotion.springDampingFraction), value: state.showAirPodsConnectionPrompt)
        .animation(.easeInOut(duration: AppMotion.durationStateChange), value: state.startCountdownValue)
```

`ContentView.swift:168-173`의 이제 쓰이지 않는 `airPodsPromptBinding` 프로퍼티를 삭제한다:

```swift
    private var airPodsPromptBinding: Binding<Bool> {
        Binding(
            get: { state.showAirPodsConnectionPrompt },
            set: { newValue in if !newValue { state.showAirPodsConnectionPrompt = false } }
        )
    }
```

- [ ] **Step 4: 시뮬레이터 빌드로 회귀 확인**

Run: `tuist generate --no-open && xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 전체 테스트 스위트 실행**

Run: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: 모든 테스트 PASS (기존 테스트 회귀 없음 + Task 1/2에서 추가한 신규 테스트 포함)

- [ ] **Step 6: swiftlint 통과 확인**

Run: `swiftlint`
Expected: 새로 추가/수정한 파일에 경고 없음 (`ododok/CLAUDE.md` 규칙 — lint 경고는 완료로 보지 않는다).

- [ ] **Step 7: 실기기 수동 검증 (시뮬레이터는 이 플로우를 타지 않음)**

시뮬레이터 빌드는 `#if !targetEnvironment(simulator)` 가드로 인해 이 플로우 자체가 스킵된다. 실기기에서 다음을 확인한다:
1. AirPods 미연결 상태에서 "식사 시작" 탭 → `AirPodsPromptDialogView` 팝업이 뜨는지 (지금의 확인 버튼형 다이얼로그 아님)
2. 팝업이 뜬 상태에서 AirPods를 연결 → 팝업이 자동으로 사라지고 3-2-1 카운트다운이 뜨는지
3. AirPods가 이미 연결된 상태에서 "식사 시작"을 탭 → 팝업 없이 곧바로 3-2-1 카운트다운이 뜨는지(즉시 시작되지 않는지)
4. 두 경로 모두 카운트다운 완료 후 자동으로 측정이 시작되는지(`state.isEating == true`)
5. 카운트다운 진행 중 AirPods를 뺐을 때(미연결 경로·연결됨 경로 둘 다) 카운트다운이 즉시 취소되고 팝업으로 돌아가는지
6. 팝업에서 "다음에 할게요"를 탭하면 팝업이 닫히고 측정이 시작되지 않는지

- [ ] **Step 8: 커밋**

```bash
git add ChewChewIOS/Views/HomeView.swift ChewChewIOS/ContentView.swift
git commit -m "feat: AirPods 팝업+카운트다운 자동 시작 플로우 통합"
```

---

## Self-Review Notes

- **스펙 커버리지:** 설계 문서(`docs/superpowers/specs/2026-07-07-airpods-auto-start-design.md`)의 목표 1~6 전부 Task 4(팝업), Task 6(감지 통합 + 연결됨 경로도 카운트다운 경유), Task 2+6(카운트다운 자동 시작), Task 3+6(끊기면 취소)에 매핑됨. 비목표(모션 권한 denied/restricted UX 변경, 온보딩 플로우 변경)는 이번 계획에서 건드리지 않음.
- **플레이스홀더 스캔:** 전 단계 코드 블록 완전 포함, "TODO"/"나중에" 문구 없음.
- **타입 일관성:** `hasHeadphoneAudioRoute(outputs:)`, `isHeadphoneRoute(_:)`, `nextCountdownValue(from:)`, `startCountdownValue`, `beginStartCountdown(onFinished:)`, `cancelStartCountdown()`, `startWatchingAirPodsConnection(onConnected:)`, `stopWatchingAirPodsConnection()` — 모든 태스크에서 동일 이름으로 참조됨을 확인. Task 순서(1→2→3→4→5→6)를 의존성 순서와 일치시켜, 뒤 Task가 앞 Task의 코드를 "교체"하는 대신 앞 Task를 그대로 두고 새 메서드만 추가하도록 정리함(Task 3이 Task 2의 `beginStartCountdown`을 한 번 더 다루는 지점만 예외 — 구독 해제 훅 추가이므로 명시적으로 "최종형으로 교체"라고 표기). Task 6 Step 2에서 "이미 연결된 경로"도 `startWatchingAirPodsConnection`을 호출하도록 추가— 이 경로의 `onConnected` 콜백은 라우트가 이미 헤드폰이라 사실상 트리거되지 않는 no-op이며, 실질적 취소·복귀 로직은 Task 3의 "연결 안 됨 + 카운트다운 중" 분기가 전담함을 확인.
