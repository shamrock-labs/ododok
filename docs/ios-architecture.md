# iOS 아키텍처 작성 기준

이 문서는 ChewChewIOS에 새 코드를 작성할 때 따르는 구조 기준이다. `README.md`는 프로젝트 진입점, 이 문서는 구현 규칙, `docs/ios-review-guide.md`는 리뷰 루브릭이다.

설계의 기준은 Obsidian `Projects/ododok/24 ios-domain-architecture-refactor.md`이고, 작업 상태의 기준은 Linear다. 문서에 상태를 복제하지 않는다.

## 기본 방향

ChewChewIOS는 Feature-first 구조를 따른다. 한 기능을 이해할 때 필요한 View, Store, 포트, Feature 전용 어댑터를 가능한 한 `Features/<Feature>/` 안에 함께 둔다.

```text
ChewChewIOS/
├── Features/
│   ├── Auth/
│   ├── Home/
│   ├── Records/
│   ├── Reminder/
│   ├── Friends/
│   └── MealSession/
├── Infra/
├── Models/
├── SignalProcessing/
├── Analytics/
├── DesignSystem/
└── Views/
```

새 코드는 기존 파일에 붙이는 것을 기본값으로 삼지 않는다. 먼저 어느 Feature와 경계에 속하는지 정한다.

## 폴더별 책임

| 위치 | 책임 | 넣지 않는 것 |
| -- | -- | -- |
| `Features/<Feature>/` | 기능 단위 View, Store, 포트, Feature 전용 어댑터, mapper, 도메인 값 타입 | 여러 Feature가 공유하는 전역 인프라 |
| `Infra/` | `RemoteStore`, `SpringRemoteStore`, `TokenManager`, `DeviceIdentity`, config, app delegate처럼 여러 Feature가 공유하는 외부 효과 | 특정 화면만 아는 비즈니스 절차 |
| `Models/` | `AppState`, DTO, 전환 중 남은 공용 값 타입 | 네트워크, 파일, 오디오, 알림 호출 |
| `SignalProcessing/` | IMU 입력을 분석해 결과를 만드는 알고리즘 | UI 상태, 서버 저장 |
| `Analytics/` | 이벤트 이름, 속성 스키마, provider fan-out | 화면별 비즈니스 상태 |
| `DesignSystem/` | 색, 폰트, 간격, 그림자, 공통 modifier | 특정 도메인의 조건문 |
| `Views/` | 아직 Feature로 옮기지 않은 레거시 화면과 작은 공유 UI | 새 Feature의 기본 위치 |

## Feature Store 기준 패턴

Feature 상태는 Store가 소유한다. Store는 화면당 하나가 아니라 기능당 하나다.

```swift
@Observable
@MainActor
final class RecordsStore {
    private let repository: MealSessionRepository
    private let calendar: Calendar

    private(set) var monthSessions: [MealSessionRecord] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var displayedMonth: Date
    var selectedDate: Date?

    init(
        repository: MealSessionRepository,
        calendar: Calendar = mealCalendarCalendar,
        initialMonth: Date = .now
    ) {
        self.repository = repository
        self.calendar = calendar
        self.displayedMonth = calendar.startOfMonth(for: initialMonth)
    }
}
```

Store 규칙은 아래와 같다.

- `@Observable`, `@MainActor`, `final class`를 기본으로 쓴다.
- 외부에서 직접 바꾸면 안 되는 상태는 `private(set)`으로 둔다.
- Repository, Service, Calendar, Clock, callback은 initializer로 주입한다.
- Store는 SwiftUI `View`, `Color`, `Font`를 소유하지 않는다.
- Store는 HTTP, JSON decoding, Keychain, UserDefaults, CoreMotion, AVAudioSession을 직접 다루지 않는다.
- 수동 락(`NSLock`, `withLock`)을 추가하지 않는다. Store 상태는 MainActor 격리로 보호한다.
- `await` 경계의 순서 문제는 generation/latest-wins로 푼다.

## View 기준

View는 Store 상태를 읽고 action을 호출한다. View는 외부 효과를 직접 수행하지 않는다.

```swift
// Do
Button("불러오기") {
    Task { await store.loadInitial() }
}

// Don't
Button("불러오기") {
    Task {
        let rows = try? await state.remoteStore.fetchChewingSessions(
            deviceId: DeviceIdentity.shared,
            since: since,
            until: until
        )
    }
}
```

View에서 금지하는 직접 접근은 아래와 같다.

- `RemoteStore`, `SpringRemoteStore`, `SpringAuthClient`
- `DeviceIdentity.shared`
- `TokenManager`
- `UserDefaults`
- `UNUserNotificationCenter`
- `CMHeadphoneMotionManager`
- `AVAudioSession`

기존 레거시 View에 남은 접근은 새 기능에서 따라 하지 않는다. 리팩터 PR에서 해당 Feature만 좁게 이동한다.

## AppState 경계

`AppState`는 모든 도메인 로직을 담는 god object가 아니다. 앱 조립, 전역 세션 상태, 화면 전환에 필요한 얇은 facade로 유지한다.

AppState에 넣을 수 있는 것:

- 앱 전체 로그인/온보딩 gate
- 앱 시작 시 Feature Store를 조립하는 의존성 연결
- 전역 sheet/alert처럼 Feature 간 조정이 필요한 얇은 상태
- push/deeplink처럼 앱 진입 이벤트를 Feature Store로 라우팅하는 코드

AppState에 넣지 않는 것:

- 새 Feature의 서버 조회/저장 절차
- 측정, 보상, 친구, 기록 같은 도메인 상태 전이
- 외부 효과 구현체 직접 호출
- DTO 필터링, domain mapping, 알고리즘 판단

파일 길이는 절대 규칙이 아니라 냄새 감지 기준이다. `AppState`가 300줄을 넘으면 역할을 점검하고, 600줄을 넘는 상태에서 새 도메인 로직을 추가하지 않는다.

## Repository와 Adapter

서버와 외부 시스템은 포트와 어댑터로 나눈다.

```swift
protocol HomeRepository {
    func fetchHome() async throws -> HomeStateDTO
}

struct RemoteStoreHomeRepository: HomeRepository {
    private let remoteStore: RemoteStore

    func fetchHome() async throws -> HomeStateDTO {
        try await remoteStore.fetchHome(deviceId: DeviceIdentity.shared)
    }
}
```

규칙은 아래와 같다.

- Store는 Feature 포트 프로토콜에 의존한다.
- 어댑터는 `RemoteStore`, `DeviceIdentity`, `TokenManager`, 시스템 framework를 감싼다.
- Feature 전용 어댑터는 `Features/<Feature>/`에 둔다.
- 여러 Feature가 공유하는 기반 어댑터는 `Infra/`에 둔다.
- 테스트는 fake repository/service를 주입한다. 실서버, Keychain, 전역 UserDefaults에 의존하지 않는다.

## DTO와 도메인 모델

DTO는 서버 계약이고, 도메인 모델은 앱이 쓰는 언어다.

- 서버 응답 DTO는 `Models/DTO/`에 둔다.
- Feature 화면이 의미 있는 앱 모델을 필요로 하면 `Features/<Feature>/`에 도메인 모델과 mapper를 둔다.
- `ReportCardModel.from(dto) != nil` 같은 판정은 mapper나 도메인 규칙 한 곳에 모은다.
- DTO를 그대로 노출하는 기존 Feature는 한 번에 전부 바꾸지 않는다. 해당 PR의 범위 안에서만 이관한다.

## 상태와 비동기 규칙

한 상태는 한 곳이 소유한다.

```swift
// Don't
func buyItem(_ item: ShopItem) {
    points -= item.price
}

func applyHome(_ home: HomeStateDTO) {
    points = home.points
}

// Do
func buyItem(_ item: ShopItem) async throws {
    let updated = try await repository.purchase(item.id)
    apply(updated)
}
```

한 도메인의 변경이 다른 도메인을 push로 갱신하지 않는다.

```swift
// Don't
func deleteAllSessions() async {
    try? await repository.deleteAll()
    await homeStore.refresh()
}

// Do
func deleteAllSessions() async throws {
    try await repository.deleteAll()
    monthSessions = []
}
```

비동기 재요청은 latest-wins를 지킨다.

```swift
func loadMonth() async {
    loadGeneration &+= 1
    let generation = loadGeneration

    do {
        let rows = try await repository.fetchSessions(month: displayedMonth)
        guard generation == loadGeneration else { return }
        monthSessions = rows
        errorMessage = nil
    } catch {
        guard generation == loadGeneration else { return }
        errorMessage = "기록을 불러오지 못했어요."
    }
}
```

상태를 바꾸는 삭제/저장 액션은 진행 중 조회를 무효화한다. 삭제는 repository 성공 뒤에만 로컬 목록을 바꾼다.

## 에러와 의도

실패는 정상 상태와 구분되어야 한다.

- `try?`로 실패를 빈 목록이나 기본값으로 바꾸지 않는다.
- 사용자가 볼 수 있는 실패는 `errorMessage`, 실패 상태, 재시도 상태로 드러낸다.
- 인증 만료, 오프라인, 서버 오류는 가능한 한 구분한다.
- 콜드스타트 중 들어온 deeplink, notification action, invite code는 버리지 말고 준비 후 처리한다.

## 타입 설계

불가능한 상태는 타입으로 막는다.

```swift
// Don't
var isMeasuring = false
var isPaused = false
var isUploading = false

// Do
enum MealSessionPhase: Equatable {
    case idle
    case measuring(startedAt: Date)
    case paused(startedAt: Date)
    case analyzing
}
```

Swift API는 사용 지점에서 읽히는 이름을 우선한다. 축약보다 명확성을 고른다.

```swift
// Do
func moveMonth(delta: Int) async
func deleteSession(_ session: MealSessionRecord) async

// Don't
func mv(_ d: Int) async
func del(_ x: MealSessionRecord) async
```

## 파일 크기와 분리

큰 파일은 먼저 책임을 나눈다. extension 파일은 파일 길이만 줄일 뿐 상태 소유를 분리하지 못한다.

- Store가 여러 외부 서비스를 조율하면 service seam을 만든다.
- 같은 타입의 렌더링 helper가 길면 `Type+Rendering.swift`로 나눌 수 있다.
- 도메인 상태가 섞인 거대 타입은 extension이 아니라 별도 Store/Coordinator/Repository로 추출한다.
- 공통 추상화(`BaseStore`, `LoadableState`, `UseCase`)는 반복이 2~3개 Feature에서 확인된 뒤 도입한다.

## 테스트 기준

새 Store나 Repository 경계에는 fake 기반 테스트를 둔다.

- Store 테스트는 fake repository/service, 고정 Calendar/Clock을 주입한다.
- 실서버, Keychain, 전역 UserDefaults, 실제 AirPods, 실제 알림 권한에 의존하지 않는다.
- async race가 있는 기능은 latest-wins나 generation 무효화 테스트를 둔다.
- 실기기에서만 검증 가능한 항목은 PR 본문에 manual checklist로 남긴다.

## 외부 Swift 레포에서 가져온 기준

아래 기준은 그대로 가져오는 프레임워크 선택이 아니라, ChewChewIOS에 맞게 낮은 비용으로 적용할 원칙이다.

| 참고한 곳 | 공통점 | ChewChewIOS 적용 |
| -- | -- | -- |
| [Kickstarter iOS](https://github.com/kickstarter/ios-oss) | side effect를 UI에서 분리하고, 입력과 출력 흐름을 테스트 가능하게 만든다. | View는 Store action만 호출하고, Store는 repository/service를 주입받는다. |
| [Point-Free TCA](https://github.com/pointfreeco/swift-composable-architecture) / [isowords](https://github.com/pointfreeco/isowords) | state, action, dependency를 명시해 기능 단위로 테스트한다. | TCA를 도입하지 않고도 Feature Store, 명시적 action, fake dependency 원칙만 가져온다. |
| [Firefox iOS](https://github.com/mozilla-mobile/firefox-ios/wiki/Development-homepage) | 기여자가 일관되게 작업하도록 개발 가이드, SwiftUI/Concurrency/Architecture 문서를 나눈다. | README, architecture, review, workflow 문서 역할을 분리한다. |
| [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) | 사용 지점의 명확성을 최우선으로 둔다. | Store action과 Repository 메서드는 호출부에서 의도가 읽히게 이름 짓는다. |
| [Apple Observation](https://developer.apple.com/videos/play/wwdc2023/10149/) | SwiftUI 모델은 Observation 기반으로 단순화할 수 있다. | Feature Store는 `@Observable @MainActor`를 기본으로 둔다. |
| [Tuist 기반 모듈화 사례](https://engineering.backmarket.com/back-market-x-tuist-part-iii-how-we-enforce-our-modularization-strategy-with-tuist-1c82fd5115a9) | 프로젝트 구조를 선언적으로 유지하고 경계를 명확히 한다. | 지금은 폴더 경계로 시작하고, 빌드 타깃 분리는 필요가 커질 때 별도 이슈로 진행한다. |

## 새 코드 작성 체크리스트

- [ ] 새 기능은 `Features/<Feature>/`에서 시작했다.
- [ ] 상태 소유자는 하나다.
- [ ] Store는 `@Observable @MainActor final class`다.
- [ ] View는 Store state/action만 사용한다.
- [ ] 외부 효과는 Repository/Service/Adapter 뒤로 이동했다.
- [ ] `AppState`에 새 도메인 절차를 추가하지 않았다.
- [ ] 실패를 삼키지 않고 상태로 드러냈다.
- [ ] async 재요청 race를 generation/latest-wins로 다뤘다.
- [ ] DTO/domain mapping 위치가 명확하다.
- [ ] fake 기반 테스트가 있다.
- [ ] dead code를 남기지 않았다.
