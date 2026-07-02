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
│   ├── AppState.swift         # @Observable 글로벌 상태
│   ├── ShopItem.swift         # 의상/도토리팩 정적 데이터
│   └── MoodStatus.swift       # 4표정 분기 + 피드백 라인
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
