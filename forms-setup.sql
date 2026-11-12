-- แท็บ "ฟอร์ม" (ฟอร์มลูกค้า Booking / Account Application) — รันครั้งเดียวใน Supabase SQL Editor
-- เก็บเฉพาะข้อมูลฟอร์ม สถานะ คำตอบ (ข้อความ) และลิงก์ไปยัง Google Sheets / Drive
-- ไฟล์แนบเก็บใน Google Drive ไม่เก็บในฐานข้อมูล

create table if not exists public.cust_forms (
  id bigint generated always as identity primary key,
  token uuid not null default gen_random_uuid() unique,
  lead_id bigint,
  kind text not null check (kind in ('book','acc')),
  brand text not null,
  team text,
  sales text,
  company text,
  prefill jsonb not null default '{}'::jsonb,
  status text not null default 'sent' check (status in ('sent','done')),
  answers jsonb,
  files jsonb,
  sheet_url text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  submitted_at timestamptz
);
create index if not exists cust_forms_lead_idx on public.cust_forms(lead_id);
create index if not exists cust_forms_created_idx on public.cust_forms(created_at desc);

alter table public.cust_forms enable row level security;

-- ใครเห็น/แก้ได้: Admin และหัวหน้าเซลล์ทุกทีม, เซลล์เฉพาะทีมตัวเอง
create or replace function public.cust_forms_can(p_team text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (p.role in ('admin','sales_lead') or (p.role = 'sales' and p.team = p_team))
  );
$$;

drop policy if exists cust_forms_staff on public.cust_forms;
create policy cust_forms_staff on public.cust_forms for all to authenticated
  using (public.cust_forms_can(team))
  with check (public.cust_forms_can(team));

-- ลูกค้า (ไม่ล็อกอิน) เข้าถึงได้ผ่าน 2 ฟังก์ชันนี้เท่านั้น ด้วยรหัสในลิงก์
create or replace function public.form_get(p_token uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('kind', kind, 'brand', brand, 'prefill', prefill, 'status', status)
  from public.cust_forms where token = p_token;
$$;

drop function if exists public.form_submit(uuid, jsonb, jsonb, text);
create or replace function public.form_submit(p_token uuid, p_answers jsonb, p_files jsonb, p_sheet text, p_company text default null, p_contact text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.cust_forms
     set status = 'done', answers = p_answers, files = p_files, sheet_url = p_sheet, submitted_at = now(),
         company = coalesce(nullif(p_company, ''), company),
         prefill = prefill || jsonb_build_object('contact', coalesce(p_contact, ''))
   where token = p_token and status = 'sent';
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

revoke all on function public.form_get(uuid) from public;
revoke all on function public.form_submit(uuid, jsonb, jsonb, text, text, text) from public;
grant execute on function public.form_get(uuid) to anon, authenticated;
grant execute on function public.form_submit(uuid, jsonb, jsonb, text, text, text) to anon, authenticated;

-- ===== นำเข้าข้อมูลเก่าจาก Jotform =====
alter table public.cust_forms add column if not exists source text;
alter table public.cust_forms add column if not exists jf_id text;
create unique index if not exists cust_forms_jf_uq on public.cust_forms(jf_id) where jf_id is not null;
alter table public.cust_forms drop constraint if exists cust_forms_kind_check;
alter table public.cust_forms add constraint cust_forms_kind_check check (kind in ('book','acc','job','claim','tc'));

-- ใบสมัครงาน: Admin เท่านั้น
create or replace function public.cust_forms_can2(p_team text, p_kind text)
returns boolean language sql stable security definer set search_path = public as $$
  select case when p_kind = 'job'
    then exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    else public.cust_forms_can(p_team) end;
$$;
drop policy if exists cust_forms_staff on public.cust_forms;
create policy cust_forms_staff on public.cust_forms for all to authenticated
  using (public.cust_forms_can2(team, kind))
  with check (public.cust_forms_can2(team, kind));

-- รหัสลับสำหรับสคริปต์นำเข้า (ตั้งรหัสของคุณเองแทนข้อความด้านล่าง แล้วใส่รหัสเดียวกันใน Script Properties: IMPORT_SECRET)
create table if not exists public.form_admin(secret text not null);
alter table public.form_admin enable row level security;
-- insert into public.form_admin(secret) values ('ตั้งรหัสของคุณ');

create or replace function public.form_import(p_secret text, p_rows jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not exists(select 1 from public.form_admin where secret = p_secret) then raise exception 'denied'; end if;
  insert into public.cust_forms(kind, brand, company, prefill, status, answers, files, sheet_url, created_by, created_at, submitted_at, source, jf_id)
  select r->>'kind', r->>'brand', coalesce(r->>'company',''), jsonb_build_object('contact', coalesce(r->>'contact','')), 'done',
         r->'answers', r->'files', r->>'folder', null, (r->>'at')::timestamptz, (r->>'at')::timestamptz, 'jotform', r->>'jf_id'
  from jsonb_array_elements(p_rows) r
  on conflict (jf_id) where jf_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.form_import(text, jsonb) from public;
grant execute on function public.form_import(text, jsonb) to anon, authenticated;
