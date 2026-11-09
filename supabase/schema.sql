-- Ti:Hi Builder database: companies, user profiles, and a private item library per company.
-- Paste all of this into Supabase > SQL Editor > New query, then click Run. Run it once.

create extension if not exists citext with schema extensions;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email_domain extensions.citext not null unique,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username extensions.citext not null unique check (char_length(username) between 3 and 40),
  email extensions.citext not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  role text not null default 'member' check (role in ('member','engineer','company_admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  length_in numeric not null check (length_in > 0),
  width_in numeric not null check (width_in > 0),
  height_in numeric not null check (height_in > 0),
  weight_lb numeric not null default 0 check (weight_lb >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create unique index if not exists items_company_name on public.items (company_id, lower(name));
create index if not exists items_updated_by on public.items (updated_by);
create index if not exists profiles_company on public.profiles (company_id);

-- Site admins (you) approve new companies.
create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- Free email providers can't identify a company, so sign-ups from them are refused.
create table if not exists public.blocked_domains (domain extensions.citext primary key);
insert into public.blocked_domains(domain) values
  ('gmail.com'),('googlemail.com'),('yahoo.com'),('hotmail.com'),('outlook.com'),('live.com'),
  ('msn.com'),('aol.com'),('icloud.com'),('me.com'),('mac.com'),('proton.me'),('protonmail.com'),
  ('gmx.com'),('mail.com'),('yandex.com'),('zoho.com')
on conflict do nothing;

create or replace function public.my_company_id() returns uuid
language sql stable security definer set search_path = public, extensions as $$
  select p.company_id from public.profiles p join public.companies c on c.id = p.company_id
  where p.id = auth.uid() and c.status = 'approved'
$$;

create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid())
$$;

-- On sign-up: match the email domain to a company (or create a pending one) and make the profile.
-- Accounts created by hand in the Supabase dashboard have no username or company:
-- the email name becomes the username and the email domain picks the company.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  dom text := lower(split_part(new.email, '@', 2));
  comp_id uuid;
  is_new boolean := false;
  uname text := nullif(trim(new.raw_user_meta_data->>'username'), '');
  cname text := nullif(trim(new.raw_user_meta_data->>'company'), '');
  base text;
  n int := 1;
begin
  if exists (select 1 from public.blocked_domains where domain = dom::extensions.citext) then
    raise exception 'Please sign up with your company email address, not a personal one.';
  end if;

  if uname is null then
    base := left(regexp_replace(split_part(new.email, '@', 1), '[^A-Za-z0-9._-]', '', 'g'), 36);
    if char_length(base) < 3 then base := base || 'user'; end if;
    uname := base;
    while exists (select 1 from public.profiles where username = uname::extensions.citext) loop
      n := n + 1; uname := base || n;
    end loop;
  end if;

  select id into comp_id from public.companies where email_domain = dom::extensions.citext;
  if comp_id is null then
    insert into public.companies(name, email_domain) values (coalesce(cname, initcap(split_part(dom, '.', 1))), dom) returning id into comp_id;
    is_new := true;
  end if;

  insert into public.profiles(id, username, email, company_id, role)
  values (new.id, uname, new.email, comp_id, case when is_new then 'company_admin' else 'member' end);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Lets the sign-up form check a username before submitting.
create or replace function public.username_available(u text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select not exists (select 1 from public.profiles where username = u::extensions.citext)
$$;
grant execute on function public.username_available(text) to anon, authenticated;

-- Site admin approves or rejects a company.
create or replace function public.set_company_status(cid uuid, new_status text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_app_admin() then raise exception 'Only site admins can approve companies.'; end if;
  if new_status not in ('approved','rejected','pending') then raise exception 'Bad status'; end if;
  update public.companies set status = new_status,
    approved_at = case when new_status = 'approved' then now() else null end
  where id = cid;
end $$;

-- Row level security: each company only ever sees its own rows.
alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.app_admins enable row level security;
alter table public.blocked_domains enable row level security;

drop policy if exists "see own company" on public.companies;
create policy "see own company" on public.companies for select to authenticated
  using (id = (select company_id from public.profiles where id = (select auth.uid())) or (select public.is_app_admin()));

drop policy if exists "see own and coworkers" on public.profiles;
create policy "see own and coworkers" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or company_id = (select public.my_company_id()) or (select public.is_app_admin()));

drop policy if exists "company items read" on public.items;
create policy "company items read" on public.items for select to authenticated
  using (company_id = (select public.my_company_id()));
drop policy if exists "company items insert" on public.items;
create policy "company items insert" on public.items for insert to authenticated
  with check (company_id = (select public.my_company_id()));
drop policy if exists "company items update" on public.items;
create policy "company items update" on public.items for update to authenticated
  using (company_id = (select public.my_company_id())) with check (company_id = (select public.my_company_id()));
drop policy if exists "company items delete" on public.items;
create policy "company items delete" on public.items for delete to authenticated
  using (company_id = (select public.my_company_id()));

drop policy if exists "see own admin row" on public.app_admins;
create policy "see own admin row" on public.app_admins for select to authenticated
  using (user_id = (select auth.uid()));
-- blocked_domains has no policies, so only the database itself reads it.

-- Lock down functions that shouldn't be called directly by the public API.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.set_company_status(uuid, text) from public, anon;
grant execute on function public.set_company_status(uuid, text) to authenticated;
-- Admins set roles: User (member), Packaging engineer (engineer), Admin (company_admin).
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

revoke execute on function public.my_company_id() from public, anon;
revoke execute on function public.is_app_admin() from public, anon;
grant execute on function public.my_company_id() to authenticated;
grant execute on function public.is_app_admin() to authenticated;
