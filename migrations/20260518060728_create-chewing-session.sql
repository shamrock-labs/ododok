-- chewing_session
--   AirPods IMU 50Hz × 6채널 한 끼 분량의 "메타" 1행.
--   raw 데이터는 imu-sessions 버킷에 gzip CSV로 올라가고 storage_path만 보관.
--   외부 ML 파이프라인이 storage_path를 읽어 분석한 결과는 chewing_bout로.

create extension if not exists "pgcrypto";

create table if not exists public.chewing_session (
    id               uuid primary key default gen_random_uuid(),
    device_id        text         not null,
    started_at       timestamptz  not null,
    ended_at         timestamptz  not null,
    duration_sec     double precision not null,
    sensor_location  text         not null default 'default',
    sample_count     int          not null default 0,
    sample_rate_hz   int          not null default 50,
    storage_path     text,
    app_version      text,
    created_at       timestamptz  not null default now()
);

create index if not exists chewing_session_device_started_idx
    on public.chewing_session (device_id, started_at desc);

-- TODO: 다음 PR에서 device_id 헤더 기반 RLS로 강화.
alter table public.chewing_session enable row level security;
drop policy if exists chewing_session_all on public.chewing_session;
create policy chewing_session_all on public.chewing_session
    for all
    using (true)
    with check (true);
