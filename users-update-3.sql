-- Admin can see the password they set and change any user's password
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.user_pw (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pw text not null,
  updated_at timestamptz not null default now()
);
alter table public.user_pw enable row level security;
drop policy if exists user_pw_admin on public.user_pw;
create policy user_pw_admin on public.user_pw for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

create or replace function public.admin_set_password(p_uid uuid, p_password text) returns void
language plpgsql security definer
set search_path = public, auth, extensions
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not allowed';
  end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'password too short'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = p_uid;
  if not found then raise exception 'user not found'; end if;
  insert into public.user_pw (user_id, pw, updated_at) values (p_uid, p_password, now())
  on conflict (user_id) do update set pw = excluded.pw, updated_at = now();
end $$;

revoke all on function public.admin_set_password(uuid,text) from public, anon;
grant execute on function public.admin_set_password(uuid,text) to authenticated;
