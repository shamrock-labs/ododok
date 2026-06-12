---
description: 현재 브랜치 diff를 컨벤션 기준으로 적대적 리뷰한다
argument-hint: [부모브랜치]
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*)
---

리뷰 대상 diff: !`git diff main...HEAD --stat`

현재 브랜치를 부모 브랜치(기본 `main`, `$1`로 지정 가능) 대비 diff로 리뷰한다. 스택 위 브랜치면 그 부모 대비 diff를 본다. **작성과 분리된 리뷰 패스**다(자기 승인 금지).

`code-reviewer` 에이전트로 리뷰한다. 이 에이전트가 없는 환경이면 일반 Task 서브에이전트를 신선한 컨텍스트로 띄워 같은 기준으로 리뷰한다.

리뷰 기준·등급·보고 형식은 `code-reviewer` 에이전트 정의(`.claude/agents/code-reviewer.md`)를 따른다. 코드 구조 규칙은 `CLAUDE.md`의 "코드 구조"를 정본으로 본다. 결과는 **P1(꼭 반영) / P2(적극 고려) / P3(사소)**로 등급을 매겨 파일·라인 근거와 함께 보고한다.
