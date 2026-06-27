# ODO-16 서명·푸시·E2E 런북

Apple Developer 등록 후 iOS 서명 + 서버 푸시를 실기기까지 연결하는 마무리 작업 체크리스트.
코드측(entitlements 활성화)은 `chore/odo-16-ios-signing-push-e2e`에 커밋됨(319dd6e). 아래는 실기기·콘솔·시크릿 수작업.

앱 번들 ID: `com.shamrock.ododok` (APNs topic = 이 값, 카카오 iOS 플랫폼 번들 ID도 동일)

## 0. 코드측 (완료)

- `project.yml` entitlements 블록 주석 해제 → Sign in with Apple + APNs `aps-environment`(development)
- `xcodegen generate` + 시뮬레이터 무서명 빌드 SUCCEEDED
- 서버 코드 변경 없음. APNs는 `application.yaml`이 env 주입식으로 이미 설계됨(`ApnsProperties`)

## 1. Apple Developer Portal

- App ID `com.shamrock.ododok`에 Capabilities 활성화: **Push Notifications**, **Sign in with Apple**
- Membership에서 **Team ID** 확인
- Keys → `+` → **Apple Push Notifications service (APNs)** 키 생성
  - **Key ID** 기록, `AuthKey_XXXXX.p8` 다운로드(다운로드 1회만 가능 — 분실 시 재발급)

## 2. Xcode 서명/빌드 (실기기, 본인이 진행)

- 워크트리 `ododok/.claude/worktrees/odo-16` 열기(또는 브랜치를 메인에 머지 후 진행)
- 빌드 전 항상 `xcodegen generate` (이미 1회 실행됨)
- Signing & Capabilities: **Team 선택**(자동 서명), Push Notifications / Sign in with Apple capability 표시 확인
- 실기기 빌드 → 동작 확인
- 아카이브(Release) 전: `aps-environment`를 **production**으로 변경(현재 development=실기기 dev 스모크용). TestFlight/App Store는 production APNs 사용
- Archive → TestFlight 업로드

## 3. 서버 배포 env (staging/prod) — 코드 변경 없음

| env | 값 |
|---|---|
| `ODODOK_APNS_ENABLED` | `true` |
| `ODODOK_APNS_TEAM_ID` | Apple Team ID |
| `ODODOK_APNS_KEY_ID` | .p8 Key ID |
| `ODODOK_APNS_BUNDLE_ID` | `com.shamrock.ododok` |
| `ODODOK_APNS_PRIVATE_KEY` | .p8 PEM 전체 내용 |

- `enabled=false`(기본)면 `LoggingApnsPushSender`(자격증명 없이 로그만). `true` + 위 값이면 실제 `Http2ApnsPushSender`로 전환
- 발송 스케줄러는 별도 토글: `ODODOK_PUSH_SCHEDULER_ENABLED=true`(식사 슬롯 시각 발송)

## 4. 카카오 콘솔 (ODO-55 후속)

- 카카오 디벨로퍼스 → 내 앱 → 플랫폼 → **iOS 등록**: 번들 ID `com.shamrock.ododok` + 커스텀 스킴 `kakao{네이티브앱키}`
  - 설치자 자동 수락(딥링크 `chewchew://invite?code=`)의 전제
- **마켓 URL**에 App Store 앱 주소 입력 → 미설치자가 앱스토어로 이동(미설치자 폴백)
- 코드 웹 폴백(`KakaoInviteSharer.Link.mobileWebUrl`)은 선택 — 이번엔 콘솔 설정만으로 처리하기로 함

## 5. 실기기 스모크 (e2e 체크리스트)

- [ ] 로그인(Apple/Google/Kakao) 통과 — entitlement 서명 검증
- [ ] 알림 권한 허용
- [ ] 토큰 등록: `POST /v1/me/push-tokens` 200, DB `push_tokens`에 본인 user row(environment sandbox/production)
- [ ] 끼니 설정 저장 → 서버가 슬롯 시각에 APNs 발송 → 실기기 푸시 수신
- [ ] 서버 미도달/오프라인 시 로컬 알림 폴백 동작(알림 끊김 없음) — `MealPushCoordinator.reconcileDelivery`
- [ ] 카카오 초대 링크: 미설치 기기에서 앱스토어로 이동

## 6. App Store 리뷰 노트 / 권한 문구 (초안)

- 권한 문구는 `Info.plist`에 이미 존재: `NSMotionUsageDescription`, `NSMicrophoneUsageDescription`. Push / Sign in with Apple은 별도 usage string 불필요
- 리뷰 노트 초안: "푸시 알림은 서버 발송 식사 리마인더이며, 네트워크/권한 불가 시 로컬 알림으로 폴백함. 로그인은 Apple/Google/Kakao 제공. 리뷰용 데모 계정: <ID/PW 기입>"
- 스크린샷 필요분: 로그인 화면, 식사 알림 설정, 리포트 허브 등 캡처

## Done When 매핑

- 서명/아카이브/TestFlight → §1, §2
- entitlement 실기기 통과 → §2, §5
- 토큰 등록 → 서버 발송 → 실기기 수신 e2e → §3, §5
- 로컬 폴백 끊김 없음 → §5
- 카카오 초대 미설치자 앱스토어 연결 → §4, §5
