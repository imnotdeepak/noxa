-- Apply once before deploying the updated delete-account function.
-- Tracks RevenueCat cleanup for account deletions. No foreign key to
-- auth.users: a row must outlive the account until RevenueCat confirms the
-- customer is gone. Only the service role reads or writes it.
create table if not exists public.account_deletion_jobs (
  user_id uuid primary key,
  status text not null default 'pending' check (status in ('pending', 'verifying')),
  revenuecat_customer_ids text[] not null default '{}',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists account_deletion_jobs_verifying_idx
  on public.account_deletion_jobs(updated_at)
  where status = 'verifying';
alter table public.account_deletion_jobs enable row level security;
revoke all on public.account_deletion_jobs from anon, authenticated;
