-- Redwood: saved results (bill of materials, overpack size, yearly quantity, Ti:Hi and best boxes),
-- kept for later use. Only Admins of the company (and site admins) can read, add or remove them.
-- Already part of schema.sql. For an existing database, run this file once in the SQL Editor
-- of the site's Supabase project.

create table if not exists public.redwood_results (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  yearly_qty integer check (yearly_qty is null or yearly_qty >= 0),
  pieces integer not null default 0,
  contents_lb numeric not null default 0,
  inside_l numeric, inside_w numeric, inside_h numeric,
  wall_in numeric, outside_l numeric, outside_w numeric, outside_h numeric,
  fill_pct numeric,
  tihi text, per_pallet integer,
  best_company_box text, best_uline_box text,
  settings jsonb not null default '{}'::jsonb,
  bom jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists redwood_results_company on public.redwood_results (company_id, created_at desc);
create index if not exists redwood_results_created_by on public.redwood_results (created_by);

alter table public.redwood_results enable row level security;

drop policy if exists "redwood results read" on public.redwood_results;
create policy "redwood results read" on public.redwood_results for select to authenticated
  using (company_id = (select public.my_company_id())
    and ((select exists (select 1 from public.app_admins where user_id = auth.uid()))
      or (select exists (select 1 from public.profiles where id = auth.uid() and role = 'company_admin'))));
drop policy if exists "redwood results insert" on public.redwood_results;
create policy "redwood results insert" on public.redwood_results for insert to authenticated
  with check (company_id = (select public.my_company_id())
    and ((select exists (select 1 from public.app_admins where user_id = auth.uid()))
      or (select exists (select 1 from public.profiles where id = auth.uid() and role = 'company_admin'))));
drop policy if exists "redwood results delete" on public.redwood_results;
create policy "redwood results delete" on public.redwood_results for delete to authenticated
  using (company_id = (select public.my_company_id())
    and ((select exists (select 1 from public.app_admins where user_id = auth.uid()))
      or (select exists (select 1 from public.profiles where id = auth.uid() and role = 'company_admin'))));
