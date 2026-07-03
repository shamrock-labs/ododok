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
├── Services/                  # 백엔드/오디오/알림/세션 등 외부 효과 어댑터
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
- `Services/`: 백엔드 클라이언트, 오디오, 알림, Keychain, Sentry처럼 외부 효과가 있는 어댑터를 둔다. 화면은 가능하면 프로토콜에 의존한다.
- `SignalProcessing/`: IMU 신호처리처럼 입력 데이터로 판단 결과를 만드는 알고리즘을 둔다. UI 상태나 서버 저장을 직접 알지 않는다.
- `Analytics/`: 이벤트 이름, 속성 스키마, provider fan-out을 둔다. 화면과 `AppState`는 이벤트 호출만 한다.
- `DesignSystem/`: 색, 폰트, 간격, 그림자, 공통 modifier를 둔다. 특정 화면의 비즈니스 조건을 넣지 않는다.

AI나 사람이 새 기능을 추가할 때는 아래 순서를 따른다.

1. 화면만 바뀌면 `Views/` 안에서 끝낸다.
2. 상태가 필요하면 `AppState`에 최소 상태만 추가한다.
3. 외부 효과가 있으면 `Services/`에 타입을 만들고 `AppState`는 호출만 한다.
4. 판단 로직이 테스트 가능하면 순수 함수나 `SignalProcessing/` 타입으로 분리한다.
5. 같은 코드가 두 화면 이상에서 필요해질 때만 공통 컴포넌트나 helper로 올린다.

## AppState 경계 규칙

`AppState`는 SwiftUI 화면이 관찰하는 앱 상태 facade다. 스프링으로 치면 Controller, Service, Session State를 전부 합친 클래스가 아니라, 화면에 필요한 상태를 들고 작은 coordinator/service를 호출하는 얇은 진입점에 가깝게 유지한다.

새 기능을 넣을 때는 아래 순서를 기본 규칙으로 삼는다.

- 화면 표시 상태, sheet/alert 플래그, 화면에서 직접 관찰해야 하는 값만 `AppState`에 둔다.
- 네트워크, 오디오, 알림, 파일, Sentry/Analytics처럼 외부 효과가 있는 로직은 `Services/` 또는 전용 어댑터로 뺀다.
- 식사 측정, 온보딩, 친구 초대처럼 여러 서비스를 묶는 절차는 `AppState`에 길게 쓰지 말고 작은 private method나 별도 coordinator로 분리한다.
- 알고리즘 판단은 `SignalProcessing/` 또는 순수 함수로 두고, `AppState`는 입력과 결과 연결만 맡는다.
- 서버가 정본인 정책값은 앱에 매직넘버로 박지 않는다. 앱은 서버 값을 주입받고, 범위 정규화·fallback 같은 안전 처리만 한다.

줄 수 기준은 절대 규칙이 아니라 냄새 감지용이다. 300줄을 넘으면 역할을 한 번 점검하고, 600줄을 넘는 새 기능은 별도 타입 분리를 먼저 고려한다. 1000줄 이상 파일에 새 도메인 로직을 바로 추가하지 않는다.

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
