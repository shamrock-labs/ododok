-- user_progress
--   기존 UserDefaults 단일 키(`ChewChewIOS.AppState.snapshot.v1`)에
--   JSON Blob으로 저장하던 게임 진행 상태를 단일 행으로 1:1 매핑.
--   row 1개 = 기기 1대 = 익명 디바이스 UUID.

create table if not exists public.user_progress (
    device_id           text primary key,
    chew_count          int          not null default 0,
    streak              int          not null default 0,
    points              int          not null default 0,
    weekly_scores       int[]        not null default '{0,0,0,0,0,0,0}',
    goal_already_hit    boolean      not null default false,
    owned               jsonb        not null default '[]'::jsonb,
    equipped            jsonb        not null default '{}'::jsonb,
    owned_acorn_packs   jsonb        not null default '{}'::jsonb,
    saved_at            timestamptz  not null default now(),
    created_at          timestamptz  not null default now(),
    updated_at          timestamptz  not null default now()
);

create or replace function public.user_progress_set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists user_progress_set_updated_at on public.user_progress;
create trigger user_progress_set_updated_at
before update on public.user_progress
for each row execute function public.user_progress_set_updated_at();

-- TODO: 다음 PR에서 디바이스 ID 헤더(`x-device-id`) 기반 RLS로 강화.
-- 1차 PR은 익명 키만으로 동작해야 하므로 RLS를 풀어둔다.
alter table public.user_progress enable row level security;
drop policy if exists user_progress_all on public.user_progress;
create policy user_progress_all on public.user_progress
    for all
    using (true)
    with check (true);
