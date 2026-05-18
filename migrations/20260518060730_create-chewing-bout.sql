-- chewing_bout
--   외부 ML 파이프라인이 chewing_session.storage_path를 읽어 분석한
--   "연속 씹기 구간" 결과. 클라이언트는 이번 PR에서 INSERT하지 않는다.
--   스키마와 RLS만 미리 잡아두고, 분석 측 권한은 서비스 키로 통제.

create table if not exists public.chewing_bout (
    id                uuid primary key default gen_random_uuid(),
    session_id        uuid not null references public.chewing_session(id) on delete cascade,
    t_start_sec       double precision not null,
    t_end_sec         double precision not null,
    duration_sec      double precision not null,
    estimated_chews   int not null,
    mean_confidence   double precision not null,
    model_version     text,
    created_at        timestamptz not null default now()
);

create index if not exists chewing_bout_session_idx
    on public.chewing_bout (session_id, t_start_sec);

-- 클라이언트는 read-only로 본인 세션의 bout만 볼 수 있게 풀어두고,
-- INSERT/UPDATE/DELETE는 서비스 키 경로로만. TODO: 다음 PR에서 device_id 기준으로 좁힘.
alter table public.chewing_bout enable row level security;
drop policy if exists chewing_bout_select on public.chewing_bout;
create policy chewing_bout_select on public.chewing_bout
    for select
    using (true);
