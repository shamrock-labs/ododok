# 씹기 감지 튜닝 기록

## 2026-06-28 — 실기기 최적값 (v1)

실기기에서 디버그 슬라이더로 직접 튜닝해 "가장 잘 잡히던" 파라미터. `ChewSensitivity` 기준.

### 최적 파라미터

| 파라미터 | 최적값 | 기본값(defaults) | 변화 | 역할 |
|---|---|---|---|---|
| 진폭 하한 `minPeakAmplitude` | 0.006 | 0.006 | = | 봉우리 노이즈 플로어 |
| 피크 간격 `minPeakGap` | 32 | 32 | = | 최소 봉우리 간격(샘플, ≈0.64s) |
| 머리움직임 허용 `headingMotionThreshold` | 0.12 | 0.12 | = | heading guard 임계(rad/s) |
| 저작 진폭 하한 `minimumRotationYStd` | 0.030 | 0.050 | ↓ | 약한 저작도 진입 |
| 진입 지속 `enterSampleCount` | 10 | 10 | = | 씹기 진입 지속(샘플) |
| 종료 지속 `exitSampleCount` | 90 | 90 | = | 씹기 종료 지속(샘플) |
| **rotY 우세도 하한** `minimumRotationYDominance` | **0.15** | 0.30 | **↓↓ (절반)** | 게이트 완화 |
| **jitter 우세도 하한** `minimumRotationYJitterBandDominance` | **0.15** | 0.40 | **↓↓** | 게이트 완화 |
| **accel/rotation 상한** `maximumAccelToRotation` | **0.050** | 0.025 | **↑↑ (2배)** | 게이트 완화 |
| 게이트 강제통과 `bypassChewingGate` | false | false | = | 진단용, 평소 OFF |

### 진단 결론 — 게이트가 과소카운트의 범인이었다

최적값이 **봉우리 검출 쪽(진폭·간격·heading)은 기본값 그대로**인데, **게이트(진동거부) 3조건은 전부 크게 완화**됐다. 이게 핵심 단서다:

- 봉우리는 원래 잘 생기고 있었다(봉우리 파라미터 안 바꿔도 됐으므로).
- **게이트가 실제 씹기를 "진동/비저작"으로 오판해 버리고 있었다.**
  - rotY 우세도 0.30 → 0.15
  - jitter 우세도 0.40 → 0.15
  - accel/rotation 상한 0.025 → 0.050

즉 원본의 게이트 임계값(저자 1인·단일 세션 튜닝, 원본 README가 과적합 경고)이 이 사용자/이 착용에는 너무 빡빡했다. 사양서 §6 "이식 후 임계값 재검증 필수" 경고가 현실화된 사례.

### Swift 반영용 (`ChewSensitivity.defaults` 후보)

```swift
static let defaults = ChewSensitivity(
    minPeakAmplitude: 0.006,
    minPeakGap: 32,
    headingMotionThreshold: 0.12,
    minimumRotationYStd: 0.030,
    enterSampleCount: 10,
    exitSampleCount: 90,
    minimumRotationYDominance: 0.15,
    minimumRotationYJitterBandDominance: 0.15,
    maximumAccelToRotation: 0.050,
    bypassChewingGate: false
)
```

### 주의 · 다음 검증

- 게이트를 완화한 만큼 **다리떨기·차량진동 오탐**이 늘 수 있다. 가만히 있을 때·걸을 때·다리 떨 때 카운트가 안 오르는지 재확인 필요.
- 단 빠른 다리떨기는 봉우리 검출의 low-pass(2.2Hz)가 1차로 막으므로, 우세도 완화가 곧장 오탐 폭증으로 이어지진 않는다. **저주파 가속 진동(차량·버스)**만 주의.
- 한 명·한 세션 기준이라 과적합 가능. 여러 식사·여러 사람으로 재검증 권장.
- rotY 우세도를 0.15까지 내려야 했다는 건, 저작이 좌우(rotY)축에 100% 실리진 않는다는 신호일 수 있다. 추후 **축 매핑**(어느 축에 저작이 가장 강하게 실리는지) 측정 가치 있음.
