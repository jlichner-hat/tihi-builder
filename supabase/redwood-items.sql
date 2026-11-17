-- Redwood packaging configurator: saved Redwood items (item number, description, packaged size
-- and weight), shared by a company. The Redwood page is for Admins, so only Admins of the company
-- (and site admins) can read, add, change or delete these rows.
-- Already part of schema.sql. For an existing database, run this file once in the SQL Editor.

create or replace function public.is_company_admin() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid())
      or exists (select 1 from public.profiles where id = auth.uid() and role = 'company_admin')
$$;
revoke execute on function public.is_company_admin() from public, anon;
grant execute on function public.is_company_admin() to authenticated;

create table if not exists public.redwood_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_no text not null check (char_length(item_no) between 1 and 80),
  description text not null default '' check (char_length(description) <= 200),
  length_in numeric not null check (length_in > 0),
  width_in numeric not null check (width_in > 0),
  height_in numeric not null check (height_in > 0),
  weight_lb numeric not null default 0 check (weight_lb >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create unique index if not exists redwood_items_company_item on public.redwood_items (company_id, lower(item_no));
create index if not exists redwood_items_updated_by on public.redwood_items (updated_by);

alter table public.redwood_items enable row level security;

drop policy if exists "redwood items read" on public.redwood_items;
create policy "redwood items read" on public.redwood_items for select to authenticated
  using (company_id = (select public.my_company_id()) and (select public.is_company_admin()));
drop policy if exists "redwood items insert" on public.redwood_items;
create policy "redwood items insert" on public.redwood_items for insert to authenticated
  with check (company_id = (select public.my_company_id()) and (select public.is_company_admin()));
drop policy if exists "redwood items update" on public.redwood_items;
create policy "redwood items update" on public.redwood_items for update to authenticated
  using (company_id = (select public.my_company_id()) and (select public.is_company_admin()))
  with check (company_id = (select public.my_company_id()));
drop policy if exists "redwood items delete" on public.redwood_items;
create policy "redwood items delete" on public.redwood_items for delete to authenticated
  using (company_id = (select public.my_company_id()) and (select public.is_company_admin()));
