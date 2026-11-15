-- Offline Team: extra details for target companies and visit results
alter table public.so_deals  add column if not exists data jsonb not null default '{}'::jsonb;
alter table public.so_visits add column if not exists data jsonb not null default '{}'::jsonb;
