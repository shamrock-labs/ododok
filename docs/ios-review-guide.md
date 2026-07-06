# iOS 코드 리뷰 가이드 (ChewChewIOS)

PR·diff를 리뷰할 때 쓰는 상세 루브릭. `CLAUDE.md`/`README`는 "코드 작성 기준"(항상 로드, 간결)이고, 이 문서는 "리뷰 절차"(호출 시 참조, 상세)다. 어떤 AI로 리뷰하든 이 파일을 붙여넣거나 링크해 기준을 맞춘다.

리뷰는 **작성과 분리된 패스**다 — 자기 코드를 같은 맥락에서 자기가 승인하지 않는다. 결과는 P1(꼭 반영) / P2(적극 고려) / P3(사소)로 등급을 매기고 file:line 근거를 단다.

## 0. 리뷰 프로세스 (먼저 지킬 것)

- **미커밋 변경이 있으면 워킹트리를 본다. `git grep HEAD`(커밋된 트리)로만 보면 실제 변경을 놓친다.** `git status`로 M/??/RM을 먼저 확인하고, 파일은 워킹트리 기준으로 읽는다.
- **빌드·테스트는 사용자가 다른 환경에서 돌린다. 리뷰어는 정적 분석만.** 요청 없이는 `tuist generate`·`xcodebuild`를 돌리지 않는다.
- 리뷰는 시뮬레이터 무서명 빌드가 통과한다는 전제. 실기기 서명·아카이브는 CD/사용자 담당.
- SourceKit "Cannot find type …"이 뜨면 프로젝트 미생성 상태의 단일 파일 분석 false-positive일 수 있다(단일 모듈). 실제 판정은 빌드 결과로.

## 1. Store 계층 (v1.1 리팩터의 코드 정본은 RecordsStore)

- `@Observable` + `@MainActor` + `final class`. ViewModel 아님(화면당 하나가 아니라 기능당 하나).
- View가 직접 쓰면 안 되는 상태는 `private(set)`.
- 의존성(Repository·Service·Calendar·콜백)은 initializer로 주입. 전역 싱글턴·실서버·실시계 직접 참조 금지.
- Store는 SwiftUI `View`/`Color`/`Font`, HTTP·JSON 디코딩, Keychain·UserDefaults 직접 접근을 소유하지 않는다.
- View는 Store 상태만 읽고 action만 호출. `RemoteStore`·`SpringAuthClient`·`DeviceIdentity`·`UserDefaults` 직접 접근이 View에 남아 있으면 P1.

## 2. 상태 소유와 흐름

- **단일 소유자**: 한 상태를 두 곳이 쓰면(예: `points`를 서버 응답과 로컬 구매가 둘 다) P1. "이 값 누가 바꾸지?"의 답이 하나여야 한다.
- **밀지 말고 당겨오게(pull > push)**: 한 도메인의 변경이 다른 도메인을 갱신하러 가면 결합. 각 화면이 자기 데이터를 진입 시 당긴다.
- **서버가 정본이면 클라는 재계산하지 않는다**(ODO-54). 서버 값은 반영만.
- 판정 규칙(예: "리포트 가능한가")은 한 곳에만. 여러 곳에 복붙되면(버그 F 패턴) P1~P2.

## 3. 동시성

- Store는 `@MainActor`로 격리. `NSLock`·`withLock` 같은 수동 락 추가 금지(격리와 중복).
- **actor 격리 함정**: `@MainActor` 메서드를 `@MainActor` 아닌(nonisolated) 컨텍스트에서 동기 호출하면 컴파일 에러. 메서드가 main-actor 메서드를 부르면 그 메서드도 `@MainActor`여야 한다.
- **비동기 재요청엔 latest-wins**: 같은 async 조회를 다시 던지는 액션(월 이동 등)은 generation 토큰으로 마지막 요청만 반영. `@MainActor`는 await 경계의 인터리빙을 막지 못한다 — 늦게 온 이전 응답이 최신 상태를 덮을 수 있다.
- 상태를 바꾸는 액션(삭제 등)은 진행 중 조회를 무효화(generation bump)해 되살아남 방지.

## 4. 에러와 의도

- **실패를 삼키지 않는다**: `try?`로 조용히 빈 결과를 만들면 오프라인이 "데이터 없음"과 구분되지 않는다. 실패는 `errorMessage`/실패 상태로 드러낸다.
- **의도 유실 금지**: 준비 전(콜드스타트 등) 도착한 사용자 동작(딥링크·알림 탭·초대 코드)은 무시하지 말고 큐잉했다가 준비 시 처리.
- 삭제·저장은 **성공한 뒤에만** 로컬 상태를 바꾼다(실패 시 기존 유지).

## 5. 경계와 배치

- **도메인별 배치**: 한 기능의 Store·View·포트를 `Features/<Feature>/`에 co-locate. 공유 인프라(RemoteStore 포트·TokenManager·DeviceIdentity·config)만 `Infra/`. Feature 전용 어댑터를 `Infra/`에 두면 P2.
- **DTO ↔ 도메인 모델**: DTO는 서버 계약이라 `Models/DTO/`(공유)에 도메인별로. Feature는 매퍼로 도메인 모델만 받는다. DTO를 한 파일에 다 몰거나 Feature가 DTO를 그대로 노출하면 P2.
- **얇은 어댑터·god-object 금지**: 델리게이트/어댑터가 "무엇을 할지"를 결정하고 여러 도메인 메서드를 알면(라우팅 허브) P2. raw 이벤트만 전달하고 결정은 소유자 한 곳으로. `AppState`에 새 도메인 절차가 쌓이면 P1~P2.
- **불가능한 상태를 타입으로**: Bool 여러 개로 상태를 표현하면(측정중+일시정지+업로드중 조합) enum(`MealSessionPhase` 등)으로. 

## 6. 도구

- 이 PR이 만진 파일에 새 `swiftlint` 경고가 없어야 한다(`force_unwrapping`·`file_length`·`type_body_length` 등). `.swiftlint.yml` 기준.
- 각 PR은 자기 범위의 Store·View 변경만. 리팩터와 버그 fix·UI 변경·서버 API 변경을 섞지 않는다.

## 등급 예시

- P1: View가 인프라 직접 접근 / 상태 이중 소유 / actor 격리 컴파일 오류 / 삭제-실패인데 로컬 비움 / 실패 삼킴.
- P2: 판정 복붙 / DTO god-file / 라우팅 허브 어댑터 / Feature 어댑터가 Infra에 / latest-wins 누락.
- P3: 매직 스트링 / 테스트 force-unwrap / 파일 길이 경고.

설계 정본: Obsidian `Projects/ododok/24 ios-domain-architecture-refactor.md`. 코드 작성 기준: `README`의 "코드 작성 원칙", `CLAUDE.md`.
