-- LINE points: who can change points
-- admin, sales head (sales_lead), CEO and marketing: every customer
-- sales: only customers they own (customers.owner = their name)
-- everyone signed in can still read points
-- Safe to run more than once.

create or replace function public.pt_can(cid text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (
        p.role in ('admin','sales_lead','ceo','marketing')
        or (p.role = 'sales' and exists (
              select 1 from public.customers c
              where c.id::text = cid and c.owner = p.name))
      )
  );
$$;

grant execute on function public.pt_can(text) to authenticated;

alter table public.cust_points enable row level security;
drop policy if exists cust_points_rw     on public.cust_points;
drop policy if exists cust_points_read   on public.cust_points;
drop policy if exists cust_points_insert on public.cust_points;
drop policy if exists cust_points_update on public.cust_points;
drop policy if exists cust_points_delete on public.cust_points;

create policy cust_points_read   on public.cust_points for select to authenticated using (true);
create policy cust_points_insert on public.cust_points for insert to authenticated with check (public.pt_can(customer_id));
create policy cust_points_update on public.cust_points for update to authenticated using (public.pt_can(customer_id)) with check (public.pt_can(customer_id));
create policy cust_points_delete on public.cust_points for delete to authenticated using (public.pt_can(customer_id));
