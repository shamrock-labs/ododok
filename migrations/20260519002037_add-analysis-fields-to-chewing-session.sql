-- chewing_session 테이블에 ML 분석 결과 5필드 추가.
-- 온디바이스 ChewingPredictor가 동작한 세션에서만 채워지는 분석 결과이며,
-- 시뮬레이터/AirPods 미연결처럼 추론이 안 도는 세션은 NULL을 허용한다 (기존 row 포함).
--
-- 컬럼:
--   chewing_seconds       : chewing 라벨 윈도우 합산 시간 (초)
--   rest_seconds          : rest 라벨 윈도우 합산 시간 (초)
--   chewing_fraction      : chewing 윈도우 비율 (0.0–1.0)
--   estimated_total_chews : bout 기반 추정 총 chew 수 (duration × 1.2 round, 연구 기반 평균)
--   model_version         : 사용된 ChewingClassifier 빌드 버전 식별자

alter table public.chewing_session
    add column if not exists chewing_seconds       double precision,
    add column if not exists rest_seconds          double precision,
    add column if not exists chewing_fraction      double precision,
    add column if not exists estimated_total_chews int,
    add column if not exists model_version         text;
