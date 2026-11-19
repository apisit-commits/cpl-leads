create table if not exists public.office_cfg (
  id int primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.office_cfg (id) values (1) on conflict (id) do nothing;
create table if not exists public.office_status (
  user_id text primary key,
  name text,
  loc text,
  note text,
  updated_at timestamptz not null default now()
);
alter table public.office_cfg enable row level security;
alter table public.office_status enable row level security;
drop policy if exists office_cfg_rw on public.office_cfg;
create policy office_cfg_rw on public.office_cfg for all to authenticated using (true) with check (true);
drop policy if exists office_status_rw on public.office_status;
create policy office_status_rw on public.office_status for all to authenticated using (true) with check (true);
