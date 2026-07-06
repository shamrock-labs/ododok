# ChewChewIOS

ChewChew (다람쥐 헬스 리워드 앱) iOS 네이티브 구현. 같은 부모 디렉토리의 `../notion_clover/demo/index.html` React/Tailwind 데모를 SwiftUI로 포팅한 결과물.

## 셋업

```bash
brew install --formula tuist    # 없으면

# 1) InsForge 비밀 키 설정
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# 그 다음 Config/Secrets.xcconfig 의 INSFORGE_API_KEY 를 실제 anon key로 교체.
# (대시보드: https://insforge.dev/dashboard/project/<project-id>/settings/api-keys)
# 이 파일은 .gitignore 에 들어가 커밋되지 않는다.

# 2) Xcode 프로젝트 생성 후 열기
tuist generate --no-open        # ChewChewIOS.xcworkspace 생성
open ChewChewIOS.xcworkspace
```

Xcode / iOS 17+ 시뮬레이터에서 빌드·실행. SwiftPM 의존성은 `Project.swift`의 Tuist manifest에서 관리한다.

> 백엔드(InsForge)는 InsForge CLI(`npx @insforge/cli`)로 별도 셋업되어 있어야 한다.
> 새 환경에서 처음 만들 때:
> ```
> npx @insforge/cli login --user-api-key <your-user-key>
> npx @insforge/cli link --project-id <project-id>
> npx @insforge/cli db migrations up --all
> npx @insforge/cli storage create-bucket imu-sessions --private
> ```

## 구조

```
ChewChewIOS/
├── ChewChewIOSApp.swift      # @main 엔트리
├── ContentView.swift          # 탭 컨테이너
├── Models/
│   ├── AppState.swift         # @Observable 앱 상태 facade
│   ├── ShopItem.swift         # 의상/도토리팩 정적 데이터
│   └── MoodStatus.swift       # 4표정 분기 + 피드백 라인
├── Features/                  # 도메인별 Store·View·포트·어댑터 (Auth/Records/Friends/Reminder/MealSession)
├── Infra/                     # 여러 Feature가 공유하는 인프라 (RemoteStore·TokenManager·DeviceIdentity·config)
├── SignalProcessing/          # IMU 신호처리와 씹기 감지 알고리즘
├── Analytics/                 # Amplitude/Firebase/Sentry 계측 포트와 어댑터
├── DesignSystem/
│   ├── Colors.swift           # acorn/sage/butter/blush/ink 토큰
│   ├── Shadows.swift          # 뉴모피즘 그림자 modifier
│   └── Constants.swift        # dailyGoal, pointsPerChew
├── Views/
│   ├── HomeView.swift
│   ├── TrackingView.swift
│   ├── ShopView.swift
│   └── Components/
│       ├── SquirrelView.swift
│       └── TabBar.swift
└── Resources/Assets.xcassets/
    ├── DaramSleepy / DaramHappy / DaramPuffy / DaramChamp
    ├── AppIcon (placeholder)
    └── AccentColor
```

## 앱 구조 규칙

새 코드는 먼저 어느 레이어에 속하는지 정한 뒤 배치한다. 기존 파일에 붙여 넣는 것을 기본값으로 삼지 않는다.

- `Views/`: SwiftUI 화면과 작은 UI 컴포넌트만 둔다. 네트워크 호출, 파일 저장, 오디오 제어, 알고리즘 판단을 직접 하지 않는다.
- `Models/`: 화면 상태, DTO가 아닌 앱 내부 모델, 값 타입을 둔다. 외부 시스템 호출은 넣지 않는다.
- `Infra/`: 여러 Feature가 공유하는 외부 효과 어댑터·포트(RemoteStore, SpringRemoteStore, TokenManager, DeviceIdentity, config, NotificationDelegate). Feature 전용 어댑터·Provider는 해당 `Features/<Feature>/`에 둔다.
- `SignalProcessing/`: IMU 신호처리처럼 입력 데이터로 판단 결과를 만드는 알고리즘을 둔다. UI 상태나 서버 저장을 직접 알지 않는다.
- `Analytics/`: 이벤트 이름, 속성 스키마, provider fan-out을 둔다. 화면과 `AppState`는 이벤트 호출만 한다.
- `DesignSystem/`: 색, 폰트, 간격, 그림자, 공통 modifier를 둔다. 특정 화면의 비즈니스 조건을 넣지 않는다.

AI나 사람이 새 기능을 추가할 때는 아래 순서를 따른다.

1. 화면만 바뀌면 `Views/` 안에서 끝낸다.
2. 상태가 필요하면 `AppState`에 최소 상태만 추가한다.
3. 외부 효과가 있으면 공유는 `Infra/`, Feature 전용은 해당 `Features/<Feature>/`에 타입을 만들고 `AppState`는 호출만 한다.
4. 판단 로직이 테스트 가능하면 순수 함수나 `SignalProcessing/` 타입으로 분리한다.
5. 같은 코드가 두 화면 이상에서 필요해질 때만 공통 컴포넌트나 helper로 올린다.

### 목표 배치: 도메인(Feature)별

레이어별(`Views/`·`Models/`·`Infra/`)은 한 기능이 세 폴더에 흩어져 국소적 이해를 떨어뜨린다. 목표는 도메인별 배치다 — 한 기능의 Store·View·포트(Repository 프로토콜)를 `Features/<Feature>/` 한 폴더에 모은다.

- Store 기반 새 기능은 `Features/<Feature>/`에서 태어난다. `Models/`·`Views/`에 흩지 않는다.
- 공유 코드(`RemoteStore` 프로토콜, `DesignSystem/`·`Analytics/`·`SignalProcessing/`·`Utils/`)와 어댑터 구현은 기능 폴더에 넣지 않고 레이어 폴더에 둔다.
- 기존 코드는 한 번에 옮기지 않는다. 리팩터 PR마다 그 기능만 `Features/`로 co-locate한다(전환 중 하이브리드 허용).
- 설계 정본은 Obsidian `Projects/ododok/24 ios-domain-architecture-refactor.md`.

## AppState 경계 규칙

`AppState`는 SwiftUI 화면이 관찰하는 앱 상태 facade다. 스프링으로 치면 Controller, Service, Session State를 전부 합친 클래스가 아니라, 화면에 필요한 상태를 들고 작은 coordinator/service를 호출하는 얇은 진입점에 가깝게 유지한다.

새 기능을 넣을 때는 아래 순서를 기본 규칙으로 삼는다.

- 화면 표시 상태, sheet/alert 플래그, 화면에서 직접 관찰해야 하는 값만 `AppState`에 둔다.
- 네트워크, 오디오, 알림, 파일, Sentry/Analytics처럼 외부 효과가 있는 로직은 공유는 `Infra/`, Feature 전용은 해당 `Features/`의 어댑터로 뺀다.
- 식사 측정, 온보딩, 친구 초대처럼 여러 서비스를 묶는 절차는 `AppState`에 길게 쓰지 말고 작은 private method나 별도 coordinator로 분리한다.
- 알고리즘 판단은 `SignalProcessing/` 또는 순수 함수로 두고, `AppState`는 입력과 결과 연결만 맡는다.
- 서버가 정본인 정책값은 앱에 매직넘버로 박지 않는다. 앱은 서버 값을 주입받고, 범위 정규화·fallback 같은 안전 처리만 한다.

줄 수 기준은 절대 규칙이 아니라 냄새 감지용이다. 300줄을 넘으면 역할을 한 번 점검하고, 600줄을 넘는 새 기능은 별도 타입 분리를 먼저 고려한다. 1000줄 이상 파일에 새 도메인 로직을 바로 추가하지 않는다.

## 코드 작성 원칙

관통하는 하나: 한 조각을 이해하거나 바꾸는 데 머릿속에 올려야 하는 맥락이 작아야 한다. 아래 원칙은 전부 "필요한 맥락을 줄인다"는 같은 목표의 다른 각도다. 예시는 실제 코드 감사에서 나온 사례다.

### 상태 하나엔 주인 하나

"이 값 누가 바꾸지?"의 답이 하나여야 한다. 여러 곳이 같은 상태를 쓰면 값이 "마지막에 누가 썼느냐"에 좌우된다.

```swift
// Don't — points를 서버 응답도 쓰고 로컬 구매도 쓴다. 어느 게 맞는지 알 수 없다.
func applyHome(_ home: HomeStateDTO) { points = home.points }   // 서버가 씀
func buyItem(_ item: ShopItem) { points -= item.price }         // 로컬이 씀

// Do — 정본은 서버 하나. 구매도 서버 왕복으로 새 잔액을 받아온다.
func buyItem(_ item: ShopItem) async throws {
    let updated = try await repository.purchase(item.id)  // 서버가 차감·검증
    apply(updated)                                        // 주인은 여전히 서버 응답
}
```

### 밀지 말고 당겨오게 하라

한 도메인의 변경이 다른 도메인을 갱신하러 가면(push) 결합이 생긴다. 각 화면이 자기 데이터를 자기 진입 시점에 당긴다(pull).

```swift
// Don't — 삭제가 홈까지 갱신하러 간다(기록→홈 결합).
func deleteAllSessions() async {
    try? await repository.deleteAll()
    await refreshFromServerHome()   // 남의 도메인을 밀어서 갱신
}

// Do — 삭제는 기록만. 홈은 자기 화면 진입 때 스스로 당긴다.
func deleteAllSessions() async throws {
    try await repository.deleteAll()
    monthSessions = []
}
// HomeView: .task { await home.refresh() }
```

### 정본이 서버면 클라이언트는 재계산하지 않는다

서버가 계산한 값을 앱이 다시 만들면 규칙이 두 곳으로 갈린다. 서버 값은 반영만 한다.

```swift
// Don't — 서버가 계산한 스트릭을 앱이 다시 만든다.
streak = lastStreak + (didChewToday ? 1 : 0)

// Do — 서버가 준 값을 그대로 반영.
streak = home.streak
```

### 실패를 삼키지 말고 상태로 드러내라

`try?`로 실패를 지우면 오류가 정상과 구분되지 않는다. 실패는 눈에 보이는 상태로 만든다.

```swift
// Don't — 실패를 삼켜 빈 목록. 오프라인이 "기록 없음"과 구분되지 않는다.
monthSessions = (try? await repository.fetchSessions(...)) ?? []

// Do — 실패를 상태로.
do {
    monthSessions = try await repository.fetchSessions(...)
    errorMessage = nil
} catch {
    errorMessage = "기록을 불러오지 못했어요."
}
```

### 같은 규칙은 한 집에 산다

같은 판정을 여러 곳에 복붙하면 한쪽만 바뀌어 모순이 생긴다. 규칙 하나 = 함수 하나.

```swift
// Don't — "리포트 가능한가"를 화면마다 복붙. 캘린더는 빼고 상세는 보여줘 모순이 난다.
rows.filter { ReportCardModel.from($0) != nil }   // 여러 곳에 흩어짐

// Do — 규칙 한 곳.
extension ChewingSessionDTO {
    var isReportable: Bool { ReportCardModel.from(self) != nil }
}
rows.filter(\.isReportable)
```

### 불가능한 상태를 타입으로 막아라

Bool을 여러 개 두면 말이 안 되는 조합이 컴파일된다. 한 번에 한 상태만 표현되게 만든다.

```swift
// Don't — "측정 중이면서 업로드 중" 같은 모순이 표현 가능하다.
var isMeasuring = false
var isPaused = false
var isUploading = false

// Do — 한 번에 한 상태만.
enum MealSessionPhase {
    case idle, measuring(Date), paused(Date), analyzing
    case completed(MealSession), failed(SessionFailure)
}
```

### 비동기 재요청엔 순번을 붙여라

`@MainActor`는 await 경계의 끼어듦을 막지 못한다. 다시 던지는 요청엔 generation을 붙여 마지막 것만 반영한다.

```swift
// Don't — 월 연타 시 늦게 온 이전 달 응답이 현재 달을 덮는다.
func moveMonth(_ delta: Int) async {
    displayedMonth = next(delta)
    monthSessions = try await repository.fetchSessions(month: displayedMonth)
}

// Do — generation으로 마지막 요청만 반영.
func moveMonth(_ delta: Int) async {
    displayedMonth = next(delta)
    loadGeneration &+= 1
    let gen = loadGeneration
    let rows = try await repository.fetchSessions(month: displayedMonth)
    guard gen == loadGeneration else { return }   // 그 사이 새 요청이 왔으면 버린다
    monthSessions = rows
}
```

### 바깥 세계는 주입으로 받아라

전역 싱글턴·실시계·실서버에 직접 의존하면 테스트가 하드웨어를 탄다. 의존을 주입하면 시그니처만 봐도 무엇에 기대는지 보인다.

```swift
// Don't — 전역 싱글턴에 직접 의존.
final class RecordsStore {
    func load() async {
        let rows = try? await SpringRemoteStore().fetch(DeviceIdentity.shared)
    }
}

// Do — 의존을 주입. fake로 실기기·실서버 없이 테스트된다.
final class RecordsStore {
    init(repository: MealSessionRepository, calendar: Calendar = .current) { ... }
}
```

### 큰 타입은 Type+기능.swift로 쪼갠다

한 타입이 커지면 기능별로 extension 파일에 나눈다. 파일명이 곧 "이 파일은 이 측면만 다룬다"를 알려준다.

```text
ProgressBar.swift            // 핵심 타입 정의
ProgressBar+Rendering.swift  // 터미널 출력만
ProgressBar+State.swift      // 상태 관리만
```

단, extension 분리는 파일 크기만 줄인다. 같은 타입의 저장 프로퍼티를 계속 공유하므로 소유권·결합은 풀리지 않는다. 상태를 여러 도메인이 나눠 가진 거대 타입(예: `AppState`)은 extension으로 쪼개지 말고 별도 타입(Store)으로 추출한다. 파일 나누기(cosmetic)와 책임 나누기(구조)를 구분한다.

### 동시성은 @MainActor로, 수동 락은 쓰지 않는다

Store와 `AppState`는 `@MainActor`로 두어 단일 스레드로 격리한다. `NSLock`·`withLock` 같은 수동 락을 추가하지 않는다 — 액터 격리와 중복이고 오히려 위험을 늘린다. `await` 경계에서 생기는 순서 문제는 락이 아니라 generation/latest-wins로 푼다("비동기 재요청엔 순번을 붙여라" 참고).

## 온보딩 닉네임

첫 실행 온보딩은 닉네임 입력 후 사용법 튜토리얼로 이어진다. 사용자가 닉네임 입력을 건너뛰면 앱이 `다람이 1234` 형태의 랜덤 닉네임을 생성해 동일한 저장 경로로 처리한다.

- 앱 책임: 랜덤 닉네임 생성, `AppState.saveDisplayName` 호출, 로컬 캐시 갱신.
- 서버 책임: 기존 `PUT /v1/me/profile` 요청의 `displayName` 저장과 온보딩 완료 처리.
- 별도 서버 API는 두지 않는다. 수동 입력과 건너뛰기 모두 같은 `displayName` 계약을 사용한다.

## 데모와의 매핑

| 데모 (React/Tailwind) | 네이티브 (SwiftUI) |
|---|---|
| `useState` 글로벌 상태 | `@Observable AppState` |
| `Phone` 390×844 프레임 | 실제 디바이스 safe area |
| `chew-bounce` 키프레임 | `spring(response: 0.42, dampingFraction: 0.55)` |
| `wave-bar` 키프레임 | `easeInOut(repeatForever)` + 지연 |
| Tailwind 색상 클래스 (`text-acorn-600`) | `Color.acorn600` 정적 상수 |
| 뉴모피즘 그림자 (`shadow-neuo-sm`) | `.neuoShadow(.sm)` |
| `setInterval(chew, 700–1100)` | `Timer.scheduledTimer(0.85)` |
| lucide-react 아이콘 | SF Symbols |

## 다음 단계

- [ ] AirPods Pro 2 IMU 연동 (`CMHeadphoneMotionManager`)
- [ ] 영구 저장소 (SwiftData 또는 UserDefaults)
- [ ] 알림 (아침 8시 식사 리마인더)
- [ ] HealthKit 연동
- [ ] 앱 아이콘 — 현재 placeholder
