-- Black Canvas team portal: database setup for Supabase.
-- Run once in your Supabase project: SQL Editor > New query > paste this file > Run.
-- Safe to run again; it only creates what is missing and refreshes the rules.
-- After the first run, add yourself as the first admin (see the end of this file).

-- 1. Who may use which app. One row per person, managed from the portal's
--    Team access screen by admins. Apps: billing, crew, projects.
create table if not exists public.portal_access (
  email      text        primary key check (email = lower(email)),
  apps       text[]      not null default '{}' check (apps <@ array['billing', 'crew', 'projects']::text[]),
  is_admin   boolean     not null default false,
  note       text,
  updated_at timestamptz not null default now(),
  updated_by uuid                 default auth.uid()
);

-- 2. Billing data (documents, clients, rate card, settings).
create table if not exists public.records (
  coll       text        not null check (coll in ('docs', 'clients', 'rates', 'settings')),
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid                 default auth.uid(),
  primary key (coll, id)
);

-- 3. Access checks, used by the rules below and by the portal pages.
create or replace function public.has_app(p_app text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.portal_access a
    where a.email = lower(auth.jwt() ->> 'email') and p_app = any (a.apps)
  );
$$;

create or replace function public.is_portal_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.portal_access a
    where a.email = lower(auth.jwt() ->> 'email') and a.is_admin
  );
$$;

create or replace function public.my_access()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'apps', coalesce((select a.apps from public.portal_access a where a.email = lower(auth.jwt() ->> 'email')), '{}'::text[]),
    'is_admin', coalesce((select a.is_admin from public.portal_access a where a.email = lower(auth.jwt() ->> 'email')), false)
  );
$$;

revoke execute on function public.has_app(text)       from public, anon;
revoke execute on function public.is_portal_admin()   from public, anon;
revoke execute on function public.my_access()         from public, anon;
grant  execute on function public.has_app(text)       to authenticated;
grant  execute on function public.is_portal_admin()   to authenticated;
grant  execute on function public.my_access()         to authenticated;

-- 4. Stamp who changed a row and when.
create or replace function public.touch_record()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
  for each row execute function public.touch_record();

drop trigger if exists portal_access_touch on public.portal_access;
create trigger portal_access_touch before insert or update on public.portal_access
  for each row execute function public.touch_record();

-- 5. Never leave the portal without an admin.
create or replace function public.portal_access_keep_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.portal_access where is_admin) then
    raise exception 'The portal needs at least one admin. Make someone else an admin first.' using errcode = 'P0001';
  end if;
  return null;
end;
$$;

drop trigger if exists portal_access_keep_admin on public.portal_access;
create trigger portal_access_keep_admin after update or delete on public.portal_access
  for each statement execute function public.portal_access_keep_admin();

-- 6. Access rules.
alter table public.records       enable row level security;
alter table public.portal_access enable row level security;

revoke all on public.records       from anon;
revoke all on public.portal_access from anon;
grant select, insert, update, delete on public.records       to authenticated;
grant select, insert, update, delete on public.portal_access to authenticated;

-- Billing data: only people with the billing app.
drop policy if exists "team can read"     on public.records;
drop policy if exists "team can add"      on public.records;
drop policy if exists "team can change"   on public.records;
drop policy if exists "team can delete"   on public.records;
drop policy if exists "billing can read"   on public.records;
drop policy if exists "billing can add"    on public.records;
drop policy if exists "billing can change" on public.records;
drop policy if exists "billing can delete" on public.records;
create policy "billing can read"   on public.records for select to authenticated using (public.has_app('billing'));
create policy "billing can add"    on public.records for insert to authenticated with check (public.has_app('billing'));
create policy "billing can change" on public.records for update to authenticated using (public.has_app('billing')) with check (public.has_app('billing'));
create policy "billing can delete" on public.records for delete to authenticated using (public.has_app('billing'));

-- Access list: everyone sees their own row; admins see and change all rows.
drop policy if exists "see own access or admin" on public.portal_access;
drop policy if exists "admins add access"       on public.portal_access;
drop policy if exists "admins change access"    on public.portal_access;
drop policy if exists "admins remove access"    on public.portal_access;
create policy "see own access or admin" on public.portal_access for select to authenticated
  using (email = lower(auth.jwt() ->> 'email') or public.is_portal_admin());
create policy "admins add access"    on public.portal_access for insert to authenticated with check (public.is_portal_admin());
create policy "admins change access" on public.portal_access for update to authenticated using (public.is_portal_admin()) with check (public.is_portal_admin());
create policy "admins remove access" on public.portal_access for delete to authenticated using (public.is_portal_admin());

revoke execute on function public.portal_access_keep_admin() from public, anon, authenticated;

-- 7. Retire the first version's domain-wide access.
drop function if exists public.is_portal_member();
drop table if exists public.portal_members;

-- 8. Live updates for billing.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'records'
  ) then
    alter publication supabase_realtime add table public.records;
  end if;
end $$;

-- First admin (run once, with your own email):
-- insert into public.portal_access (email, apps, is_admin)
-- values ('you@blackcanvasglobal.com', array['billing','crew','projects'], true)
-- on conflict (email) do update set apps = excluded.apps, is_admin = true;
