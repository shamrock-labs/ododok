# ododok_ui 작업 규칙

SwiftUI 기반 오도독 iOS 앱. AirPods IMU 신호를 신호처리(DSP)로 분석해 저작 리듬을 시각화하고, 세션·프로필·통계를 백엔드와 동기화한다. 설계의 정본은 Obsidian `Projects/ododok/`, 작업 상태의 정본은 Linear다. 이 파일은 코드를 짤 때 매번 지킬 규칙만 둔다.

## 빌드·테스트

- 프로젝트 생성: `xcodegen generate` (`project.yml` → `ChewChewIOS.xcodeproj`). 빌드·테스트 전에 항상 먼저 실행한다.
- 시뮬레이터 빌드(무서명): `xcodebuild -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
- 테스트: `xcodebuild test -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16'` (유닛 `ChewChewIOSTests` + UI `ChewChewIOSUITests`).
- **에이전트는 시뮬레이터 무서명 빌드까지만 한다.** 코드 서명·실기기 빌드·아카이브는 사용자(보형)가 Xcode에서 직접 한다. 무료 Personal Team 제약 때문이다.

## 코드 구조

- SwiftUI 앱. 화면은 SwiftUI View, 상태는 `@Observable` `AppState`(`ChewChewIOS/Models/`)로 모은다.
- 백엔드 접근은 **포트&어댑터**다. 포트는 `RemoteStore` 프로토콜(`ChewChewIOS/Services/RemoteStore.swift`), 어댑터는 `InsForgeRemoteStore`·`SpringRemoteStore`·`NoopRemoteStore`다. 화면·상태는 프로토콜에만 의존하고 구현은 주입으로 갈아끼운다.
- 어댑터 선택은 `ChewChewIOS/ChewChewIOSApp.swift`의 `makeRemoteStore()` 한 곳에서만 한다. 기본은 Spring(`AppEnvironment.backendURL`), 테스트(XCTest/`-useNoopRemote`)는 Noop, `-useInsForge`는 레거시 InsForge.
- 환경(바라보는 백엔드)은 **config 주입**으로 결정한다: `AppEnvironment.backendURL` ← Info.plist `ODODOK_BACKEND_URL` ← xcconfig(`Config/Env.Dev.xcconfig` Debug / `Config/Env.Prod.xcconfig` Release). 환경 분기를 코드에 하드코딩하지 않는다.
- 번들 ID는 환경별로 쪼개지 않는다(무료 Personal Team은 앱당 번들 ID 1개 제약). 환경 분리는 백엔드 URL로만 한다.
- 테스트 런치 인자(`-useNoopRemote`/`-useInsForge`)는 환경 config와 **직교한 오버라이드**다. 환경 분리(dev/prod)와 섞지 않는다.
- 신호처리(DSP) 카운터는 `ChewChewIOS/ML/ChewCounter.swift`(actor)다. ML 추론은 폐기됐다.

## 커밋·브랜치·PR

- 커밋: `type(ODO-NN): 요약` (type = feat/fix/refactor/docs/test/chore). 한 커밋에 한 가지 목적만. 상세는 `.github/COMMIT_CONVENTION.md`.
- 브랜치: `type/odo-NN-짧은-설명` (type + Linear 키 + 설명, 소문자, 하이픈).
- PR: `.github/PULL_REQUEST_TEMPLATE.md`를 사용한다. 제목은 Linear 키로 시작한다. 머지는 사용자가 본인 검토 후 직접 한다.

## Linear (작업 상태 정본)

매번 MCP로 조회하지 않도록 ID를 박아둔다. Linear MCP 호출 시 아래 값을 바로 쓴다.

- 팀: `Engineering` (key `ODO`, id `bd976e28-3afe-4908-86cd-66764267807c`)
- 프로젝트: `Spring Boot 백엔드 마이그레이션` (id `c7a821fa-60e3-4552-ac47-45249f6971bd`)
- 이니셔티브: `오도독 V1 출시` (id `211e6297-002a-43a8-82d4-dcf8c3e0ba4c`)
- 상태 흐름: Backlog → Todo → In Progress → In Review → Done

라벨 id:

- 트랙: `track: core-migration` `4711cb61-5b6e-44de-ae2c-ba1f6ccdce04` · `track: product-account` `a569b514-2529-484f-8038-82c4e7bb4459`
- 영역(area): `backend` `0b2371e3-12aa-48ea-aa14-a45780b2aee8` · `infra` `c5394f9d-534a-4fe2-a8f6-37f0addb3ba0` · `ios` `4f5aa840-87fc-491a-b4e1-ca7ad2deac62` · `ml` `6e0546d1-ad08-42bd-8a78-d141ba24639a` · `design` `485729de-2920-4296-a784-4e2abc81db7e`
- 유형(type): `chore` `a85cb9ab-89f8-476b-84b6-f2bf9c919b09` · `research` `b05cf2f4-64c4-450f-8b0f-0c67381969fc`
- 기타: `Feature` `c1acfbd2-f4a4-4cfb-a1ee-2f16d253a2b5` · `Improvement` `ba70df5f-c6c5-456e-a653-a9fbcf22ee46` · `Bug` `07e5dcd5-e733-479a-a1d7-511f73d0f52e`

연동: 브랜치 이름에 `odo-NN`이 있으면 Linear가 이슈에 자동 연결하고, PR 머지 시 이슈를 자동으로 Done으로 옮긴다. 이슈 시작 시 In Progress로 바꾸고, 완료 시 Linear 코멘트를 1회 남긴다. 진행/완료 상태는 Linear에만 적는다(코드 주석·메모리에 미러링 금지).

## 글쓰기 (PR·Linear·문서 공통)

두괄식, 평서문 헤더, 이모지 금지. 상세 규칙은 `docs/workflow.md`의 "글쓰기 규칙"을 따른다.

## 작업 상태·세션 하이진

- 작업 상태(진행/완료)는 Linear에만 기록한다. 메모리·Obsidian·코드 주석에 상태를 미러링하지 않는다(중복 = 부채).
- 브랜치는 push해서 가시화한다(로컬 방치 금지).
- 병렬 에이전트는 목적당 1개로 제한한다.
- 자기 코드는 같은 맥락에서 자기가 승인하지 않는다. 리뷰는 별도 패스로 받는다.

## 슬래시 커맨드

상세는 `.claude/commands/`를 본다. 여기엔 이름과 한 줄 요약만 둔다.

- `/issue <ODO-NN> [type]` — Linear 이슈 하나를 시작한다(조회 → In Progress → 브랜치 생성 → 짧은 계획).
- `/commit [--split]` — 변경을 커밋 컨벤션으로 커밋한다(push·PR 안 함). `--split`은 의미 단위 분할.
- `/review [부모브랜치]` — 현재 브랜치 diff를 컨벤션 기준으로 적대적 리뷰한다.
- `/ship` — 테스트(시뮬레이터 빌드) → 리뷰 → 커밋 → push → PR까지 보낸다(머지 안 함).
