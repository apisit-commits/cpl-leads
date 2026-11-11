-- Sales Offline (เซลล์ภาคสนาม) — รันครั้งเดียวใน Supabase SQL Editor
-- สร้างตารางแยกต่างหากจากข้อมูล Lead Tracker (ไม่ปนกับตาราง leads)

create table if not exists public.so_deals (
  id bigint generated always as identity primary key,
  team text not null,
  company text not null,
  mode text,
  stage text not null default 'lead',
  sales text,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
alter table public.so_deals enable row level security;
drop policy if exists so_deals_rw on public.so_deals;
create policy so_deals_rw on public.so_deals for all to authenticated using (true) with check (true);

create table if not exists public.so_visits (
  id bigint generated always as identity primary key,
  team text not null,
  deal_id bigint references public.so_deals(id) on delete set null,
  company text not null,
  sales text,
  visit_date date not null,
  visit_time time not null,
  purpose text,
  checked_in boolean not null default false,
  checkin_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.so_visits enable row level security;
drop policy if exists so_visits_rw on public.so_visits;
create policy so_visits_rw on public.so_visits for all to authenticated using (true) with check (true);

create table if not exists public.so_activity (
  id bigint generated always as identity primary key,
  team text not null,
  actor_name text,
  action_text text not null,
  created_at timestamptz not null default now()
);
alter table public.so_activity enable row level security;
drop policy if exists so_activity_rw on public.so_activity;
create policy so_activity_rw on public.so_activity for all to authenticated using (true) with check (true);

create index if not exists so_deals_team_idx on public.so_deals(team);
create index if not exists so_visits_team_date_idx on public.so_visits(team, visit_date);
create index if not exists so_activity_team_idx on public.so_activity(team, created_at desc);
