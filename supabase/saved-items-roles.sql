-- Saved items: everyone in a company can add them, but only Packaging engineers and Admins
-- (and site admins) can change or delete them.
-- Already part of schema.sql. For an existing database, run this file once in the SQL Editor.

create or replace function public.can_manage_items() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select public.is_app_admin() or exists (select 1 from public.profiles
    where id = auth.uid() and role in ('engineer','company_admin'))
$$;
revoke execute on function public.can_manage_items() from public, anon;
grant execute on function public.can_manage_items() to authenticated;

drop policy if exists "company items update" on public.items;
create policy "company items update" on public.items for update to authenticated
  using (company_id = (select public.my_company_id()) and (select public.can_manage_items()))
  with check (company_id = (select public.my_company_id()));

drop policy if exists "company items delete" on public.items;
create policy "company items delete" on public.items for delete to authenticated
  using (company_id = (select public.my_company_id()) and (select public.can_manage_items()));
