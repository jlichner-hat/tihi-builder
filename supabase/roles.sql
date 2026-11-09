-- Roles: who can see which pages.
--   member        = User: Shipment builder only
--   engineer      = Packaging engineer: also Compare box sizes and Box finder
--   company_admin = Admin: everything, and sets the roles of people in their company
-- Site admins (public.app_admins) can do everything for every company.
-- Already part of schema.sql. For a database set up before roles existed, run this file once in the SQL Editor.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('member','engineer','company_admin'));

create or replace function public.set_user_role(uid uuid, new_role text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target_company uuid;
begin
  if new_role not in ('member','engineer','company_admin') then raise exception 'Unknown role.'; end if;
  select company_id into target_company from public.profiles where id = uid;
  if target_company is null then raise exception 'That user wasn''t found.'; end if;
  if not public.is_app_admin() then
    if not exists (select 1 from public.profiles
                   where id = auth.uid() and role = 'company_admin'
                     and company_id = target_company and company_id = public.my_company_id()) then
      raise exception 'Only an admin of this company can change roles.';
    end if;
    if uid = auth.uid() then raise exception 'You can''t change your own role.'; end if;
  end if;
  update public.profiles set role = new_role where id = uid;
end $$;

revoke execute on function public.set_user_role(uuid, text) from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;
