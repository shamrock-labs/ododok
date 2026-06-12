---
description: 변경사항을 팀 커밋 컨벤션(type(ODO-NN))에 맞춰 커밋한다 (push·PR은 안 함)
argument-hint: [--split]
allowed-tools: Bash(git add:*), Bash(git commit:*), Bash(git status:*), Bash(git diff:*), Bash(git branch:*), Bash(xcodegen:*), Bash(xcodebuild:*)
---

현재 변경: !`git status --short`

변경을 `.github/COMMIT_CONVENTION.md` 형식으로 커밋한다. **push·PR은 하지 않는다** — 그건 `/ship`이다.

사용:

- `/commit` — 변경 전체를 하나의 컨벤션 커밋으로 작성.
- `/commit --split` — 변경을 의미 단위로 분할하고, 분할안을 사용자에게 컨펌받은 뒤 순서대로 커밋.

## 0. 브랜치 가드

현재 브랜치가 `main`이면 직접 커밋하지 말고, `type/odo-NN-짧은-설명` 작업 브랜치를 새로 따도록 안내하고 멈춘다(`.github/COMMIT_CONVENTION.md`).

## 절차 (/commit)

1. `git status`와 `git diff`(스테이징 포함)로 변경 내용을 파악한다.
2. 변경이 논리적으로 여러 단위라면 `--split`을 제안한다.
3. 관련 파일을 `git add`로 스테이징한다.
4. `type(ODO-NN): 요약` 형식으로 커밋한다. 한 커밋에 한 가지 목적만.

## --split (분할 커밋)

여러 작업이 섞인 변경을 의미 단위로 나눠 순차 커밋한다.

1. `git status`·`git diff`로 변경 전체를 파악한다.
2. 의미 단위(기능/수정/설정 등)로 그룹화하고, **각 커밋 시점에 빌드가 깨지지 않도록 순서**를 정한다:
   - **의존 순서**: 다른 코드가 참조하는 피의존 코드(프로토콜·모델·유틸·상수·확장)를 먼저, 이를 쓰는 코드를 나중에 커밋.
   - **빌드 안전성**: 각 커밋 시점에 정의되지 않은 심볼·끊긴 참조가 없도록. 신규 public 타입·API와 그 사용처는 같은 커밋에 묶는다.
   - **type 매핑**: 그룹마다 적절한 type(feat/fix/refactor/docs/test/chore)을 지정.
3. **분할안을 제시하고 컨펌을 받는다(승인 전 커밋 금지):**

   ```
   분할안 (총 N개 커밋)
   1. feat(ODO-NN): ...  ← 파일: A.swift, B.swift
   2. refactor(ODO-NN): ... ← 파일: C.swift
   순서 근거: 1이 추가하는 프로토콜을 2가 사용 → 1을 먼저 커밋
   ```

4. 승인되면 그룹별 `git add <files>` → `git commit`으로 순서대로 커밋한다. 파일 일부만 변경된 경우 `git add -p`로 hunk 단위 분할도 쓴다.
5. 가능하면 커밋 사이/후 `xcodegen generate` + 시뮬레이터 무서명 빌드로 각 커밋이 빌드를 깨지 않는지 확인한다: `xcodebuild -scheme ChewChewIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.

## 커밋 형식

```
type(ODO-NN): 작업 내용
```

- 스코프에 Linear 키 `ODO-NN`을 넣는다. 이슈가 없는 작업은 스코프를 생략할 수 있다.
- 작업 내용은 한국어 명령형/요약형으로 간결하게 쓴다.
- type: feat(기능) / fix(버그) / refactor(동작 동일 구조 개선) / docs(문서·템플릿) / test(테스트) / chore(설정·빌드·의존성). 상세는 `.github/COMMIT_CONVENTION.md`.

## 규칙

- `git push`는 사용자가 명시적으로 요청할 때만 한다(기본은 안 함).
- 커밋 메시지 끝에 `Co-Authored-By: Claude ...` 라인을 둔다(레포 기존 이력과 통일).

## 예시

- `feat(ODO-53): SpringRemoteStore 주입 스위치`
- `fix(ODO-61): IMU 볼륨 마운트 경로 수정`
- `chore(ODO-NN): xcodegen 설정 정리`
