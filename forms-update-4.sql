-- แท็บฟอร์มดีไซน์ใหม่: จำว่าคำตอบไหนเปิดดูแล้ว (ป้าย "ใหม่")
alter table public.cust_forms add column if not exists seen_at timestamptz;
-- ข้อมูลเก่าจาก Jotform ถือว่าเปิดดูแล้ว
update public.cust_forms set seen_at = coalesce(submitted_at, created_at) where source = 'jotform' and seen_at is null;

create or replace function public.form_import(p_secret text, p_rows jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not exists(select 1 from public.form_admin where secret = p_secret) then raise exception 'denied'; end if;
  insert into public.cust_forms(kind, brand, company, prefill, status, answers, files, sheet_url, created_by, created_at, submitted_at, source, jf_id, seen_at)
  select r->>'kind', r->>'brand', coalesce(r->>'company',''), jsonb_build_object('contact', coalesce(r->>'contact','')), 'done',
         r->'answers', r->'files', r->>'folder', null, (r->>'at')::timestamptz, (r->>'at')::timestamptz, 'jotform', r->>'jf_id', (r->>'at')::timestamptz
  from jsonb_array_elements(p_rows) r
  on conflict (jf_id) where jf_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
