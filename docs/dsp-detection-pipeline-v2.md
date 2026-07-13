# DSP 감지 파이프라인 v2

## 목적

센서 입력, 씹기 활동 구간, 대표 peak 확정, 화면 pulse 전달의 책임을 분리한다. 세션 종료 직전 입력과 마지막 peak까지 통계에 포함하고, 화면 처리 지연이 씹기 횟수 누락으로 이어지지 않게 한다.

상태가 행마다 어떻게 바뀌는지는 [DSP Gate·Count 파이프라인 시각화](./dsp-gate-count-pipeline.html)에서 확인한다.

## 전체 흐름

```text
AirPods IMU sample
  -> MealSessionRuntimeStore input task chain
  -> ChewDetectionEngine
     -> ChewingActivityGate
     -> RepresentativePeakWindow
     -> confirmedChewCount
  -> ChewPulseDeliveryGate
  -> SwiftUI pulse
```

`MealSessionRuntimeStore`는 센서 입력의 순서를 보존한다. `ChewDetectionEngine`은 활동 구간과 대표 peak를 판단해 확정 횟수를 소유한다. `ChewPulseDeliveryGate`는 화면에 너무 촘촘한 pulse가 전달될 때 짧은 구간을 합치지만, DSP의 확정 횟수에는 관여하지 않는다.

## Gate와 count의 책임

### ChewingActivityGate

Gate는 현재 입력이 씹기 활동 구간 안에 있는지만 판단한다. 연속 10개 입력이 씹기 조건을 만족하면 열리고, 연속 30개 입력이 조건을 만족하지 않으면 닫힌다.

`isChewingGateOpen`은 확정된 씹기 횟수가 아니다. 이후 peak 후보를 검토해도 되는 구간인지 나타내는 상태다.

### RepresentativePeakWindow

Gate가 열린 동안 들어온 local peak를 대표 peak 후보로 모은다. peak 사이 간격이 최소 간격보다 짧으면 같은 씹기 동작에서 발생한 잔파동으로 보고, 더 큰 amplitude를 대표 후보로 남긴다.

후보 구간이 닫히면 `confirmChew`가 대표 peak 하나를 확정하고 `confirmedChewCount`를 한 번 증가시킨다.

## 세션 종료 계약

세션 종료는 다음 순서를 지킨다.

1. 새 센서 입력 수신을 중단한다.
2. `sampleProcessingTailTask`가 끝날 때까지 기다려 이미 받은 입력을 모두 처리한다.
3. `finishSession()`으로 아직 열려 있는 마지막 대표 peak를 확정한다.
4. `snapshot()`으로 최종 통계를 읽는다.

`finishSession()`은 여러 번 호출해도 결과가 한 번만 반영되는 idempotent 연산이다. 종료 후 들어온 입력은 무시한다. `snapshot()`은 상태를 바꾸지 않는 읽기 전용 연산이다.

이 순서로 세션 종료 직전 센서 데이터와 마지막 씹기 후보가 통계에서 빠지는 문제를 막는다.

## UI pulse 전달

확정된 DSP count와 도토리 pulse 애니메이션은 서로 다른 책임이다. `ChewPulseDeliveryGate`는 0.20초 안에 연속으로 도착한 화면 pulse를 합쳐 MainActor가 밀릴 때 애니메이션이 한꺼번에 재생되는 현상을 줄인다.

UI pulse를 합쳐도 `confirmedChewCount`와 세션 통계는 줄어들지 않는다. 화면은 감지 결과를 표현하고, DSP 엔진이 결과의 기준이 된다.

## 이름과 버전

- `ChewCounter`는 책임을 드러내도록 `ChewDetectionEngine`으로 바꾼다.
- `isChewing`은 count로 오해하지 않도록 `isChewingGateOpen`으로 바꾼다.
- `chewCount`는 확정값임을 드러내도록 `confirmedChewCount`로 바꾼다.
- DSP 모델 버전은 엔진이 `dsp-chewcounter-2`로 소유한다.

파일명 `ChewCounter.swift`는 이번 변경에서 유지한다. 타입과 호출 계약을 먼저 안정화하고 파일 이동은 별도 변경으로 다룬다.

## 변경 범위

- `ChewChewIOS/SignalProcessing/ChewCounter.swift`: 엔진, Gate, peak 이름과 세션 종료 계약을 정리한다.
- `ChewChewIOS/Features/MealSession/MealSessionRuntimeStore.swift`: 입력 task를 drain한 뒤 통계를 생성한다.
- `ChewChewIOS/Features/MealSession/ChewPulseDeliveryGate.swift`: UI pulse 합치기 규칙을 분리한다.
- 관련 화면과 DTO: 새 타입명과 모델 버전을 사용한다.
- 단위 테스트: 마지막 peak, 종료 멱등성, 종료 후 입력 거부, 입력 task drain을 검증한다.

## 검증

- DSP와 runtime 관련 타깃 테스트 16개가 통과한다.
- 무서명 iOS Simulator 빌드가 통과한다.
- 변경된 핵심 Swift 파일의 SwiftLint 위반이 0개다.
- `tuist generate --no-open`으로 새 파일이 Xcode 프로젝트에 포함된다.

Amplitude SDK의 기존 deprecation 경고는 이번 변경 범위 밖이며 빌드 실패와 관련이 없다.

## 트레이드오프

입력 task를 모두 기다리므로 종료 버튼을 누른 직후 아주 짧은 대기 시간이 생길 수 있다. 대신 이미 수신한 센서 데이터가 통계에서 누락되지 않는다.

UI pulse 합치기는 화면 표현을 안정시키지만 모든 확정 count마다 별도 애니메이션을 보장하지 않는다. 정확한 횟수는 DSP 통계를 기준으로 하고, 화면 pulse는 즉각적인 피드백으로만 사용한다.
