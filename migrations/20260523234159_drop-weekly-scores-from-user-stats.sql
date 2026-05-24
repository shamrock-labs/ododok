-- user_stats.weekly_scores 제거 (dead column).
--   주간 점수 막대그래프(scoreCard)는 #7에서 인라인 캘린더로 교체되며 UI에서 사라졌고,
--   이 컬럼을 실제 데이터로 채우는 산출 로직은 처음부터 없었다 — 옛 하드코딩 시드값
--   [72,85,68,78,82,88,41]만 일부 row에 잔존(#9에서 시드 제거 이전 빌드가 동기화한 흔적).
--   소비처(View)·생산처(계산) 모두 없는 dead column이라 제거한다.
--   트래킹/리포트 점수의 source of truth는 chewing_session(세션별 SessionScore.compute).
--
-- 주의: 이미 배포된 옛 클라이언트는 upsert 시 weekly_scores를 계속 보낼 수 있으나,
--   MVP(0.1.0) 단계 dev 디바이스만 존재하므로 영향 없음. 신규 빌드는 필드 자체를 안 보낸다.

alter table public.user_stats
    drop column if exists weekly_scores;
