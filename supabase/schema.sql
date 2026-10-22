-- Noxa cloud persistence (stage 3)
--
-- Run this file in the Supabase SQL editor for the Noxa project. It creates
-- only product data tables. FamilyActivitySelection, Apple activity tokens,
-- active shields, schedules, and raw Screen Time usage never leave the device.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  platform text not null default 'ios',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null,
  plan text not null,
  platform text not null default 'ios',
  original_transaction_id text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists subscriptions_user_id_idx
  on public.subscriptions(user_id);

create table if not exists public.website_blocklist (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  domain text not null check (char_length(domain) between 3 and 253),
  created_at timestamptz not null default now(),
  unique (user_id, domain)
);

create index if not exists website_blocklist_user_id_idx
  on public.website_blocklist(user_id);

create table if not exists public.focus_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'ios',
  start_time timestamptz not null,
  planned_duration_seconds integer not null check (planned_duration_seconds >= 0),
  actual_duration_seconds integer not null check (actual_duration_seconds >= 0),
  outcome text not null check (
    outcome in ('completed', 'ended_early', 'failed_to_start', 'interrupted', 'recovered_stale')
  ),
  completed_successfully boolean not null,
  apps_blocked_count integer,
  websites_blocked_count integer,
  created_at timestamptz not null default now()
);

create index if not exists focus_sessions_user_start_idx
  on public.focus_sessions(user_id, start_time desc);

-- Short-lived ActivityKit delivery data. This contains no Screen Time targets.
-- Only server functions may read or write it; account deletion cascades it.
create table if not exists public.focus_live_activity_ends (
  session_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  push_token text not null,
  apns_environment text not null check (apns_environment in ('sandbox', 'production')),
  started_at timestamptz not null,
  planned_end_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed')),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id),
  check (planned_end_at > started_at),
  check (planned_end_at <= started_at + interval '8 hours')
);
create index if not exists focus_live_activity_ends_due_idx
  on public.focus_live_activity_ends(planned_end_at)
  where status = 'pending';
alter table public.focus_live_activity_ends enable row level security;

-- Upgrade databases created by the first stage-three draft. Legacy Boolean
-- rows cannot distinguish all outcomes, so successful rows migrate to
-- completed and unsuccessful rows migrate to interrupted.
alter table public.focus_sessions
  add column if not exists outcome text;
update public.focus_sessions
set outcome = case
  when completed_successfully then 'completed'
  else 'interrupted'
end
where outcome is null;
alter table public.focus_sessions
  alter column outcome set not null;
alter table public.focus_sessions
  drop constraint if exists focus_sessions_outcome_check;
alter table public.focus_sessions
  add constraint focus_sessions_outcome_check check (
    outcome in ('completed', 'ended_early', 'failed_to_start', 'interrupted', 'recovered_stale')
  );

create table if not exists public.usage_limit_config (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_reference_id uuid not null,
  daily_limit_minutes integer not null check (daily_limit_minutes between 5 and 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, local_reference_id)
);

create table if not exists public.limit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_reference_id uuid,
  event_type text not null,
  occurred_at timestamptz not null default now()
);

create index if not exists limit_events_user_occurred_idx
  on public.limit_events(user_id, occurred_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists subscriptions_set_updated_at on public.subscriptions;
create trigger subscriptions_set_updated_at
before update on public.subscriptions
for each row execute function public.set_updated_at();

drop trigger if exists usage_limit_config_set_updated_at on public.usage_limit_config;
create trigger usage_limit_config_set_updated_at
before update on public.usage_limit_config
for each row execute function public.set_updated_at();

-- Create a profile as soon as Auth creates a user. The client also upserts the
-- row so an existing account is repaired if this trigger was added later.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, platform)
  values (new.id, new.email, 'ios')
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.subscriptions enable row level security;
alter table public.website_blocklist enable row level security;
alter table public.focus_sessions enable row level security;
alter table public.usage_limit_config enable row level security;
alter table public.limit_events enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
for select to authenticated using (auth.uid() = id);
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
for insert to authenticated with check (auth.uid() = id);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
for select to authenticated using (auth.uid() = user_id);

drop policy if exists website_blocklist_select_own on public.website_blocklist;
create policy website_blocklist_select_own on public.website_blocklist
for select to authenticated using (auth.uid() = user_id);
drop policy if exists website_blocklist_insert_own on public.website_blocklist;
create policy website_blocklist_insert_own on public.website_blocklist
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists website_blocklist_update_own on public.website_blocklist;
create policy website_blocklist_update_own on public.website_blocklist
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists website_blocklist_delete_own on public.website_blocklist;
create policy website_blocklist_delete_own on public.website_blocklist
for delete to authenticated using (auth.uid() = user_id);

drop policy if exists focus_sessions_select_own on public.focus_sessions;
create policy focus_sessions_select_own on public.focus_sessions
for select to authenticated using (auth.uid() = user_id);
drop policy if exists focus_sessions_insert_own on public.focus_sessions;
create policy focus_sessions_insert_own on public.focus_sessions
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists focus_sessions_update_own on public.focus_sessions;
create policy focus_sessions_update_own on public.focus_sessions
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists usage_limit_config_select_own on public.usage_limit_config;
create policy usage_limit_config_select_own on public.usage_limit_config
for select to authenticated using (auth.uid() = user_id);
drop policy if exists usage_limit_config_insert_own on public.usage_limit_config;
create policy usage_limit_config_insert_own on public.usage_limit_config
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists usage_limit_config_update_own on public.usage_limit_config;
create policy usage_limit_config_update_own on public.usage_limit_config
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists usage_limit_config_delete_own on public.usage_limit_config;
create policy usage_limit_config_delete_own on public.usage_limit_config
for delete to authenticated using (auth.uid() = user_id);

drop policy if exists limit_events_select_own on public.limit_events;
create policy limit_events_select_own on public.limit_events
for select to authenticated using (auth.uid() = user_id);
drop policy if exists limit_events_insert_own on public.limit_events;
create policy limit_events_insert_own on public.limit_events
for insert to authenticated with check (auth.uid() = user_id);

-- Replacing the website list in one server-side operation makes removals
-- idempotent and avoids leaving stale domains in the cloud. The function only
-- accepts the caller's own auth.uid(); no user_id is accepted from the app.
create or replace function public.replace_website_blocklist(domains text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  delete from public.website_blocklist
  where user_id = auth.uid();

  insert into public.website_blocklist (user_id, domain)
  select auth.uid(), lower(trim(domain))
  from unnest(coalesce(domains, array[]::text[])) as supplied(domain)
  where char_length(trim(domain)) between 3 and 253
  on conflict (user_id, domain) do nothing;
end;
$$;

revoke all on function public.replace_website_blocklist(text[]) from public;
grant execute on function public.replace_website_blocklist(text[]) to authenticated;
