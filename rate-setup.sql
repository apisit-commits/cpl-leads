-- Rate Builder: เก็บชุด Rate ที่หัวหน้าเซลล์เผยแพร่ (รันครั้งเดียวใน Supabase SQL Editor)
create table if not exists public.rate_sets (
  id bigint generated always as identity primary key,
  kind text not null default 'courier',
  ver text,
  eff text,
  file text,
  data jsonb not null default '{}'::jsonb,
  rules jsonb not null default '[]'::jsonb,
  remote jsonb not null default '{}'::jsonb,
  adj jsonb not null default '{}'::jsonb,
  fuel jsonb not null default '{}'::jsonb,
  pm jsonb not null default '{}'::jsonb,
  by text,
  created_at timestamptz not null default now()
);
alter table public.rate_sets add column if not exists fuel jsonb not null default '{}'::jsonb;
alter table public.rate_sets add column if not exists pm jsonb not null default '{}'::jsonb;
alter table public.rate_sets enable row level security;
drop policy if exists rate_sets_read on public.rate_sets;
create policy rate_sets_read on public.rate_sets for select to authenticated using (true);
drop policy if exists rate_sets_write on public.rate_sets;
create policy rate_sets_write on public.rate_sets for insert to authenticated
  with check (exists (select 1 from public.profiles p where p.id = auth.uid()
    and (p.role in ('admin','sales_lead') or p.name ilike 'jonus%')));
