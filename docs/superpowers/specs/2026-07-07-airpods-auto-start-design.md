# AirPods 자동 시작 플로우 설계

## 배경

현재 `HomeView.handleMealToggle()`은 식사 시작 시 AirPods 연결·모션 권한을 확인하고, 미충족이면 `state.showAirPodsConnectionPrompt = true`를 세팅해 시작 자체를 막는다. `ContentView`는 이 플래그를 시스템 alert 스타일의 `AppDialog`("AirPods를 연결해 주세요" + 확인 버튼 하나)로 표시한다.

이 alert는 확인을 눌러도 아무 일도 일어나지 않아(빈 클로저), 사용자가 직접 AirPods를 연결한 뒤 시작 버튼을 다시 눌러야 한다. 이 왕복을 없애고, 팝업 디자인도 도토리 적립 팝업(`RewardDialogView`)과 같은 톤으로 통일한다.

또한 현재는 AirPods가 이미 연결된 상태에서 시작 버튼을 누르면 아무 연출 없이 즉시 측정이 시작돼, 사용자가 "식사를 시작한다"는 경험을 체감하기 어렵다. 이번 변경으로 연결 여부와 무관하게 시작 버튼을 누르면 항상 3-2-1 카운트다운을 거치도록 해, 시작 순간의 체감을 준다.

## 목표

1. 시작 버튼을 눌렀을 때 AirPods 미연결이면 alert 대신 `RewardDialogView` 톤의 커스텀 팝업을 띄운다.
2. 팝업에는 온보딩 `skipBar`와 동일 규격의 "다음에 할게요" 버튼을 우상단에 둔다.
3. 팝업이 떠 있는 동안 AirPods 연결 상태를 실시간으로 관찰하다가, 연결되는 순간 팝업을 닫고 3-2-1 카운트다운을 자동 시작한다.
4. AirPods가 이미 연결된 상태에서 시작 버튼을 눌러도(팝업을 거치지 않는 경로) 즉시 시작이 아니라 동일한 3-2-1 카운트다운을 거친 뒤 측정을 시작한다.
5. 카운트다운이 끝나면 자동으로 식사 측정을 시작한다(`state.startEating()` 경로 — 이 시점엔 항상 미시작 상태이므로 `toggleEating()`의 종료 분기를 탈 일이 없다).
6. 카운트다운 도중 연결이 끊기면 즉시 카운트다운을 취소하고 팝업으로 되돌아간다.

## 비목표

- 모션 권한이 `.denied`/`.restricted`인 케이스의 UX 변경 (권한 자체가 없으면 연결해도 시작 불가 — 별도 안내가 필요하지만 이번 스코프 밖. 기존 alert 문구를 그대로 유지하거나, 이번 팝업과 통합할지는 구현 단계에서 판단)
- 온보딩 플로우 자체 변경 (건너뛰기 버튼 스타일만 참조)

## 현재 코드 구조

- `Views/HomeView.swift` `handleMealToggle()`: 시작 가드. `CMHeadphoneMotionManager.authorizationStatus()` + `hasHeadphoneAudioRoute`(현재 라우트 1회 스냅샷)로 판정
- `Models/AppState.swift`: `showAirPodsConnectionPrompt: Bool`, `startEating()`, `toggleEating()`, `requestMotionPermission(onGranted:onDenied:)`, `shouldStartImmediately(status:available:)`
- `ContentView.swift`: `airPodsPromptBinding` → `.appDialog(...)`로 alert 표시
- `Views/RewardDialogView.swift`: 다람이 이미지 + 타이틀 + 서브타이틀 카드형 팝업, 2.5초 자동 dismiss, 탭으로도 dismiss — 참조 디자인
- `Views/OnboardingTutorialView.swift` `skipBar`: 우상단 텍스트 버튼 (`boldLabel` 폰트, `textMuted` 색, `AppSpacing.oneHalf`/`inner` 패딩) — 참조 버튼 스타일

## 설계

### 1. 새 팝업 뷰: `AirPodsPromptDialogView`

`RewardDialogView`와 같은 카드 톤(다람이 이미지 + 타이틀 + 서브타이틀, `bgPopover` 배경, `AppRadius.page`, `appElevation(.floating)`)으로 구성하되:

- 자동 dismiss 없음 (연결 감지 또는 "다음에 할게요"로만 닫힘)
- 우상단에 `OnboardingTutorialView.skipBar`와 동일 규격의 "다음에 할게요" 버튼 오버레이
- 다람이 이미지는 기존 에셋 중 하나 재사용(예: 대기 상태에 어울리는 `DaramHi` 또는 `DaramSad` — 구현 시 확정)
- 텍스트: "에어팟을 착용해주세요!" (정확한 문구는 구현 시 확정)

### 2. AirPods 연결 실시간 감지

기존 `hasHeadphoneAudioRoute`는 호출 시점의 스냅샷만 본다. 팝업이 떠 있는 동안 지속 관찰하려면 `AVAudioSession.routeChangeNotification`을 구독하는 로직이 필요하다.

- `AppState`에 관찰 시작/중단 메서드 추가 (예: `startWatchingAirPodsConnection(onConnected:)` / `stopWatchingAirPodsConnection()`)
- 팝업이 뜨는 시점(`showAirPodsConnectionPrompt = true`)에 구독 시작, 팝업이 닫히는 시점(연결 감지 또는 "다음에 할게요")에 구독 해제
- 알림 콜백에서 `hasHeadphoneAudioRoute` 재평가 → true면 연결됨으로 판단

### 3. 카운트다운 뷰: 신규 컴포넌트

- 3 → 2 → 1 순서로 숫자를 표시하는 오버레이 뷰 (신규, 기존에 없음)
- 진입 경로 두 가지 모두 이 카운트다운을 거친다: (a) 미연결 → 팝업 → 연결 감지 → 카운트다운, (b) 이미 연결됨 → 팝업 없이 바로 카운트다운
- 두 경로 모두 카운트다운 시작과 동시에 라우트 감지 구독을 시작(또는 유지)한다 — 끊기면 카운트다운 취소 + 팝업 상태로 복귀
- 카운트다운 완료 시 `state.toggleEating()`(또는 동등 시작 경로) 호출

### 4. 상태 흐름 정리

```
시작 버튼 탭
  ├─ AirPods 연결됨 + 권한 OK → 팝업 없이 바로 카운트다운 → state.startEating()
  │      └─ 카운트다운 중 연결 끊김 → 카운트다운 취소 → 팝업 복귀
  └─ AirPods 미연결/권한 미확정
        → 팝업 표시 + 라우트 감지 구독 시작
              ├─ 연결 감지 → 팝업 닫힘 → 카운트다운 → state.startEating()
              │      └─ 카운트다운 중 연결 끊김 → 카운트다운 취소 → 팝업 복귀
              └─ "다음에 할게요" 탭 → 팝업 닫힘 + 구독 해제, 시작 안 함
```

연결됨 경로(팝업 없이 바로 카운트다운)에서도 카운트다운 중 연결이 끊길 수 있으므로, 이 경로 진입 시에도 라우트 감지 구독을 시작해야 한다 — 팝업 표시 여부와 무관하게 "카운트다운이 진행 중인 동안"이 구독의 생명주기 기준이다.

### 5. 상태 관리 위치

`showAirPodsConnectionPrompt`는 유지하되, 카운트다운 여부를 나타내는 새 상태(예: `isShowingStartCountdown: Bool` 또는 카운트다운 남은 값)를 `AppState`에 추가한다. `ContentView`의 오버레이 구성이 alert 하나에서 "팝업 오버레이 + 카운트다운 오버레이" 두 단계로 늘어난다.

## 테스트 고려사항

- 시뮬레이터에서는 `#if !targetEnvironment(simulator)` 가드로 인해 이 플로우 자체가 스킵된다 — 실기기 검증이 필요하다는 점을 유지한다.
- 라우트 체인지 알림 구독/해제가 짝이 맞는지(메모리 누수·중복 구독 방지) 확인이 필요하다.
