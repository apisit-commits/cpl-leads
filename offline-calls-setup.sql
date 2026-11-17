-- Offline Team: call list (รายชื่อโทร) and call history
create table if not exists public.so_calls (
  id bigint generated always as identity primary key,
  team text not null default 'C',
  company text not null,
  contact text,
  phone text,
  email text,
  address text,
  postal text,
  country text,
  grp text,
  last_buy date,
  assignee text,
  status text not null default 'new',
  attempts int not null default 0,
  last_call_at timestamptz,
  last_call_by text,
  callback_date date,
  calling_by text,
  calling_at timestamptz,
  note text,
  matched text,
  batch text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.so_calls enable row level security;
drop policy if exists so_calls_rw on public.so_calls;
create policy so_calls_rw on public.so_calls for all to authenticated using (true) with check (true);
create index if not exists so_calls_team_idx on public.so_calls(team, status);
create index if not exists so_calls_assignee_idx on public.so_calls(assignee);

create table if not exists public.so_call_logs (
  id bigint generated always as identity primary key,
  call_id bigint not null references public.so_calls(id) on delete cascade,
  actor text,
  result text,
  status text,
  note text,
  created_at timestamptz not null default now()
);
alter table public.so_call_logs enable row level security;
drop policy if exists so_call_logs_rw on public.so_call_logs;
create policy so_call_logs_rw on public.so_call_logs for all to authenticated using (true) with check (true);
create index if not exists so_call_logs_call_idx on public.so_call_logs(call_id, created_at desc);

-- Hand-off from Online (Lead ไม่สนใจ ครบ 30 วัน ที่มีเบอร์)
alter table public.so_calls add column if not exists src text;
alter table public.so_calls add column if not exists src_lead bigint;
create unique index if not exists so_calls_src_lead_uq on public.so_calls(src_lead) where src_lead is not null;
