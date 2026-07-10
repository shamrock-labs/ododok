# Amplitude 기본 사용자 흐름 추적 기준

이 문서는 앱 설치부터 로그인, 앱 이용, 로그아웃, 탈퇴, 재가입까지의 기본 사용자 흐름을 Amplitude에서 같은 기준으로 보기 위한 트래킹 기준이다. 아하 모먼트와 리텐션 행동은 아직 확정하지 않고, 나중에 기준이 정해졌을 때 최소 변경으로 퍼널과 리텐션 차트를 만들 수 있게 현재 이벤트와 식별자 기준을 정리한다.

## 식별자 기준

| 구간 | Amplitude user_id | Amplitude device_id | user property | 분석 기준 |
| -- | -- | -- | -- | -- |
| 설치, 앱 진입, 로그인 전 | 비어 있음 | Amplitude SDK 기본 device_id | 없음 | 익명 설치/기기 기준 전환 |
| 로그인 성공 이후 | 서버 `users.id` | Amplitude SDK 기본 device_id 유지 | `anonymous_device_id = DeviceIdentity.shared` | 계정 기준 앱 이용 |
| 로그아웃 이후 | 비어 있음 | Amplitude SDK 기본 device_id 유지 | 기존 profile property는 새 로그인 시 갱신 | 계정 세션 종료 |
| 탈퇴 이후 | 비어 있음 | Amplitude SDK 기본 device_id 유지 | 기존 profile property는 새 로그인 시 갱신 | 탈퇴 전 마지막 계정 이벤트 |
| 동일 소셜 계정 재가입 | 새 서버 `users.id` | Amplitude SDK 기본 device_id 유지 | 같은 `anonymous_device_id` 가능 | 새 계정 기준 재가입 |

분석에서 `device_id`는 Amplitude SDK의 익명 사용자 연결 기준으로만 본다. 서버의 `DeviceIdentity.shared`는 Amplitude `device_id`로 덮어쓰지 않고, 로그인 이후 `anonymous_device_id` user property로 저장한다. 그래서 앱 설치에서 로그인까지는 Amplitude `device_id`, 로그인 이후 계정 행동은 서버 `users.id` 기반 `user_id`, 익명 기기와 계정의 연결은 `anonymous_device_id`로 본다.

## 기본 사용자 흐름

| 흐름 | 주요 이벤트 | 필수 속성 | 주 식별자 | 확인할 것 |
| -- | -- | -- | -- | -- |
| 설치 및 앱 진입 | Amplitude SDK lifecycle/session 자동 이벤트 | `environment` | `device_id` | 설치/진입 모수, 로그인 전 이탈 |
| 로그인 성공 | `login` | `method`, `onboarding_completed`, `environment` | `user_id` | 소셜 로그인 방법별 전환 |
| 온보딩 완료 | `onboarding_completed` | `environment` | `user_id` | 로그인 후 초기 세팅 완료 |
| 권한 허용 | `permission_result` | `type`, `granted`, `environment` | `user_id` | 측정 시작 전 권한 이탈 |
| 식사 측정 시작 | `meal_session_started` | `environment` | `user_id` | 핵심 기능 시도 |
| 식사 측정 종료/저장 성공 | `meal_session_completed` | `duration_sec`, `sample_count`, `reportable`, `chewing_fraction`, `estimated_total_chews`, `environment` | `user_id` | 실제 이용 완료 |
| 식사 측정 중단 | `meal_session_aborted` | `reason`, `duration_sec`, `environment` | `user_id` | 저장 전 이탈 이유 |
| 식사 저장 실패 | `meal_session_failed` | `reason`, `environment` | `user_id` | 기술적 실패로 인한 손실 |
| 리포트 이용 | `report_tab_viewed`, `report_date_selected`, `report_calendar_opened`, `daily_report_opened`, `meal_report_opened` | 날짜/소스/점수/세션 수 계열 속성, `environment` | `user_id` | 측정 후 결과 확인 |
| 보상 및 경제 | `reward_earned`, `streak_event`, `shop_item_purchased` | 포인트/종류/아이템/가격 계열 속성, `environment` | `user_id` | 보상 경험과 소비 |
| 친구 초대 | `friend_invite_received` | `logged_in`, `environment` | 로그인 전은 `device_id`, 로그인 후는 `user_id` | 초대 유입과 로그인 연결 |
| 로그아웃 | `logout` | `source`, `environment` | 마지막 로그인 `user_id` | 계정 세션 종료 |
| 탈퇴 | `account_deleted` | `source`, `environment` | 마지막 로그인 `user_id` | 탈퇴 발생 계정 |
| 재가입 | `login` | `method`, `onboarding_completed`, `environment` | 새 서버 `users.id` | 같은 `anonymous_device_id`의 새 계정 로그인 |

## 기존 이벤트와 프로퍼티

현재 직접 정의된 이벤트는 `ChewChewIOS/Analytics/AnalyticsEvent.swift`가 원본이다. 모든 직접 이벤트에는 `CompositeAnalytics`에서 `environment = dev|prod`가 공통 속성으로 붙는다.

현재 user property는 로그인 또는 세션 복원 시 아래 값을 설정한다.

| user property | 값 | 용도 |
| -- | -- | -- |
| `anonymous_device_id` | `DeviceIdentity.shared` | 로그인 전 익명 기기와 로그인 후 계정 연결 |
| `has_completed_onboarding` | 서버/앱 온보딩 완료 여부 | 로그인 후 온보딩 완료 세그먼트 |
| `current_streak` | 홈 상태의 현재 스트릭 | 활성 사용자 상태 세그먼트 |
| `total_points` | 현재 포인트 | 보상/경제 상태 세그먼트 |

## Amplitude 차트 구성

### 1. 설치에서 로그인 전환

목적은 익명 설치/진입이 로그인 계정으로 얼마나 전환되는지 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | Amplitude SDK lifecycle 설치 또는 앱 진입 이벤트 | `device_id` |
| 2 | `login` | `device_id`에서 `user_id`로 전환된 사용자 |

필터는 `environment = prod`를 기본으로 둔다. 세그먼트는 `method`로 나눈다. 로그인 전 홈 사용은 제품 정책상 허용하지 않으므로 로그인 전 행동 퍼널은 만들지 않는다.

### 2. 로그인에서 첫 핵심 기능 시도

목적은 로그인한 계정이 측정 기능까지 도달하는지 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | `login` | `user_id` |
| 2 | `onboarding_completed` | `user_id` |
| 3 | `permission_result` where `type = motion`, `granted = true` | `user_id` |
| 4 | `meal_session_started` | `user_id` |

아하 모먼트가 확정되기 전까지는 4단계를 "핵심 기능 시도"로만 부른다. 이후 아하 모먼트가 식사 저장 성공으로 정해지면 5단계에 `meal_session_completed`를 추가하면 된다.

### 3. 측정 시작에서 저장 성공

목적은 핵심 기능 내부 이탈과 실패를 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | `meal_session_started` | `user_id` |
| 2 | `meal_session_completed` | `user_id` |

보조 차트로 `meal_session_aborted`를 `reason`별로 보고, `meal_session_failed`를 `reason`별로 본다. `meal_session_completed`는 `reportable`, `duration_sec`, `sample_count`로 breakdown한다.

### 4. 측정 후 리포트 확인

목적은 저장 성공 후 사용자가 결과를 확인하는지 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | `meal_session_completed` | `user_id` |
| 2 | `report_tab_viewed` | `user_id` |
| 3 | `daily_report_opened` 또는 `meal_report_opened` | `user_id` |

세그먼트는 `reportable`, `days_from_today`, `source`를 우선 사용한다.

### 5. 보상 경험과 재사용 후보

목적은 리텐션 기준 확정 전까지 재사용 후보 행동을 관찰하는 것이다.

| 차트 | 이벤트 | 기준 |
| -- | -- | -- |
| 보상 발생 | `reward_earned` | `user_id`, `kind` |
| 스트릭 변화 | `streak_event` | `user_id`, `type` |
| 포인트 소비 | `shop_item_purchased` | `user_id`, `item_type`, `price` |

리텐션 행동이 확정되면 returning event를 `meal_session_completed`, `report_tab_viewed`, `reward_earned` 중 하나로 선택한다. 현재 기본값 후보는 실제 식사 이용을 가장 잘 나타내는 `meal_session_completed`다.

### 6. 로그아웃, 탈퇴, 재가입

목적은 계정 이탈과 재가입 흐름을 계정 단위로 분리해서 보는 것이다.

| 차트 | 이벤트/조건 | 기준 |
| -- | -- | -- |
| 로그아웃 발생 | `logout` | `user_id`, `source` |
| 탈퇴 발생 | `account_deleted` | `user_id`, `source` |
| 재가입 후보 | 같은 `anonymous_device_id`에서 `account_deleted` 이후 다른 `user_id`의 `login` | `anonymous_device_id` |

서버는 탈퇴 시 기존 계정을 `WITHDRAWN`으로 소프트 딜리트하고 소셜 인증 연결을 제거한다. 같은 소셜 계정으로 다시 로그인하면 새 `users.id`가 발급되므로, Amplitude에서도 재가입 계정은 새 `user_id`로 본다.

## 향후 아하 모먼트/리텐션 기준 연결

아하 모먼트가 확정되면 새 이벤트를 먼저 만들지 말고 기존 이벤트 중 하나를 기준 이벤트로 승격한다. 후보는 `meal_session_started`, `meal_session_completed`, `daily_report_opened`, `reward_earned`다.

리텐션 기준이 확정되면 returning event를 하나 고른다. 기본 후보는 `meal_session_completed`이며, 제품 판단에 따라 "리포트 확인까지 해야 재사용"으로 볼 경우 `report_tab_viewed` 또는 `daily_report_opened`로 바꾼다.

부족한 이벤트가 발견되면 이 문서의 표에 먼저 추가하고, `AnalyticsEvent.swift`에 타입 안전 팩토리와 호출부 테스트를 함께 추가한다.
