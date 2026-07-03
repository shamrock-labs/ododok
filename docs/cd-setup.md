# CD 세팅 가이드 (TestFlight / App Store 자동 배포)

main에 머지하면 TestFlight로, `vX.Y.Z` 태그를 push하면 App Store 심사 제출까지 자동으로 간다. 이 문서는 그 파이프라인을 처음 켤 때 사람이 한 번 해야 하는 세팅을 정리한다. 코드(Fastfile·워크플로우)는 이미 레포에 있고, 아래 인증 자료만 채우면 동작한다.

## 파이프라인 요약

| 트리거 | 워크플로우 | 하는 일 |
|--------|-----------|---------|
| PR·main push | `ios-ci.yml` (기존) | 시뮬레이터 무서명 빌드 게이트 |
| main push | `ios-cd-testflight.yml` | Release 아카이브 → match 서명 → TestFlight 업로드 (빌드번호 = run number) |
| `vX.Y.Z` 태그 push | `ios-cd-release.yml` | Release 아카이브 → match 서명 → App Store 심사 제출 (버전 = 태그, 출시 버튼은 수동) |

서명은 fastlane match다. `Project.swift`가 Manual 서명 + `match AppStore ...` / `match Development ...` 프로파일 이름을 참조하므로, match가 만드는 프로파일 이름과 정확히 맞물린다.

## 전제조건

- 유료 Apple Developer Program 가입 (팀 `26SRR6SP9B`)
- App Store Connect에 앱 레코드 존재 (`com.shamrock.ododok`)
- 확장 2개(`com.shamrock.ododok.OdodokWidgets`, `com.shamrock.ododok.OdodokNotificationContent`)의 App ID가 Developer Portal에 등록돼 있을 것

## 1회 세팅 (사람이 직접)

### 1. App Store Connect API Key 발급

App Store Connect → Users and Access → Integrations → App Store Connect API → 팀 키 생성 (Access: App Manager 이상).

- **Issuer ID** (페이지 상단, UUID) → `ASC_ISSUER_ID`
- **Key ID** (발급한 키 행) → `ASC_KEY_ID`
- **.p8 파일** 다운로드 (한 번만 받을 수 있음) → base64로 인코딩해 `ASC_KEY_P8`

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # 클립보드에 복사됨
```

### 2. match 인증서 레포 생성 + 최초 실행

인증서·프로파일을 저장할 **프라이빗** git 레포를 하나 만든다 (예: `shamrock-labs/ododok-certs`). 비어 있어도 된다.

로컬(맥, Xcode 로그인된 상태)에서 최초 1회 실행해 인증서·프로파일을 생성·업로드한다. `ODODOK_BUNDLE_PREFIX` 등 빌드용 `Config/Secrets.xcconfig`가 채워져 있어야 한다.

```sh
bundle install

export MATCH_GIT_URL="https://github.com/shamrock-labs/ododok-certs.git"
export MATCH_PASSWORD="<인증서 암호화에 쓸 새 비밀번호 — 잊지 말 것>"

# Distribution(App Store) 인증서·프로파일
bundle exec fastlane match appstore

# Development 인증서·프로파일 (로컬 실기기 빌드용)
bundle exec fastlane match development
```

`Matchfile`에 앱+확장 3개 번들 ID가 등록돼 있어 한 번에 전부 만들어진다. 이때 만들어진 프로파일 이름이 `match AppStore com.shamrock.ododok` 형식이라 `Project.swift`와 정확히 일치한다.

주의: match가 새 Distribution 인증서를 만들면 기존에 로컬에서 쓰던 수동 인증서와 별개다. 팀에 이미 배포 인증서가 있으면 `match import`로 기존 것을 넣는 것도 가능하다.

### 3. GitHub Secrets 등록

레포 Settings → Secrets and variables → Actions → New repository secret. 아래 전부 등록한다.

| Secret | 값 |
|--------|-----|
| `ASC_KEY_ID` | ASC API Key ID |
| `ASC_ISSUER_ID` | ASC API Issuer ID |
| `ASC_KEY_P8` | `.p8` 파일을 base64 인코딩한 값 |
| `MATCH_PASSWORD` | 위 2단계에서 정한 인증서 암호화 비밀번호 |
| `MATCH_GIT_URL` | 인증서 레포 URL (예: `https://github.com/shamrock-labs/ododok-certs.git`) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | 인증서 레포 접근용. `echo -n "<github-user>:<PAT>" \| base64` (PAT는 certs 레포 read 권한) |
| `SECRETS_XCCONFIG_BASE64` | 실제 값이 채워진 `Config/Secrets.xcconfig`를 base64 인코딩. `base64 -i Config/Secrets.xcconfig \| pbcopy` |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | (선택) `ChewChewIOS/GoogleService-Info.plist`를 base64 인코딩. 없으면 Firebase 비활성으로 빌드됨 |

`SECRETS_XCCONFIG_BASE64`가 핵심이다. TestFlight/App Store 빌드는 CI 게이트와 달리 더미 키로는 안 되고, InsForge·OAuth·백엔드 URL 등 실제 값이 앱에 들어가야 한다.

### 4. Gemfile.lock 커밋 (권장)

CI 재현성을 위해 로컬에서 한 번 `bundle install` 한 뒤 생성되는 `Gemfile.lock`을 커밋한다.

## 배포 방법 (세팅 후 일상 운영)

- **TestFlight**: main에 머지하면 끝. 몇 분 뒤 App Store Connect → TestFlight에 새 빌드가 뜬다. 내부 테스터에게 자동 배포되고, 외부 테스트 그룹·심사는 콘솔에서 관리한다.
- **App Store 제출**:

  ```sh
  git tag v0.1.0
  git push origin v0.1.0
  ```

  태그의 버전이 앱 마케팅 버전이 된다. 워크플로우가 심사 제출까지 하고, 심사 통과 후 최종 '출시'는 App Store Connect에서 사람이 누른다.

## 트러블슈팅

- **`match`가 프로파일을 못 찾음**: 인증서 레포 접근 실패(`MATCH_GIT_BASIC_AUTHORIZATION`) 또는 아직 2단계 최초 실행을 안 한 경우. CI는 `readonly`라 프로파일을 만들지 않는다 — 반드시 로컬에서 먼저 생성해 둘 것.
- **서명 실패(프로파일 이름 불일치)**: `Project.swift`의 `PROVISIONING_PROFILE_SPECIFIER`와 match 프로파일 이름이 어긋난 경우. 번들 ID를 바꿨다면 양쪽을 함께 고친다.
- **빌드번호 중복 업로드 거부**: 같은 (버전, 빌드번호) 조합은 재업로드가 안 된다. 빌드번호는 GitHub run number라 재실행 시 올라간다. 실패한 실행을 그대로 재시도하기보다 새 커밋/새 실행으로 올린다.
- **Secrets.xcconfig 없음으로 tuist generate 실패**: `SECRETS_XCCONFIG_BASE64` 미등록. 등록 후 재실행.
- **entitlements(푸시·App Groups) 불일치**: match 프로파일이 앱 entitlements를 지원해야 한다. capability를 추가했다면 Developer Portal에서 App ID에 반영 후 `match`를 로컬에서 다시 실행(생성 모드)해 프로파일을 갱신한다.
