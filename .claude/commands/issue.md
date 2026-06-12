---
description: Linear 이슈 하나를 시작한다 (조회 → In Progress → 브랜치 생성)
argument-hint: <ODO-NN> [type]
allowed-tools: Bash(git fetch:*), Bash(git status:*), Bash(git checkout:*), Bash(git switch:*), Bash(git branch:*)
---

ODO 이슈 `$1`을 시작한다. 절차는 `docs/workflow.md`의 "이슈 한 개 처리 순서"를 따른다.

1. Linear에서 이슈 `$1`을 조회해 **배경·Tasks·Done-When을 3~5줄로 요약**한다. (Linear MCP가 없으면 사용자에게 이슈 내용을 요청한다.)
2. 이슈를 **In Progress**로 옮긴다. (Linear MCP가 없으면 이 단계는 건너뛰고 사용자에게 위임한다.)
3. 분기 전 `git fetch`로 최신 `main`을 기준으로 맞춘다. dirty worktree면 먼저 정리하거나 사용자에게 확인한다. 브랜치를 만든다: `<type>/odo-NN-짧은-설명`. type 기본값은 `feat`, `$2`로 지정 가능(feat/fix/refactor/docs/test/chore). 규칙은 `.github/COMMIT_CONVENTION.md`. base는 `main`(사용자가 스택 PR 브랜치를 지정하면 그것을 base로).
4. 어떻게 진행할지 **짧은 계획을 제시하고 멈춘다.** 코드 작성은 사용자가 확인한 뒤 시작한다.

상태는 Linear에만 적는다(메모리·주석에 진행상태 미러링 금지).
