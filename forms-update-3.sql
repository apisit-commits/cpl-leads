-- ฟอร์มเพิ่ม: เคลมสินค้า / ยอมรับข้อตกลงและเงื่อนไข / ใบสมัครงาน (ลิงก์ใบสมัครงานใช้ซ้ำได้ ผู้สมัครแต่ละคนได้รายการใหม่)
alter table public.cust_forms drop constraint if exists cust_forms_kind_check;
alter table public.cust_forms add constraint cust_forms_kind_check check (kind in ('book','acc','job','claim','tc'));

create or replace function public.form_submit(p_token uuid, p_answers jsonb, p_files jsonb, p_sheet text, p_company text default null, p_contact text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare r public.cust_forms; n int;
begin
  select * into r from public.cust_forms where token = p_token and status = 'sent';
  if not found then return false; end if;
  if r.kind = 'job' then
    insert into public.cust_forms(kind, brand, team, sales, company, prefill, status, answers, files, sheet_url, created_by, submitted_at, source)
    values (r.kind, r.brand, r.team, r.sales, coalesce(p_company, ''),
            jsonb_build_object('contact', coalesce(p_contact, ''), 'from', r.id),
            'done', p_answers, p_files, p_sheet, r.created_by, now(), 'apply');
    return true;
  end if;
  update public.cust_forms
     set status = 'done', answers = p_answers, files = p_files, sheet_url = p_sheet, submitted_at = now(),
         company = coalesce(nullif(p_company, ''), company),
         prefill = prefill || jsonb_build_object('contact', coalesce(p_contact, ''))
   where id = r.id and status = 'sent';
  get diagnostics n = row_count;
  return n > 0;
end;
$$;
revoke all on function public.form_submit(uuid, jsonb, jsonb, text, text, text) from public;
grant execute on function public.form_submit(uuid, jsonb, jsonb, text, text, text) to anon, authenticated;

-- ส่งฟอร์มเร็วขึ้น: บันทึกคำตอบทันที แล้วสคริปต์ Google แนบลิงก์ไฟล์/ชีตตามมา
create or replace function public.form_get(p_token uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('kind', kind, 'brand', brand, 'prefill', prefill, 'status', status,
         'synced', sheet_url is not null and kind <> 'job')
  from public.cust_forms where token = p_token;
$$;

create or replace function public.form_attach(p_token uuid, p_files jsonb, p_sheet text)
returns boolean language plpgsql security definer set search_path = public as $$
declare r public.cust_forms; n int;
begin
  select * into r from public.cust_forms where token = p_token;
  if not found then return false; end if;
  if r.kind = 'job' then
    update public.cust_forms set files = p_files, sheet_url = p_sheet
     where id = (select id from public.cust_forms where source = 'apply' and (prefill->>'from')::bigint = r.id
                   and sheet_url is null order by submitted_at desc limit 1);
  else
    update public.cust_forms set files = p_files, sheet_url = p_sheet
     where id = r.id and status = 'done' and sheet_url is null;
  end if;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;
revoke all on function public.form_attach(uuid, jsonb, text) from public;
grant execute on function public.form_attach(uuid, jsonb, text) to anon, authenticated;
