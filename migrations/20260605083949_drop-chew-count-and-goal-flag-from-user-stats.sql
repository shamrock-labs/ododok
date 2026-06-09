-- user_stats.chew_count, goal_already_hit 제거 (dead column).
--   chew_count는 식사 중 가짜 0.85초 Timer가 굴리던 in-app 화폐 카운터로, 실제 씹기와
--   무관하고 화면 어디에도 노출된 적이 없다. "실제 씹기" 수치의 source of truth는
--   chewing_session.estimated_total_chews 합(앱의 todayRealChewCount)이다.
--   goal_already_hit는 dailyGoal 첫 도달 플래그였으나 소비처(분기) 없이 자기 자신만
--   게이트하던 미사용 값 — "향후 트로피/스트릭 trigger" 용도로 남겨뒀으나 실연동이 없었다.
--   생산처(가짜 Timer)·소비처(View) 정리와 함께 두 컬럼을 제거한다.
--
-- 주의: 이미 배포된 옛 클라이언트는 upsert 시 두 필드를 계속 보낼 수 있으나,
--   MVP 단계 dev 디바이스만 존재하므로 영향 없음. 신규 빌드는 필드 자체를 안 보낸다.

alter table public.user_stats
    drop column if exists chew_count,
    drop column if exists goal_already_hit;
