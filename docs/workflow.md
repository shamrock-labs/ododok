# 개발 워크플로

이 문서는 이슈 하나를 시작해서 PR까지 가는 표준 절차와, PR·Linear·문서 글쓰기 규칙을 정의한다.
상태의 정본은 Linear, 설계의 정본은 Obsidian `Projects/ododok/`다. 이 규칙은 그 둘을 코드 작업에 연결한다.

## 이슈 한 개 처리 순서

1. Linear 이슈를 In Progress로 바꾼다.
2. 브랜치를 만든다: `type/odo-NN-짧은-설명` (main 또는 직전 스택 PR 브랜치를 base로).
3. 작업한 뒤 `tuist generate --no-open`으로 프로젝트를 재생성하고, 시뮬레이터 무서명 빌드와 테스트가 그린인지 확인한다.
   - 빌드: `xcodebuild -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
   - 테스트: `xcodebuild test -workspace ChewChewIOS.xcworkspace -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16'`
   - 코드 서명·실기기 빌드·아카이브는 사용자가 Xcode에서 직접 한다(무료 Personal Team 제약).
4. 별도 리뷰 패스(다른 에이전트 또는 사람)로 검증한다. 자기 승인은 하지 않는다.
5. 커밋한다: `type(ODO-NN): 요약`. 한 커밋에 한 가지 목적만.
6. push한 뒤 PR을 만든다(템플릿 사용). 제목은 Linear 키로 시작한다.
7. Linear에 진행/완료 코멘트를 1회 남긴다. 상태는 Linear에만 적는다.
8. 머지는 사용자가 본인 검토 후 직접 한다. 머지 후 로컬 브랜치 정리도 사용자 몫이다.

배포 운영은 `docs/cd-setup.md`를 따른다. main 머지는 TestFlight 배포를 자동으로 트리거하고, App Store 제출은 출시 버전 태그(`vX.Y.Z`)로 시작한다.

## 상태 SSOT (중복 = 부채)

- "지금 무슨 작업이 어디까지 됐나"는 Linear에만 적는다.
- 메모리·Obsidian·코드 주석에는 설계·취향·다음 진입점 포인터만 둔다. 상태를 복제하지 않는다.
- 같은 사실은 한 곳이 원본이고 나머지는 링크다.

## 글쓰기 규칙 (PR·Linear·기획·문서 공통)

읽는 사람은 작업 히스토리를 모른다고 전제하고 쓴다.

- 두괄식: 첫 줄이 "무엇을 왜 하는가"의 한 문장 요약이다. 근거와 과정은 그 뒤에 둔다.
- 구조는 Why → What → How: 배경(왜 열렸나) → 변경 내용(무엇을) → 확인 방법(어떻게 검증하나).
- 평서문 선언형 헤더를 쓴다. "왜 바뀌었나" 같은 의문형 제목은 쓰지 않는다("배경", "변경 근거"로).
- 이모지·체크마크 장식을 쓰지 않는다. 텍스트로 쓴다.
- 한 항목에 한 가지 목적만 담고, 섹션 사이는 빈 줄로 띄우며, 항목은 완전한 문장으로 쓴다.
- 리뷰어가 꼭 볼 부분과 검증할 부분을 명시한다. 사소한 변경은 한 줄로 표시해 리뷰 시간을 아낀다.

리뷰 우선순위 표기는 PR 템플릿과 동일하게 P1(꼭 반영) / P2(적극 고려) / P3(사소 의견)를 쓴다.
