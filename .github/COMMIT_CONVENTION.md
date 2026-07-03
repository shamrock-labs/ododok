# Commit & Branch Convention

## 커밋 메시지

```text
type(ODO-NN): 변경 요약
```

예시:

```text
feat(ODO-53): SpringRemoteStore 주입 스위치
fix(ODO-NN): 옵셔널 언래핑 크래시 수정
test(ODO-NN): ChewCounter 피크 검출 단위 테스트 추가
docs(ODO-NN): 팀 컨벤션 문서 추가
chore(ODO-NN): xcodegen 설정 정리
```

### Type

- `feat`: 기능 추가
- `fix`: 버그 수정
- `test`: 테스트 추가/수정
- `docs`: 문서, 템플릿
- `chore`: 설정, 빌드, 의존성
- `refactor`: 동작 변경 없는 구조 개선

### Rule

- 한 커밋에는 한 가지 목적만 담는다.
- 스코프에 Linear 키 `ODO-NN`을 넣는다. 이슈가 없는 작업은 스코프를 생략할 수 있다.
- PR 제목도 `type(ODO-NN): 변경 요약` 형식으로 쓴다.

## 브랜치 이름

```text
type/odo-NN-짧은-설명
```

예시: `feat/odo-53-spring-store-switch`, `fix/odo-61-imu-volume`

### Rule

- type은 커밋 type과 동일한 집합(feat/fix/refactor/docs/test/chore)을 쓴다.
- Linear 키(`odo-NN`)를 포함한다. Linear가 이 키로 브랜치·PR을 이슈에 자동 연결한다.
- 소문자, 단어는 하이픈으로 구분, 설명은 50자 이내로 짧게 쓴다.
