-- Black Canvas team portal: database setup for Supabase.
-- Run once in your Supabase project: SQL Editor > New query > paste this file > Run.
-- Safe to run again; it only creates what is missing and refreshes the rules.
-- After the first run, add yourself as the first admin (see the end of this file).

-- 1. Who may use which app. One row per person, managed from the portal's
--    Team access screen by admins. Apps: billing, crew, projects, bills, staff.
create table if not exists public.portal_access (
  email      text        primary key check (email = lower(email)),
  apps       text[]      not null default '{}' check (apps <@ array['billing', 'crew', 'projects', 'bills', 'staff']::text[]),
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

-- 9. Projects app (portal/projects/): events, tasks, production schedules, contacts and
--    templates, stored like billing as one row per item. Only people with the
--    "projects" app can read or change them.
create table if not exists public.pm_records (
  coll       text        not null check (coll = any (array['projects','tasks','schedule','contacts','templates','settings'])),
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid        default auth.uid(),
  primary key (coll, id)
);
create index if not exists pm_records_project_idx on public.pm_records ((data->>'projectId'));
alter table public.pm_records enable row level security;

drop policy if exists "projects can read"   on public.pm_records;
drop policy if exists "projects can add"    on public.pm_records;
drop policy if exists "projects can change" on public.pm_records;
drop policy if exists "projects can delete" on public.pm_records;
create policy "projects can read"   on public.pm_records for select to authenticated using (public.has_app('projects'));
create policy "projects can add"    on public.pm_records for insert to authenticated with check (public.has_app('projects'));
create policy "projects can change" on public.pm_records for update to authenticated using (public.has_app('projects')) with check (public.has_app('projects'));
create policy "projects can delete" on public.pm_records for delete to authenticated using (public.has_app('projects'));

drop trigger if exists pm_records_touch on public.pm_records;
create trigger pm_records_touch before insert or update on public.pm_records
  for each row execute function public.touch_record();

-- People who can be given tasks: only callable by, and only lists, people with Projects access.
create or replace function public.pm_team()
returns table (email text, note text)
language sql stable security definer set search_path = public
as $$
  select a.email, a.note from public.portal_access a
  where public.has_app('projects') and 'projects' = any (a.apps)
  order by a.email;
$$;
revoke all on function public.pm_team() from public, anon;
grant execute on function public.pm_team() to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pm_records'
  ) then
    alter publication supabase_realtime add table public.pm_records;
  end if;
end $$;

-- 10. Crew assignment app (portal/crew/): crew roster, crew-only jobs, shifts and who is
--     booked on each shift, stored like the other apps as one row per item. Only people with
--     the "crew" app can read or change them.
create table if not exists public.crew_records (
  coll       text        not null check (coll = any (array['crew','events','shifts','assign','settings'])),
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid        default auth.uid(),
  primary key (coll, id)
);
create index if not exists crew_records_event_idx on public.crew_records ((data->>'eventId'));
alter table public.crew_records enable row level security;
revoke all on public.crew_records from anon;
grant select, insert, update, delete on public.crew_records to authenticated;

drop policy if exists "crew can read"   on public.crew_records;
drop policy if exists "crew can add"    on public.crew_records;
drop policy if exists "crew can change" on public.crew_records;
drop policy if exists "crew can delete" on public.crew_records;
create policy "crew can read"   on public.crew_records for select to authenticated using (public.has_app('crew'));
create policy "crew can add"    on public.crew_records for insert to authenticated with check (public.has_app('crew'));
create policy "crew can change" on public.crew_records for update to authenticated using (public.has_app('crew')) with check (public.has_app('crew'));
create policy "crew can delete" on public.crew_records for delete to authenticated using (public.has_app('crew'));

drop trigger if exists crew_records_touch on public.crew_records;
create trigger crew_records_touch before insert or update on public.crew_records
  for each row execute function public.touch_record();

-- Events from the Projects app, so crew can be planned on them without Projects access.
-- Only the basics (name, client, venue, city, code, status, type, dates) and only for
-- people with the "crew" app.
create or replace function public.crew_events()
returns table (id text, data jsonb)
language sql stable security definer set search_path = public
as $$
  select r.id, jsonb_build_object(
    'id', r.id, 'name', r.data->'name', 'client', r.data->'client', 'venue', r.data->'venue',
    'city', r.data->'city', 'code', r.data->'code', 'status', r.data->'status',
    'type', r.data->'type', 'dates', r.data->'dates')
  from public.pm_records r
  where public.has_app('crew') and r.coll = 'projects';
$$;
revoke all on function public.crew_events() from public, anon;
grant execute on function public.crew_events() to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'crew_records'
  ) then
    alter publication supabase_realtime add table public.crew_records;
  end if;
end $$;

-- 11. Bills app (portal/bills/): bills Black Canvas pays (suppliers, freelancers, rent,
--     subscriptions...) with an approve-then-pay flow, receipts, recurring bills and
--     reminders, plus chasing unpaid client invoices from Billing. Stored like the other
--     apps as one row per item. Only people with the "bills" app can read or change them;
--     only portal admins can approve or reject bills.

-- Allow "bills" as an app on the access list.
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.portal_access'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%apps%'
  loop execute format('alter table public.portal_access drop constraint %I', c); end loop;
  alter table public.portal_access add constraint portal_access_apps_check
    check (apps <@ array['billing', 'crew', 'projects', 'bills']::text[]);
end $$;

create table if not exists public.bills_records (
  coll       text        not null check (coll = any (array['bills','vendors','chase','settings'])),
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid        default auth.uid(),
  primary key (coll, id)
);
create index if not exists bills_records_due_idx on public.bills_records ((data->>'dueDate')) where coll = 'bills';
alter table public.bills_records enable row level security;
revoke all on public.bills_records from anon;
grant select, insert, update, delete on public.bills_records to authenticated;

drop policy if exists "bills can read"   on public.bills_records;
drop policy if exists "bills can add"    on public.bills_records;
drop policy if exists "bills can change" on public.bills_records;
drop policy if exists "bills can delete" on public.bills_records;
create policy "bills can read"   on public.bills_records for select to authenticated using (public.has_app('bills'));
create policy "bills can add"    on public.bills_records for insert to authenticated with check (public.has_app('bills'));
create policy "bills can change" on public.bills_records for update to authenticated using (public.has_app('bills')) with check (public.has_app('bills'));
-- Approved and paid bills can only be deleted by admins (others can void a pending bill).
create policy "bills can delete" on public.bills_records for delete to authenticated using (
  public.has_app('bills') and (coll <> 'bills' or public.is_portal_admin()
    or coalesce(data->>'status', 'pending') in ('pending', 'rejected', 'void')));

drop trigger if exists bills_records_touch on public.bills_records;
create trigger bills_records_touch before insert or update on public.bills_records
  for each row execute function public.touch_record();

-- The approval rules, enforced by the database so they hold whatever the page does.
create or replace function public.bills_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  adm  boolean := public.is_portal_admin();
  who  text    := lower(coalesce(auth.jwt() ->> 'email', ''));
  st   text    := coalesce(new.data->>'status', 'pending');
  was  text;
  now_ text    := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  npay int     := jsonb_array_length(coalesce(new.data->'payments', '[]'::jsonb));
begin
  if new.coll <> 'bills' then return new; end if;
  if st not in ('pending', 'approved', 'rejected', 'paid', 'void') then
    raise exception 'Unknown bill status "%".', st using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    was := null;
    if st <> 'pending' and st <> 'void' and not adm then
      raise exception 'New bills start as "awaiting approval". Only an approver can add one already approved.' using errcode = 'P0001';
    end if;
    if npay > 0 and st not in ('approved', 'paid') then
      raise exception 'Approve this bill before recording a payment.' using errcode = 'P0001';
    end if;
  else
    was := coalesce(old.data->>'status', 'pending');
    if st is distinct from was then
      if st in ('approved', 'rejected') and not adm then
        raise exception 'Only an approver can approve or reject bills.' using errcode = 'P0001';
      end if;
      if st = 'paid' and was <> 'approved' then
        raise exception 'Approve this bill before marking it paid.' using errcode = 'P0001';
      end if;
      if was in ('approved', 'paid') and not adm and st <> 'paid' then
        raise exception 'Only an approver can change a bill once it is approved.' using errcode = 'P0001';
      end if;
    end if;
    if not adm and was in ('approved', 'paid') and (
         new.data->'amount'    is distinct from old.data->'amount'
      or new.data->>'currency' is distinct from old.data->>'currency'
      or new.data->>'vendorId' is distinct from old.data->>'vendorId') then
      raise exception 'The amount, currency or supplier of an approved bill can only be changed by an approver.' using errcode = 'P0001';
    end if;
    if st in ('pending', 'rejected', 'void') and npay > jsonb_array_length(coalesce(old.data->'payments', '[]'::jsonb)) then
      raise exception 'Approve this bill before recording a payment.' using errcode = 'P0001';
    end if;
  end if;
  -- Stamp who approved, rejected or settled it (not trusted from the page).
  if st is distinct from was then
    if st = 'approved' then new.data := new.data || jsonb_build_object('approvedBy', who, 'approvedAt', now_);
    elsif st = 'rejected' then new.data := new.data || jsonb_build_object('rejectedBy', who, 'rejectedAt', now_);
    elsif st = 'paid' then new.data := new.data || jsonb_build_object('paidBy', who, 'paidAt', now_);
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function public.bills_guard() from public, anon, authenticated;
drop trigger if exists bills_records_guard on public.bills_records;
create trigger bills_records_guard before insert or update on public.bills_records
  for each row execute function public.bills_guard();

-- Numbers typed into Billing documents, read the same way the Billing page reads them.
create or replace function public.bc_num(t text)
returns numeric language sql immutable set search_path = public as $$
  select case when t ~ '^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?\s*$' then t::numeric else null end;
$$;

-- Totals of a Billing document (same maths as totals() in portal/billing/index.html).
create or replace function public.bc_invoice_totals(d jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  s jsonb; it jsonb; items numeric := 0; sec numeric; subtotal numeric; disc numeric; taxable numeric;
  rate numeric; vat numeric; total numeric; paid numeric; days numeric;
begin
  for s in select * from jsonb_array_elements(coalesce(d->'sections', '[]'::jsonb)) loop
    if bc_num(s->>'totalOverride') is not null then
      sec := round(bc_num(s->>'totalOverride'), 2);
    else
      sec := 0;
      for it in select * from jsonb_array_elements(coalesce(s->'items', '[]'::jsonb)) loop
        days := case when coalesce(it->>'days', '') = '' then 1 else coalesce(bc_num(it->>'days'), 0) end;
        sec := sec + round(coalesce(bc_num(it->>'qty'), 0) * days * coalesce(bc_num(it->>'rate'), 0), 2);
      end loop;
      sec := round(sec, 2);
    end if;
    items := items + sec;
  end loop;
  items := round(items, 2);
  subtotal := coalesce(round(bc_num(d->>'subtotalOverride'), 2), items);
  disc := case when d->'discount'->>'type' = 'amt' then round(coalesce(bc_num(d->'discount'->>'value'), 0), 2)
               else round(subtotal * coalesce(bc_num(d->'discount'->>'value'), 0) / 100, 2) end;
  taxable := round(subtotal - disc, 2);
  rate := case when coalesce(d->>'vatRate', '') = '' then 15 else coalesce(bc_num(d->>'vatRate'), 0) end;
  vat := round(taxable * rate / 100, 2);
  total := round(taxable + vat, 2);
  paid := round(coalesce(bc_num(d->>'amountPaid'), 0), 2);
  return jsonb_build_object('total', total, 'paid', paid, 'due', round(total - paid, 2));
end;
$$;

-- Unpaid client invoices from Billing, for chasing in the Bills app. Only the basics,
-- and only for people with the "bills" app.
create or replace function public.bills_receivables()
returns table (id text, data jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, jsonb_build_object(
    'id', r.id, 'number', r.data->'number', 'issueDate', r.data->'issueDate', 'dueDate', r.data->'dueDate',
    'currency', coalesce(r.data->>'currency', (select s.data->>'currency' from public.records s where s.coll = 'settings' limit 1), 'SAR'),
    'project', r.data->'project', 'company', r.data->'client'->'company', 'contact', r.data->'client'->'contact',
    'email', r.data->'client'->'email', 'phone', r.data->'client'->'phone') || public.bc_invoice_totals(r.data)
  from public.records r
  where public.has_app('bills') and r.coll = 'docs' and r.data->>'type' = 'invoice' and r.data->>'status' = 'sent';
$$;
revoke all on function public.bills_receivables() from public, anon;
grant execute on function public.bills_receivables() to authenticated;

-- Events from the Projects app, so bills can be linked to an event.
create or replace function public.bills_events()
returns table (id text, data jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, jsonb_build_object('id', r.id, 'name', r.data->'name', 'client', r.data->'client',
    'code', r.data->'code', 'status', r.data->'status', 'dates', r.data->'dates')
  from public.pm_records r
  where public.has_app('bills') and r.coll = 'projects';
$$;
revoke all on function public.bills_events() from public, anon;
grant execute on function public.bills_events() to authenticated;

-- What needs attention, as a list of bills with their outstanding amount.
create or replace function public.bills_open(p_days int default null)
returns table (id text, number text, vendor text, category text, currency text, due_date date,
               outstanding numeric, status text, bucket text)
language sql stable security definer set search_path = public as $$
  with cfg as (
    select coalesce(p_days, bc_num((select data->>'remindDays' from public.bills_records where coll = 'settings' and id = 'main'))::int, 7) as days,
           (now() at time zone 'Asia/Riyadh')::date as today
  ), b as (
    select r.id, r.data,
      coalesce(r.data->>'status', 'pending') as st,
      case when coalesce(r.data->>'dueDate', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r.data->>'dueDate')::date end as due,
      round(coalesce(bc_num(r.data->>'amount'), 0) - coalesce((select sum(coalesce(bc_num(p->>'amount'), 0))
        from jsonb_array_elements(coalesce(r.data->'payments', '[]'::jsonb)) p), 0), 2) as owed
    from public.bills_records r where r.coll = 'bills'
  )
  select b.id, b.data->>'number', coalesce(v.data->>'name', b.data->>'vendorName', 'Supplier'), b.data->>'category',
         coalesce(b.data->>'currency', 'SAR'), b.due, b.owed, b.st,
         case when b.st = 'pending' then 'approval'
              when b.due is not null and b.due < cfg.today then 'overdue'
              when b.due is not null and b.due <= cfg.today + cfg.days then 'soon'
              else 'later' end
  from b cross join cfg
  left join public.bills_records v on v.coll = 'vendors' and v.id = b.data->>'vendorId'
  where (public.has_app('bills') or auth.role() is null or auth.role() = 'service_role')
    and b.st in ('pending', 'approved') and b.owed > 0
  order by b.due nulls last;
$$;
revoke all on function public.bills_open(int) from public, anon;
grant execute on function public.bills_open(int) to authenticated;

-- Counts for the Bills tile on the portal's apps screen.
create or replace function public.bills_alerts()
returns json language sql stable security definer set search_path = public as $$
  select case when not public.has_app('bills') then null else json_build_object(
    'overdue',  (select count(*) from public.bills_open() where bucket = 'overdue'),
    'soon',     (select count(*) from public.bills_open() where bucket = 'soon'),
    'approval', (select count(*) from public.bills_open() where bucket = 'approval'),
    'invoicesOverdue', (select count(*) from public.bills_receivables() r
                        where coalesce(r.data->>'dueDate', '') ~ '^\d{4}-\d{2}-\d{2}$'
                          and (r.data->>'dueDate')::date < (now() at time zone 'Asia/Riyadh')::date
                          and (r.data->>'due')::numeric > 0)) end;
$$;
revoke all on function public.bills_alerts() from public, anon;
grant execute on function public.bills_alerts() to authenticated;

-- The morning digest: everything due, overdue or waiting, in one JSON. Not callable from
-- the website; read by the scheduled digest with the project's own database access.
create or replace function public.bills_digest(p_days int default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with o as (select * from public.bills_open(p_days)),
  inv as (
    select r.data->>'number' as number, r.data->>'company' as client, r.data->>'currency' as currency,
           (r.data->>'due')::numeric as due,
           case when coalesce(r.data->>'dueDate', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r.data->>'dueDate')::date end as due_date
    from public.records x
    cross join lateral (select jsonb_build_object('number', x.data->'number', 'company', x.data->'client'->'company',
      'currency', coalesce(x.data->>'currency', 'SAR'), 'dueDate', x.data->'dueDate') || public.bc_invoice_totals(x.data) as data) r
    where x.coll = 'docs' and x.data->>'type' = 'invoice' and x.data->>'status' = 'sent'
  )
  select jsonb_build_object(
    'today', (now() at time zone 'Asia/Riyadh')::date,
    'bills', coalesce((select jsonb_agg(to_jsonb(o) order by o.due_date nulls last) from o where bucket <> 'later'), '[]'::jsonb),
    'invoicesUnpaid', coalesce((select jsonb_agg(to_jsonb(inv) order by inv.due_date nulls last) from inv where inv.due > 0), '[]'::jsonb));
$$;
revoke all on function public.bills_digest(int) from public, anon, authenticated;

-- Supplier invoices and payment receipts: a private storage bucket for "bills" people only.
insert into storage.buckets (id, name, public, file_size_limit)
values ('bill-files', 'bill-files', false, 15728640)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "bills files read"   on storage.objects;
drop policy if exists "bills files add"    on storage.objects;
drop policy if exists "bills files remove" on storage.objects;
create policy "bills files read"   on storage.objects for select to authenticated using (bucket_id = 'bill-files' and public.has_app('bills'));
create policy "bills files add"    on storage.objects for insert to authenticated with check (bucket_id = 'bill-files' and public.has_app('bills'));
create policy "bills files remove" on storage.objects for delete to authenticated using (bucket_id = 'bill-files' and public.has_app('bills'));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bills_records'
  ) then
    alter publication supabase_realtime add table public.bills_records;
  end if;
end $$;

-- 12. Staff assignment app (portal/staff/): the staff database, staff-only projects,
--     positions (the budgeted staff plan for each project) and who is assigned to each
--     position for which dates. Stored like the other apps as one row per item. Only people
--     with the "staff" app can read or change them. The database refuses any booking that
--     would put the same person on two projects (or two positions) on the same day.

-- Allow "staff" as an app on the access list.
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.portal_access'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%apps%'
  loop execute format('alter table public.portal_access drop constraint %I', c); end loop;
  alter table public.portal_access add constraint portal_access_apps_check
    check (apps <@ array['billing', 'crew', 'projects', 'bills', 'staff']::text[]);
end $$;

create table if not exists public.staff_records (
  coll       text        not null check (coll = any (array['staff','projects','positions','assign','budgets','settings'])),
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid        default auth.uid(),
  primary key (coll, id)
);
create index if not exists staff_records_project_idx on public.staff_records ((data->>'projectId'));
create index if not exists staff_records_person_idx  on public.staff_records ((data->>'staffId')) where coll = 'assign';
alter table public.staff_records enable row level security;
revoke all on public.staff_records from anon;
grant select, insert, update, delete on public.staff_records to authenticated;

drop policy if exists "staff can read"   on public.staff_records;
drop policy if exists "staff can add"    on public.staff_records;
drop policy if exists "staff can change" on public.staff_records;
drop policy if exists "staff can delete" on public.staff_records;
create policy "staff can read"   on public.staff_records for select to authenticated using (public.has_app('staff'));
create policy "staff can add"    on public.staff_records for insert to authenticated with check (public.has_app('staff'));
create policy "staff can change" on public.staff_records for update to authenticated using (public.has_app('staff')) with check (public.has_app('staff'));
create policy "staff can delete" on public.staff_records for delete to authenticated using (public.has_app('staff'));

drop trigger if exists staff_records_touch on public.staff_records;
create trigger staff_records_touch before insert or update on public.staff_records
  for each row execute function public.touch_record();

-- The overlap rule, enforced by the database so it holds whatever the page does: a booking
-- (on hold or confirmed) is refused if the same person already has another booking on any
-- of the same days. Released bookings don't count.
create or replace function public.staff_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  sid  text := nullif(new.data->>'staffId', '');
  st   text := coalesce(nullif(new.data->>'status', ''), 'hold');
  f    date;
  t    date;
  c    jsonb;
  who  text;
  what text;
begin
  if new.coll <> 'assign' then return new; end if;
  if sid is null then raise exception 'Pick a staff member for this booking.' using errcode = 'P0001'; end if;
  if st not in ('hold', 'confirmed', 'released') then
    raise exception 'Unknown booking status "%".', st using errcode = 'P0001';
  end if;
  begin
    f := (new.data->>'from')::date;
    t := (new.data->>'to')::date;
  exception when others then
    raise exception 'Set a valid start and end date.' using errcode = 'P0001';
  end;
  if f is null or t is null then raise exception 'Set a start and end date.' using errcode = 'P0001'; end if;
  if t < f then raise exception 'The end date is before the start date.' using errcode = 'P0001'; end if;
  if st = 'released' then return new; end if;

  -- One check at a time per person, so two bookings saved at the same moment can't both pass.
  perform pg_advisory_xact_lock(hashtext('bc-staff:' || sid));

  select r.data into c from public.staff_records r
  where r.coll = 'assign' and r.id <> new.id and r.data->>'staffId' = sid
    and coalesce(nullif(r.data->>'status', ''), 'hold') <> 'released'
    and (r.data->>'from')::date <= t and (r.data->>'to')::date >= f
  order by (r.data->>'from')::date
  limit 1;

  if c is not null then
    select nullif(s.data->>'name', '') into who from public.staff_records s where s.coll = 'staff' and s.id = sid;
    what := coalesce(
      (select nullif(p.data->>'name', '') from public.staff_records p where p.coll = 'projects' and p.id = c->>'projectId'),
      (select nullif(p.data->>'name', '') from public.pm_records    p where p.coll = 'projects' and p.id = c->>'projectId'),
      'another project');
    raise exception '%', format('%s is already on %s from %s to %s%s. Someone can’t be on two projects at the same time.',
      coalesce(who, 'This person'), what,
      to_char((c->>'from')::date, 'FMDD Mon YYYY'), to_char((c->>'to')::date, 'FMDD Mon YYYY'),
      case when coalesce(nullif(c->>'status', ''), 'hold') = 'hold' then ' (on hold)' else '' end)
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.staff_guard() from public, anon, authenticated;
drop trigger if exists staff_records_guard on public.staff_records;
create trigger staff_records_guard before insert or update on public.staff_records
  for each row execute function public.staff_guard();

-- Events from the Projects app, so staff can be planned on them without Projects access.
-- Only the basics (name, client, venue, city, code, status, type, dates) and only for
-- people with the "staff" app.
create or replace function public.staff_events()
returns table (id text, data jsonb)
language sql stable security definer set search_path = public
as $$
  select r.id, jsonb_build_object(
    'id', r.id, 'name', r.data->'name', 'client', r.data->'client', 'venue', r.data->'venue',
    'city', r.data->'city', 'code', r.data->'code', 'status', r.data->'status',
    'type', r.data->'type', 'dates', r.data->'dates')
  from public.pm_records r
  where public.has_app('staff') and r.coll = 'projects';
$$;
revoke all on function public.staff_events() from public, anon;
grant execute on function public.staff_events() to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'staff_records'
  ) then
    alter publication supabase_realtime add table public.staff_records;
  end if;
end $$;

-- 13. Finding people on Team access. When an admin types a name or email in the "Add a
--     person" form, the portal suggests matching people from the Staff database, the Crew
--     roster and the company's Microsoft 365 directory, and fills in their email and name.
--
-- The Microsoft 365 directory, copied in by the "portal-directory" Edge Function (only
-- names, work emails, job titles and departments of enabled member accounts). Nobody can
-- read it directly; admins search it through portal_people_search() below.
create table if not exists public.directory_people (
  email      text        primary key check (email = lower(email)),
  name       text        not null default '',
  title      text,
  dept       text,
  active     boolean     not null default true,
  synced_at  timestamptz not null default now()
);
alter table public.directory_people enable row level security;
revoke all on public.directory_people from anon, authenticated;

-- Up to 8 people whose name or email contains every word typed, best matches first.
-- Only portal admins get results. on_team says they're already on the access list.
create or replace function public.portal_people_search(q text)
returns table (email text, name text, title text, source text, on_team boolean)
language sql stable security definer set search_path = public
as $$
  with words as (
    select array_remove(regexp_split_to_array(lower(trim(coalesce(q, ''))), '\s+'), '') as w
  ),
  people as (
    select lower(trim(d.email)) as email, d.name, nullif(trim(coalesce(d.title, '')), '') as title,
           'm365'::text as source, 1 as rank
    from public.directory_people d
    where d.active
    union all
    select lower(trim(s.data->>'email')), coalesce(s.data->>'name', ''),
           nullif(trim(coalesce(s.data->>'title', '')), ''), 'staff', 2
    from public.staff_records s
    where s.coll = 'staff' and coalesce((s.data->>'active')::boolean, true)
    union all
    select lower(trim(c.data->>'email')), coalesce(c.data->>'name', ''),
           nullif(trim(coalesce(c.data->>'role', '')), ''), 'crew', 3
    from public.crew_records c
    where c.coll = 'crew' and coalesce((c.data->>'active')::boolean, true)
  ),
  usable as (
    select distinct on (p.email) p.*
    from people p
    where p.email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'
    order by p.email, p.rank
  )
  select u.email, u.name, u.title, u.source,
         exists (select 1 from public.portal_access a where a.email = u.email) as on_team
  from usable u, words
  where public.is_portal_admin()
    and cardinality(words.w) > 0
    and not exists (
      select 1 from unnest(words.w) t
      where position(t in lower(u.name || ' ' || u.email)) = 0
    )
  order by
    (lower(u.name) like words.w[1] || '%' or u.email like words.w[1] || '%') desc,
    exists (select 1 from public.portal_access a where a.email = u.email),
    u.name, u.email
  limit 8;
$$;
revoke all on function public.portal_people_search(text) from public, anon;
grant execute on function public.portal_people_search(text) to authenticated;

-- 14. Permanent, temporary and project access. Each person on the access list is one of:
--     - permanent: until an admin removes them (the default, and the only kind that can be admin);
--     - temp: until expires_at;
--     - project: tied to one event from the Projects app (project_id), ending the day after
--       that event's de-rig (or last show day) in Riyadh time. With project_only they see and
--       change only that event in Projects, Crew and Staff, and can't use Billing or Bills.
--     When access has ended the person can still sign in but sees no apps, and the database
--     gives them nothing.
alter table public.portal_access add column if not exists access_kind  text        not null default 'permanent';
alter table public.portal_access add column if not exists expires_at   timestamptz;
alter table public.portal_access add column if not exists project_id   text;
alter table public.portal_access add column if not exists project_only boolean     not null default false;

do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.portal_access'::regclass and conname like 'portal_access_kind%'
  loop execute format('alter table public.portal_access drop constraint %I', c); end loop;
  alter table public.portal_access add constraint portal_access_kind_check check (
    case access_kind
      when 'permanent' then expires_at is null and project_id is null and not project_only
      when 'temp'      then expires_at is not null and project_id is null and not project_only
      when 'project'   then project_id is not null and expires_at is null
      else false
    end);
  alter table public.portal_access add constraint portal_access_kind_admin_check
    check (not is_admin or access_kind = 'permanent');
  alter table public.portal_access add constraint portal_access_kind_scope_check
    check (not project_only or apps <@ array['projects', 'crew', 'staff']::text[]);
end $$;

-- When a project's access ends: the start of the day after its de-rig ends (or its last
-- show day, or show day 1), in Riyadh time. Null if the event has no dates yet.
create or replace function public.project_access_ends(p_project text)
returns timestamptz language sql stable security definer set search_path = public as $$
  select ((coalesce(nullif(r.data #>> '{dates,derigEnd}', ''), nullif(r.data #>> '{dates,showEnd}', ''),
                    nullif(r.data #>> '{dates,showStart}', ''))::date + 1)::timestamp at time zone 'Asia/Riyadh')
  from public.pm_records r where r.coll = 'projects' and r.id = p_project;
$$;

create or replace function public.access_ends(a public.portal_access)
returns timestamptz language sql stable security definer set search_path = public as $$
  select case a.access_kind
    when 'temp'    then a.expires_at
    when 'project' then public.project_access_ends(a.project_id)
    else null end;
$$;

-- The signed-in person's access row, only while it's in force.
create or replace function public.my_active_access()
returns setof public.portal_access language sql stable security definer set search_path = public as $$
  select a.* from public.portal_access a
  where a.email = lower(auth.jwt() ->> 'email')
    and (public.access_ends(a) is null or now() < public.access_ends(a));
$$;

create or replace function public.has_app(p_app text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.my_active_access() a
    where p_app = any (a.apps) and (not a.project_only or p_app in ('projects', 'crew', 'staff'))
  );
$$;

create or replace function public.is_portal_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.my_active_access() a where a.is_admin);
$$;

-- The one event a project-only person is limited to (null for everyone else).
create or replace function public.my_project_scope()
returns text language sql stable security definer set search_path = public as $$
  select a.project_id from public.my_active_access() a where a.project_only;
$$;

-- What the portal pages need to know about the signed-in person.
create or replace function public.my_access()
returns json language sql stable security definer set search_path = public as $$
  with mine as (select a.*, public.access_ends(a) as ends from public.portal_access a where a.email = lower(auth.jwt() ->> 'email')),
       live as (select * from mine where ends is null or now() < ends)
  select json_build_object(
    'apps', coalesce((select case when l.project_only then array(select x from unnest(l.apps) x where x in ('projects', 'crew', 'staff')) else l.apps end from live l), '{}'::text[]),
    'is_admin', coalesce((select l.is_admin from live l), false),
    'kind', (select m.access_kind from mine m),
    'ends_at', (select m.ends from mine m),
    'expired', exists (select 1 from mine) and not exists (select 1 from live),
    'project_only', coalesce((select m.project_only from mine m), false),
    'project', (select json_build_object('id', r.id, 'name', r.data->>'name', 'code', r.data->>'code')
                from mine m join public.pm_records r on r.coll = 'projects' and r.id = m.project_id)
  );
$$;

-- Events admins can tie access to, with when that access would end.
create or replace function public.portal_projects()
returns table (id text, name text, code text, client text, status text, show_start text, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.data->>'name', r.data->>'code', r.data->>'client', r.data->>'status',
         nullif(r.data #>> '{dates,showStart}', ''), public.project_access_ends(r.id)
  from public.pm_records r
  where public.is_portal_admin() and r.coll = 'projects'
  order by nullif(r.data #>> '{dates,showStart}', '') nulls last, r.data->>'name';
$$;

-- Each person's access, with its end date, for the Team access list (admins only).
create or replace function public.portal_access_list()
returns table (email text, apps text[], is_admin boolean, note text, access_kind text, expires_at timestamptz,
               project_id text, project_only boolean, project_name text, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.email, a.apps, a.is_admin, a.note, a.access_kind, a.expires_at, a.project_id, a.project_only,
         (select r.data->>'name' from public.pm_records r where r.coll = 'projects' and r.id = a.project_id),
         public.access_ends(a)
  from public.portal_access a
  where public.is_portal_admin()
  order by a.email;
$$;

revoke all on function public.project_access_ends(text)              from public, anon, authenticated;
revoke all on function public.access_ends(public.portal_access)       from public, anon, authenticated;
revoke all on function public.my_active_access()                      from public, anon, authenticated;
revoke all on function public.my_project_scope()                      from public, anon;
revoke all on function public.portal_projects()                       from public, anon;
revoke all on function public.portal_access_list()                    from public, anon;
grant execute on function public.my_project_scope()   to authenticated;
grant execute on function public.portal_projects()    to authenticated;
grant execute on function public.portal_access_list() to authenticated;

-- People who can be given tasks: only those whose access is still in force.
create or replace function public.pm_team()
returns table (email text, note text)
language sql stable security definer set search_path = public
as $$
  select a.email, a.note from public.portal_access a
  where public.has_app('projects') and 'projects' = any (a.apps)
    and (public.access_ends(a) is null or now() < public.access_ends(a))
  order by a.email;
$$;

-- Which rows a project-only person may see (read) and change (write). p_scope is null for
-- everyone else, who keeps the whole app.
create or replace function public.pm_row_ok(p_scope text, p_coll text, p_id text, p_data jsonb, p_write boolean)
returns boolean language sql immutable as $$
  select p_scope is null
      or (not p_write and p_coll = 'projects' and p_id = p_scope)
      or (p_coll in ('tasks', 'schedule', 'contacts') and p_data->>'projectId' = p_scope)
      or (not p_write and p_coll in ('templates', 'settings'));
$$;
create or replace function public.crew_row_ok(p_scope text, p_coll text, p_id text, p_data jsonb, p_write boolean)
returns boolean language sql immutable as $$
  select p_scope is null
      or (p_coll in ('shifts', 'assign') and p_data->>'eventId' = p_scope)
      or (not p_write and p_coll in ('crew', 'settings'));
$$;
create or replace function public.staff_row_ok(p_scope text, p_coll text, p_id text, p_data jsonb, p_write boolean)
returns boolean language sql immutable as $$
  select p_scope is null
      or (p_coll in ('positions', 'assign', 'budgets') and p_data->>'projectId' = p_scope)
      or (not p_write and p_coll in ('staff', 'settings'));
$$;

drop policy if exists "projects can read"   on public.pm_records;
drop policy if exists "projects can add"    on public.pm_records;
drop policy if exists "projects can change" on public.pm_records;
drop policy if exists "projects can delete" on public.pm_records;
create policy "projects can read" on public.pm_records for select to authenticated
  using ((select public.has_app('projects')) and public.pm_row_ok((select public.my_project_scope()), coll, id, data, false));
create policy "projects can add" on public.pm_records for insert to authenticated
  with check ((select public.has_app('projects')) and public.pm_row_ok((select public.my_project_scope()), coll, id, data, true));
create policy "projects can change" on public.pm_records for update to authenticated
  using ((select public.has_app('projects')) and public.pm_row_ok((select public.my_project_scope()), coll, id, data, true))
  with check ((select public.has_app('projects')) and public.pm_row_ok((select public.my_project_scope()), coll, id, data, true));
create policy "projects can delete" on public.pm_records for delete to authenticated
  using ((select public.has_app('projects')) and ((select public.my_project_scope()) is null
         or (coll in ('tasks', 'schedule', 'contacts') and data->>'projectId' = (select public.my_project_scope()))));

drop policy if exists "crew can read"   on public.crew_records;
drop policy if exists "crew can add"    on public.crew_records;
drop policy if exists "crew can change" on public.crew_records;
drop policy if exists "crew can delete" on public.crew_records;
create policy "crew can read" on public.crew_records for select to authenticated
  using ((select public.has_app('crew')) and public.crew_row_ok((select public.my_project_scope()), coll, id, data, false));
create policy "crew can add" on public.crew_records for insert to authenticated
  with check ((select public.has_app('crew')) and public.crew_row_ok((select public.my_project_scope()), coll, id, data, true));
create policy "crew can change" on public.crew_records for update to authenticated
  using ((select public.has_app('crew')) and public.crew_row_ok((select public.my_project_scope()), coll, id, data, true))
  with check ((select public.has_app('crew')) and public.crew_row_ok((select public.my_project_scope()), coll, id, data, true));
create policy "crew can delete" on public.crew_records for delete to authenticated
  using ((select public.has_app('crew')) and public.crew_row_ok((select public.my_project_scope()), coll, id, data, true));

drop policy if exists "staff can read"   on public.staff_records;
drop policy if exists "staff can add"    on public.staff_records;
drop policy if exists "staff can change" on public.staff_records;
drop policy if exists "staff can delete" on public.staff_records;
create policy "staff can read" on public.staff_records for select to authenticated
  using ((select public.has_app('staff')) and public.staff_row_ok((select public.my_project_scope()), coll, id, data, false));
create policy "staff can add" on public.staff_records for insert to authenticated
  with check ((select public.has_app('staff')) and public.staff_row_ok((select public.my_project_scope()), coll, id, data, true));
create policy "staff can change" on public.staff_records for update to authenticated
  using ((select public.has_app('staff')) and public.staff_row_ok((select public.my_project_scope()), coll, id, data, true))
  with check ((select public.has_app('staff')) and public.staff_row_ok((select public.my_project_scope()), coll, id, data, true));
create policy "staff can delete" on public.staff_records for delete to authenticated
  using ((select public.has_app('staff')) and public.staff_row_ok((select public.my_project_scope()), coll, id, data, true));

-- Events from the Projects app for Crew and Staff: a project-only person gets just theirs.
create or replace function public.crew_events()
returns table (id text, data jsonb)
language sql stable security definer set search_path = public
as $$
  select r.id, jsonb_build_object(
    'id', r.id, 'name', r.data->'name', 'client', r.data->'client', 'venue', r.data->'venue',
    'city', r.data->'city', 'code', r.data->'code', 'status', r.data->'status',
    'type', r.data->'type', 'dates', r.data->'dates')
  from public.pm_records r
  where public.has_app('crew') and r.coll = 'projects'
    and (public.my_project_scope() is null or r.id = public.my_project_scope());
$$;
create or replace function public.staff_events()
returns table (id text, data jsonb)
language sql stable security definer set search_path = public
as $$
  select r.id, jsonb_build_object(
    'id', r.id, 'name', r.data->'name', 'client', r.data->'client', 'venue', r.data->'venue',
    'city', r.data->'city', 'code', r.data->'code', 'status', r.data->'status',
    'type', r.data->'type', 'dates', r.data->'dates')
  from public.pm_records r
  where public.has_app('staff') and r.coll = 'projects'
    and (public.my_project_scope() is null or r.id = public.my_project_scope());
$$;

-- Someone whose access is tied to an event can't move that event's dates (which would
-- move the end of their own access). Admins and everyone else can.
create or replace function public.pm_dates_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.coll = 'projects' and (new.data->'dates') is distinct from (old.data->'dates')
     and exists (select 1 from public.portal_access a
                 where a.email = lower(auth.jwt() ->> 'email') and a.access_kind = 'project' and a.project_id = new.id) then
    raise exception 'Your access is tied to this event, so you can''t change its dates. Ask a portal admin.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.pm_dates_guard() from public, anon, authenticated;
drop trigger if exists pm_records_dates_guard on public.pm_records;
create trigger pm_records_dates_guard before update on public.pm_records
  for each row execute function public.pm_dates_guard();

-- First admin (run once, with your own email):
-- insert into public.portal_access (email, apps, is_admin)
-- values ('you@blackcanvas.live', array['billing','crew','projects','bills','staff'], true)
-- on conflict (email) do update set apps = excluded.apps, is_admin = true;
