# Amplitude 기본 사용자 흐름 추적 기준

이 문서는 앱 설치부터 로그인, 앱 이용, 로그아웃, 탈퇴, 재가입까지의 기본 사용자 흐름을 Amplitude에서 같은 기준으로 보기 위한 트래킹 기준이다. 아하 모먼트와 리텐션 행동은 아직 확정하지 않고, 나중에 기준이 정해졌을 때 최소 변경으로 퍼널과 리텐션 차트를 만들 수 있게 현재 이벤트와 식별자 기준을 정리한다.

Amplitude는 US 리전의 `Ododok Dev`, `Ododok Prod` 프로젝트로 분리한다. Debug와 TestFlight 빌드는 Dev 프로젝트로, App Store Release 빌드는 Prod 프로젝트로 전송한다. 각 프로젝트는 별도 API Key와 SDK 인스턴스명을 사용해 전송 대기 큐와 기기 식별 저장소까지 격리한다. 모든 직접 이벤트에는 백엔드 환경인 `environment=dev|prod`와 배포 채널인 `build_channel=debug|testflight|app_store`가 함께 붙는다.

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
| 설치 및 앱 진입 | `app_opened` | `launch_type`, `authentication_state`, `onboarding_completed`, `chew_profile_configured`, `environment` | 로그인 전 `device_id`, 로그인 후 `user_id` | 환경별 진입 모수, 로그인 전 이탈 |
| 로그인 시도·결과 | `login_started`, `login_cancelled`, `login_failed`, `login` | `method`, 실패 시 `reason`, 성공 시 `onboarding_completed`, `environment` | 성공 전 `device_id`, 성공 후 `user_id` | 로그인 이탈을 취소·프로바이더·서버 실패로 구분 |
| 온보딩 진행·완료 | `onboarding_started`, `onboarding_step_completed`, `onboarding_step_failed`, `onboarding_completed` | `step`, `name_method`, `completion_method`, `last_step`, 실패 시 `reason`, `environment` | `user_id` | 닉네임 방식, 튜토리얼 건너뛰기, 저장 실패 |
| 권한 결과 | `permission_result` | `type`, `status`, `granted`, `source`, `environment` | `user_id` | 모션·알림 권한과 센서 미지원/오류 구분 |
| 식사 시작 시도 | `meal_start_requested`, `meal_start_blocked`, `meal_start_cancelled` | `source`, 차단 시 `reason`, 취소 시 `stage`, `environment` | `user_id` | 홈·알림 유입과 AirPods·권한 이탈 |
| 식사 측정 시작 | `meal_session_started` | `meal_session_id`, `source`, `environment`, `build_channel` | `user_id` | 시작 시도 중 실제 측정 전환 |
| 식사 측정 종료/저장 성공 | `meal_session_completed` | `meal_session_id`, `duration_sec`, `sample_count`, `reportable`, `chewing_fraction`, `estimated_total_chews`, `environment`, `build_channel` | `user_id` | 실제 이용 완료 |
| 식사 측정 중단 | `meal_session_aborted` | `meal_session_id`, `reason`, `duration_sec`, `environment`, `build_channel` | `user_id` | 저장 전 이탈 이유 |
| 식사 저장 실패·복구 | `meal_session_failed`, `meal_session_upload_retry_requested`, `meal_session_upload_abandoned` | `meal_session_id`, `reason`, `attempt_number`, `next_attempt_number`, `failed_attempt_count`, `environment`, `build_channel` | `user_id` | 기술적 실패, 재시도, 사용자 포기 |
| 리포트 이용 | `report_tab_viewed`, `report_date_selected`, `report_calendar_opened`, `daily_report_opened`, `meal_report_opened` | 날짜/소스/점수/세션 수 계열 속성, `environment` | `user_id` | 측정 후 결과 확인 |
| 보상 및 경제 | `reward_earned`, `streak_event`, `shop_item_purchased` | 포인트/종류/아이템/가격 계열 속성, `environment` | `user_id` | 보상 경험과 소비 |
| 친구 초대 | `friend_invite_received` | `logged_in`, `environment` | 로그인 전은 `device_id`, 로그인 후는 `user_id` | 초대 유입과 로그인 연결 |
| 로그아웃 | `logout` | `source`, `environment` | 마지막 로그인 `user_id` | 계정 세션 종료 |
| 탈퇴 | `account_deleted` | `source`, `environment` | 마지막 로그인 `user_id` | 탈퇴 발생 계정 |
| 재가입 | `login` | `method`, `onboarding_completed`, `environment` | 새 서버 `users.id` | 같은 `anonymous_device_id`의 새 계정 로그인 |
| 개인 씹기 프로필 설정 | `chew_profile_setup_offered`, `chew_profile_setup_started`, `chew_profile_setup_step_completed`, `chew_profile_setup_completed`, `chew_profile_setup_failed`, `chew_profile_setup_dismissed`, `chew_profile_reset` | `source`, 단계·소요 시간·실패 사유·재시도 횟수, `environment` | `user_id` | 온보딩·설정 진입별 전환과 이탈 |

## 기존 이벤트와 프로퍼티

현재 직접 정의된 이벤트는 `ChewChewIOS/Analytics/AnalyticsEvent.swift`가 원본이다. 모든 직접 이벤트에는 `CompositeAnalytics`에서 `environment = dev|prod`와 `build_channel = debug|testflight|app_store`가 공통 속성으로 붙는다.

현재 user property는 로그인 또는 세션 복원 시 아래 값을 설정한다.

| user property | 값 | 용도 |
| -- | -- | -- |
| `anonymous_device_id` | `DeviceIdentity.shared` | 로그인 전 익명 기기와 로그인 후 계정 연결 |
| `has_completed_onboarding` | 서버/앱 온보딩 완료 여부 | 로그인 후 온보딩 완료 세그먼트 |
| `current_streak` | 홈 상태의 현재 스트릭 | 활성 사용자 상태 세그먼트 |
| `total_points` | 현재 포인트 | 보상/경제 상태 세그먼트 |

## Amplitude 차트 구성

### 1. 앱 진입에서 로그인 전환

목적은 익명 설치/진입이 로그인 계정으로 얼마나 전환되는지 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | `app_opened` | 로그인 전 `device_id`, 로그인 후 `user_id` |
| 2 | `login_started` | 로그인 방법을 선택한 `device_id` |
| 3 | `login` | `device_id`에서 `user_id`로 전환된 사용자 |

운영 차트는 `Ododok Prod` 프로젝트에서 만들고 필요하면 `environment = prod`를 방어적으로 적용한다. 세그먼트는 `launch_type`, `authentication_state`, `method`로 나눈다. SDK 자동 `[Amplitude] Application Opened`는 앱의 `environment` 속성이 없지만 프로젝트가 분리되어 개발 빌드 이벤트와 섞이지 않는다.

### 2. 로그인에서 첫 핵심 기능 시도

목적은 로그인한 계정이 측정 기능까지 도달하는지 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | `login` | `user_id` |
| 2 | `onboarding_completed` | `user_id` |
| 3 | `meal_start_requested` | `user_id`, `source` |
| 4 | `meal_session_started` | `user_id`, `source` |

`permission_result`는 권한이 처음 결정되는 순간에만 발생하므로 필수 퍼널 단계로 두지 않는다. `meal_start_blocked`와 함께 `type`, `status`, `reason` 진단 차트로 본다. 아하 모먼트가 확정되기 전까지는 4단계를 "핵심 기능 시도"로만 부른다. 이후 아하 모먼트가 식사 저장 성공으로 정해지면 5단계에 `meal_session_completed`를 추가하면 된다.

### 3. 측정 시작에서 저장 성공

목적은 핵심 기능 내부 이탈과 실패를 보는 것이다.

| 단계 | 이벤트 | 기준 |
| -- | -- | -- |
| 1 | `meal_session_started` | `user_id` |
| 2 | `meal_session_completed` | `user_id` |

보조 차트로 `meal_start_blocked`를 `source`, `reason`별로 보고, `meal_session_aborted`를 `reason`별로 본다. `meal_session_failed`는 세션 수를 중복 집계하지 않도록 `meal_session_id` 기준 고유값과 `attempt_number`를 함께 본다. 실패 이후 `meal_session_upload_retry_requested`, `meal_session_upload_abandoned`, `meal_session_completed`를 같은 `meal_session_id`로 연결한다. `meal_session_completed`는 `reportable`, `duration_sec`, `sample_count`로 breakdown한다.

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

### 7. 개인 씹기 프로필 설정

온보딩 직후 제안 흐름은 아래 퍼널로 본다.

| 단계 | 이벤트 | 조건 |
| -- | -- | -- |
| 1 | `onboarding_completed` | `environment = prod` |
| 2 | `chew_profile_setup_offered` | `source = onboarding` |
| 3 | `chew_profile_setup_started` | `source = onboarding` |
| 4 | `chew_profile_setup_completed` | `source = onboarding` |

설정에서 최초 설정하거나 재측정하는 흐름은 `chew_profile_setup_started where source = settings`에서 `chew_profile_setup_completed`로 본다. 보조 차트는 `chew_profile_setup_failed`를 `step`, `reason`으로, `chew_profile_setup_dismissed`를 `source`, `step`으로 분해한다.

분석 단계명은 내부 구현 용어와 분리한다. 정지 신호는 `resting_signal`, 자연스러운 씹기 신호는 `chewing_signal`, 최종 확인은 `verification`을 사용한다. 모든 개인 씹기 프로필 이벤트는 `CompositeAnalytics`를 통과하므로 `environment = dev|prod`가 자동 첨부된다.

## 향후 아하 모먼트/리텐션 기준 연결

아하 모먼트가 확정되면 새 이벤트를 먼저 만들지 말고 기존 이벤트 중 하나를 기준 이벤트로 승격한다. 후보는 `meal_session_started`, `meal_session_completed`, `daily_report_opened`, `reward_earned`다.

리텐션 기준이 확정되면 returning event를 하나 고른다. 기본 후보는 `meal_session_completed`이며, 제품 판단에 따라 "리포트 확인까지 해야 재사용"으로 볼 경우 `report_tab_viewed` 또는 `daily_report_opened`로 바꾼다.

부족한 이벤트가 발견되면 이 문서의 표에 먼저 추가하고, `AnalyticsEvent.swift`에 타입 안전 팩토리와 호출부 테스트를 함께 추가한다.
