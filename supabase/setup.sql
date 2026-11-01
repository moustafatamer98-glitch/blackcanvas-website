-- Black Canvas team portal: database setup for Supabase.
-- Run once in your Supabase project: SQL Editor > New query > paste this file > Run.
-- Safe to run again; it only creates what is missing and refreshes the rules.

-- 1. Everything the billing app stores (documents, clients, rate card, settings).
create table if not exists public.records (
  coll       text        not null check (coll in ('docs', 'clients', 'rates', 'settings')),
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid                 default auth.uid(),
  primary key (coll, id)
);

-- 2. People without a @blackcanvasglobal.com address who may use the portal
--    (freelancers, partners). Add their email here in Table Editor.
create table if not exists public.portal_members (
  email    text        primary key,
  note     text,
  added_at timestamptz not null default now()
);

-- 3. Who counts as team: any signed-in @blackcanvasglobal.com account,
--    plus the emails listed in portal_members.
create or replace function public.is_portal_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    lower(auth.jwt() ->> 'email') like '%@blackcanvasglobal.com'
    or exists (
      select 1 from public.portal_members m
      where lower(m.email) = lower(auth.jwt() ->> 'email')
    ),
    false
  );
$$;

-- 4. Stamp who changed a record and when.
create or replace function public.touch_record()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists records_touch on public.records;
create trigger records_touch
  before insert or update on public.records
  for each row execute function public.touch_record();

-- 5. Access rules: nobody signed out sees anything; only team members read or write.
alter table public.records        enable row level security;
alter table public.portal_members enable row level security;

revoke all on public.records        from anon;
revoke all on public.portal_members from anon, authenticated;
grant select, insert, update, delete on public.records to authenticated;

drop policy if exists "team can read"   on public.records;
drop policy if exists "team can add"    on public.records;
drop policy if exists "team can change" on public.records;
drop policy if exists "team can delete" on public.records;

create policy "team can read"   on public.records for select to authenticated using (public.is_portal_member());
create policy "team can add"    on public.records for insert to authenticated with check (public.is_portal_member());
create policy "team can change" on public.records for update to authenticated using (public.is_portal_member()) with check (public.is_portal_member());
create policy "team can delete" on public.records for delete to authenticated using (public.is_portal_member());

-- 6. Live updates, so everyone's screen refreshes when someone saves.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'records'
  ) then
    alter publication supabase_realtime add table public.records;
  end if;
end $$;
