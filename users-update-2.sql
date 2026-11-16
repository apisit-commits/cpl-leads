-- Allow team C (Offline Team) wherever a team check exists (profiles, options, etc.)
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname
    from pg_constraint c join pg_namespace n on n.oid = c.connamespace
    where n.nspname = 'public' and c.contype = 'c' and c.conname like '%team_check%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I check (team is null or team in (''A'',''B'',''C''))', r.tbl, r.conname);
  end loop;
end $$;
