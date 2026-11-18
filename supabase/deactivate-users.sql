-- Deactivate / reactivate user accounts.
-- A deactivated user keeps their profile and everything they saved, but the database refuses them:
-- they can't read or change their company's saved items, label items, Redwood results or coworkers,
-- can't change roles or approve companies, and (where Supabase allows it) can't sign in again.
-- Admins of a company can deactivate people in their company; site admins can deactivate anyone.
-- Nobody can deactivate themselves, and only a site admin can deactivate another site admin.
-- Already part of schema.sql. For an existing database, run this file once in the SQL Editor
-- of the site's Supabase project.

alter table public.profiles add column if not exists active boolean not null default true;
alter table public.profiles add column if not exists deactivated_at timestamptz;
alter table public.profiles add column if not exists deactivated_by uuid references auth.users(id) on delete set null;
create index if not exists profiles_deactivated_by on public.profiles (deactivated_by);

-- Every company rule (saved items, label items, Redwood results, seeing coworkers, setting roles)
-- goes through my_company_id(), so a deactivated user gets no company at all.
create or replace function public.my_company_id() returns uuid
language sql stable security definer set search_path = public, extensions as $$
  select p.company_id from public.profiles p join public.companies c on c.id = p.company_id
  where p.id = auth.uid() and c.status = 'approved' and p.active
$$;

-- A deactivated site admin loses site admin powers too.
create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid())
    and not exists (select 1 from public.profiles where id = auth.uid() and not active)
$$;

create or replace function public.can_manage_items() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select public.is_app_admin() or exists (select 1 from public.profiles
    where id = auth.uid() and active and role in ('engineer','company_admin'))
$$;

create or replace function public.set_user_active(uid uuid, make_active boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target_company uuid;
begin
  if uid = auth.uid() then raise exception 'You can''t deactivate or reactivate your own account.'; end if;
  select company_id into target_company from public.profiles where id = uid;
  if target_company is null then raise exception 'That user wasn''t found.'; end if;
  if not public.is_app_admin() then
    if not exists (select 1 from public.profiles
                   where id = auth.uid() and role = 'company_admin' and active
                     and company_id = target_company and company_id = public.my_company_id()) then
      raise exception 'Only an admin of this company can deactivate or reactivate accounts.';
    end if;
    if exists (select 1 from public.app_admins where user_id = uid) then
      raise exception 'Only a site admin can deactivate or reactivate a site admin.';
    end if;
  end if;

  update public.profiles
     set active = make_active,
         deactivated_at = case when make_active then null else now() end,
         deactivated_by = case when make_active then null else auth.uid() end
   where id = uid;

  -- Also ban the sign-in and end their open sessions, so they can't sign in or refresh a session.
  -- The database rules above already block them; this is a second lock where Supabase permits it.
  begin
    update auth.users set banned_until = case when make_active then null else now() + interval '100 years' end
     where id = uid;
    if not make_active then delete from auth.sessions where user_id = uid; end if;
  exception when others then
    null;
  end;
end $$;

revoke execute on function public.set_user_active(uuid, boolean) from public, anon;
grant execute on function public.set_user_active(uuid, boolean) to authenticated;
