---
description: 현재 작업을 빌드→리뷰→커밋→push→PR까지 보낸다 (머지는 하지 않음)
allowed-tools: Bash(xcodegen:*), Bash(xcodebuild:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git checkout:*), Bash(gh:*)
---

현재 브랜치: !`git branch --show-current`
커밋 대상 diff: !`git log main..HEAD --oneline`
변경 파일: !`git status --short`

현재 브랜치 작업을 PR까지 보낸다. `docs/workflow.md`의 3~7단계를 따른다. **머지는 하지 않는다 — 사용자가 본인 검토 후 직접 머지한다.**

0. 현재 브랜치가 `main`이면 중단한다. main에서는 커밋·push하지 않는다.
1. `xcodegen generate`로 프로젝트를 재생성하고 시뮬레이터 무서명 빌드가 그린인지 확인한다: `xcodebuild -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`. 가능하면 `xcodebuild test -scheme ChewChewIOS -destination 'platform=iOS Simulator,name=iPhone 16'`까지 돌린다. 실패하면 멈추고 원인을 보고한다. **코드 서명·실기기 빌드·아카이브는 사용자 몫이다(무료 Personal Team 제약).**
2. **별도 리뷰 패스**를 받는다(`code-reviewer` 에이전트). 이 에이전트가 없는 환경이면 일반 Task 서브에이전트를 신선한 컨텍스트로 띄워 리뷰한다. 자기 승인 금지. P1 지적은 반영 후 다시 검증한다.
3. 변경을 `type(ODO-NN): 요약`으로 커밋한다(한 커밋에 한 가지 목적). 규칙은 `.github/COMMIT_CONVENTION.md`.
4. push하고 `.github/PULL_REQUEST_TEMPLATE.md`로 PR을 연다. 제목은 `type(ODO-NN): ...`. 본문은 두괄식·Why→What→How·평서문 헤더·이모지 금지(`docs/workflow.md` 글쓰기 규칙). PR base는 스택 부모 브랜치 기준이다(기본 `main`). 스택 위면 `gh pr create --base <부모브랜치>`로 부모를 base로 지정한다.
5. Linear 이슈에 완료 코멘트를 1회 남긴다. 상태는 Linear에만 적는다. Linear MCP가 없으면 이 단계는 건너뛰고 사용자에게 위임한다.
6. **PR 링크를 보고하고 멈춘다.** 머지·서명·실기기 빌드는 사용자 몫이다. 머지 후 브랜치 정리도 사용자 몫이다.
