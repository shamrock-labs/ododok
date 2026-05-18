-- user_progress 단일 테이블을 profiles + user_stats 두 테이블로 분리.
--   profiles   : 디바이스 신원 메타 (display_name 등 — 지금은 device_id만 실사용).
--   user_stats : 게임 진행 상태 (카운터 + 인벤토리 + 플래그). FK → profiles.
-- worktree-insforge-setup 브랜치의 분리 구조와 정렬. PK는 여전히 device_id;
-- auth.users 기반 전환과 RLS 강화는 후속 PR.

-- 1. profiles ----------------------------------------------------------------

create table if not exists public.profiles (
    device_id     text primary key,
    display_name  text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create or replace function public.profiles_set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.profiles_set_updated_at();

-- 2. user_stats --------------------------------------------------------------

create table if not exists public.user_stats (
    device_id           text primary key references public.profiles(device_id) on delete cascade,
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

create or replace function public.user_stats_set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists user_stats_set_updated_at on public.user_stats;
create trigger user_stats_set_updated_at
before update on public.user_stats
for each row execute function public.user_stats_set_updated_at();

-- 3. 기존 user_progress가 있다면 데이터 이관 후 폐기 ---------------------
--    (이전 마이그레이션을 이미 적용한 환경 대응. 이관할 row가 없으면 no-op.)

do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'user_progress'
    ) then
        insert into public.profiles (device_id, created_at, updated_at)
        select device_id, created_at, updated_at
        from public.user_progress
        on conflict (device_id) do nothing;

        insert into public.user_stats (
            device_id, chew_count, streak, points, weekly_scores,
            goal_already_hit, owned, equipped, owned_acorn_packs,
            saved_at, created_at, updated_at
        )
        select device_id, chew_count, streak, points, weekly_scores,
               goal_already_hit, owned, equipped, owned_acorn_packs,
               saved_at, created_at, updated_at
        from public.user_progress
        on conflict (device_id) do nothing;

        drop table public.user_progress;
        drop function if exists public.user_progress_set_updated_at();
    end if;
end$$;

-- 4. RLS — 기존과 동일 (다음 PR에서 device_id 헤더 기반으로 강화) ------

alter table public.profiles enable row level security;
drop policy if exists profiles_all on public.profiles;
create policy profiles_all on public.profiles
    for all using (true) with check (true);

alter table public.user_stats enable row level security;
drop policy if exists user_stats_all on public.user_stats;
create policy user_stats_all on public.user_stats
    for all using (true) with check (true);
