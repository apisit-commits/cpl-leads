create table if not exists public.cls_state (
  user_id text primary key,
  name text,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.cls_state enable row level security;
drop policy if exists cls_state_rw on public.cls_state;
create policy cls_state_rw on public.cls_state for all to authenticated using (true) with check (true);
