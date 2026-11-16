-- Admin creates user accounts directly (works while "Allow new users to sign up" is off)
create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_create_user(
  p_email text, p_password text, p_name text default null, p_role text default 'sales', p_team text default null
) returns uuid
language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare uid uuid := gen_random_uuid(); em text := lower(trim(p_email));
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not allowed';
  end if;
  if em is null or em = '' or position('@' in em) = 0 then raise exception 'invalid email'; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'password too short'; end if;
  if exists (select 1 from auth.users where lower(email) = em) then raise exception 'email exists'; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
    extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());

  insert into public.profiles (id, name, role, team)
  values (uid, nullif(trim(p_name),''), p_role, nullif(p_team,''))
  on conflict (id) do update set name = excluded.name, role = excluded.role, team = excluded.team;

  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='email') then
    execute 'update public.profiles set email = $1 where id = $2' using em, uid;
  end if;
  return uid;
end $$;

revoke all on function public.admin_create_user(text,text,text,text,text) from public, anon;
grant execute on function public.admin_create_user(text,text,text,text,text) to authenticated;
