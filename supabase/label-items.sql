-- Multi box label: saved item numbers, descriptions and weights, shared by everyone in a company.
-- Same rules as saved items: everyone can add, only Packaging engineers and Admins (and site admins)
-- can change or delete. Already part of schema.sql. For an existing database, run this file once.

create table if not exists public.label_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_no text not null check (char_length(item_no) between 1 and 80),
  description text not null default '' check (char_length(description) <= 200),
  weight_lb numeric check (weight_lb is null or weight_lb >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create unique index if not exists label_items_company_item on public.label_items (company_id, lower(item_no));
create index if not exists label_items_updated_by on public.label_items (updated_by);

alter table public.label_items enable row level security;

drop policy if exists "company label items read" on public.label_items;
create policy "company label items read" on public.label_items for select to authenticated
  using (company_id = (select public.my_company_id()));
drop policy if exists "company label items insert" on public.label_items;
create policy "company label items insert" on public.label_items for insert to authenticated
  with check (company_id = (select public.my_company_id()));
drop policy if exists "company label items update" on public.label_items;
create policy "company label items update" on public.label_items for update to authenticated
  using (company_id = (select public.my_company_id()) and (select public.can_manage_items()))
  with check (company_id = (select public.my_company_id()));
drop policy if exists "company label items delete" on public.label_items;
create policy "company label items delete" on public.label_items for delete to authenticated
  using (company_id = (select public.my_company_id()) and (select public.can_manage_items()));
