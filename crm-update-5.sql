-- CRM update 5: ฟอร์มที่สร้างเอง + เชื่อมฟอร์มกับลูกค้า + แต้มสะสม LINE
-- รันทั้งไฟล์ใน Supabase SQL Editor ได้หลายครั้ง (ไม่ซ้ำซ้อน)

-- 1) แบบฟอร์มที่เซลล์สร้างเอง (เห็นเฉพาะคนสร้าง)
create table if not exists public.form_templates (
  id bigint generated always as identity primary key,
  owner uuid not null default auth.uid(),
  owner_name text,
  name text not null,
  name_en text,
  brand text not null default 'CPL-Inter',
  schema jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.form_templates enable row level security;
drop policy if exists form_templates_own on public.form_templates;
create policy form_templates_own on public.form_templates for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

-- 2) ลิงก์ฟอร์ม: แบบฟอร์มที่ใช้ (เก็บสำเนาไว้กับลิงก์) และลูกค้าที่ผูกไว้
alter table public.cust_forms add column if not exists template_id bigint;
alter table public.cust_forms add column if not exists schema jsonb;
alter table public.cust_forms add column if not exists customer_id text;
alter table public.cust_forms drop constraint if exists cust_forms_kind_check;
alter table public.cust_forms add constraint cust_forms_kind_check check (kind in ('book','acc','job','claim','tc','custom'));
create index if not exists cust_forms_customer_idx on public.cust_forms(customer_id);

create or replace function public.form_get(p_token uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('kind', kind, 'brand', brand, 'prefill', prefill, 'status', status,
         'synced', sheet_url is not null and kind <> 'job',
         'schema', schema, 'title', prefill->>'title')
  from public.cust_forms where token = p_token;
$$;
grant execute on function public.form_get(uuid) to anon, authenticated;

-- 3) แต้มสะสม LINE: เปิดบัตร / ยืนยันชำระเงินของงานที่ปิด / แลกแต้ม / ปรับแต้ม
create table if not exists public.cust_points (
  id bigint generated always as identity primary key,
  customer_id text not null,
  brand text not null,
  kind text not null,
  lead_id bigint,
  points integer not null default 0,
  note text,
  date date not null default current_date,
  created_by text,
  created_at timestamptz not null default now()
);
alter table public.cust_points enable row level security;
drop policy if exists cust_points_rw on public.cust_points;
create policy cust_points_rw on public.cust_points for all to authenticated using (true) with check (true);
alter table public.cust_points drop constraint if exists cust_points_kind_check;
alter table public.cust_points add constraint cust_points_kind_check check (kind in ('open','paid','redeem','adjust'));
create index if not exists cust_points_customer_idx on public.cust_points(customer_id, brand);
