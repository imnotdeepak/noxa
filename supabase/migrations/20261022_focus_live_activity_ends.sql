-- Apply once to an existing Noxa project before deploying the Live Activity functions.
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
