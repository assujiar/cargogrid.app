-- Closes `ISS-2026-091` (Phase 7 HR/payroll) and `ISS-2026-142` (Phase 8 Customer Portal and
-- Loyalty). Both say the same thing: RPD-025 retention/legal-hold classification is unbuilt, and
-- no table anywhere carries a `retention_class`/`legal_hold` column an operator could act on.
--
-- WHY NOT THE FIX BOTH ENTRIES DESCRIBE
--
--   Both propose adding `retention_class`/`legal_hold`/`legal_hold_reason` columns to every
--   affected table -- ~82 in Phase 7 alone, and every Phase 8 table on top. That was measured
--   before being rejected, not assumed: the live schema carries **615** tables in `app`. Even
--   done perfectly, a column-per-table fix would:
--
--     * leave the other ~500 tables silently ungoverned, with nothing anywhere saying so;
--     * make adding a new table to governance a MIGRATION, when it is a policy decision;
--     * be unable to express a hold that covers a whole table or a whole tenant, because a
--       per-row boolean can only ever say something about a row that already exists -- and a
--       legal hold most often arrives as "preserve everything about this customer", before
--       anybody knows which rows that means.
--
--   So the classification lives in a registry keyed BY table, and a hold is a record with a
--   scope, not a flag on a row. Adding a table to governance becomes a row a Supreme Admin
--   writes, which is the same principle the task scheduler follows: the platform is configured,
--   not re-migrated.
--
-- THE HONEST PART, AND IT IS THE POINT OF `review_status`
--
--   `ISS-2026-091` warns specifically against a "copy-paste default" -- payroll figures
--   plausibly warrant `finance_tax_10y`, but candidate records, leave narrative and performance
--   data "each need their own considered mapping". That warning is right, and no migration can
--   satisfy it, because the mapping is a legal judgement about a particular business in a
--   particular jurisdiction.
--
--   So every row this migration seeds is `review_status = 'provisional'`: governed by a starting
--   class, and explicitly NOT confirmed by anybody with the standing to confirm it. Only
--   `app.confirm_data_retention_classification` -- a deliberate act, recording who and why --
--   makes a row `confirmed`. `app.list_unclassified_tables` shows what is not governed at all.
--   Between them, "which of our data is under a reviewed retention rule" becomes a question with
--   an answer, which is exactly what both entries say is missing.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: DELETE ANYTHING
--
--   There is no purge routine here, and that is a decision rather than an omission. A generic
--   sweeper that deleted rows across 615 tables from a config table would be the most dangerous
--   thing in this repository -- one wrong classification row and real business records are gone,
--   with the audit trail of the deletion being the only evidence they existed. What ships is the
--   classification, the hold, the predicate a future purge MUST consult, and a due-for-review
--   report. Deletion stays a deliberate, human-reviewed act per table.

-- ===========================================================================
-- 1. The class vocabulary -- the same three RPD-025 classes the code already names
-- ===========================================================================

create table app.data_retention_classes (
  class_code text primary key,
  display_name text not null,
  description text not null,
  -- Null means "no scheduled expiry" rather than "unknown": a class that never expires is a real
  -- policy answer, and conflating it with an unset value would make the report below lie.
  retention_months integer,
  created_at timestamptz not null default now(),
  constraint data_retention_classes_months_check check (retention_months is null or retention_months > 0)
);

comment on table app.data_retention_classes is
  'RPD-025 retention vocabulary. Deliberately the same three classes scripts/data-classification/registry.ts already names (finance_tax_10y, audit_security_7y, operational_contract_plus_90d) rather than a new parallel set -- the repository having two disagreeing retention vocabularies would be worse than having none. retention_months null means "no scheduled expiry", a real policy answer, never "not yet decided".';

insert into app.data_retention_classes (class_code, display_name, description, retention_months) values
  ('finance_tax_10y', 'Financial and tax records (10 years)',
   'Records with a statutory financial or tax retention obligation. Payroll figures are included on the inference scripts/data-classification/registry.ts already documents.', 120),
  ('audit_security_7y', 'Audit and security records (7 years)',
   'Audit trails, access records and security evidence.', 84),
  ('operational_contract_plus_90d', 'Operational records (contract term plus 90 days)',
   'Operational and personal data kept for the life of the commercial relationship plus a short tail.', null)
on conflict (class_code) do nothing;

-- ===========================================================================
-- 2. The classification registry -- one row per governed table
-- ===========================================================================

create table app.data_retention_classifications (
  id uuid primary key default gen_random_uuid(),
  table_schema text not null default 'app',
  table_name text not null,
  class_code text not null references app.data_retention_classes (class_code),
  domain text not null,
  -- 'provisional' until somebody with the standing to decide says otherwise. See the header.
  review_status text not null default 'provisional',
  review_note text,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint data_retention_classifications_unique unique (table_schema, table_name),
  constraint data_retention_classifications_review_status_check check (review_status in ('provisional', 'confirmed')),
  -- A confirmed row must say who confirmed it and when. A "confirmed" classification with no
  -- reviewer is exactly the false assurance this whole entry is about.
  constraint data_retention_classifications_confirmed_shape_check check (
    review_status <> 'confirmed' or (reviewed_by_auth_user_id is not null and reviewed_at is not null)
  )
);

comment on table app.data_retention_classifications is
  'ISS-2026-091/ISS-2026-142: which retention class governs which table. A registry rather than a column on each table, because the live schema carries 615 tables in app -- a column-per-table fix would leave ~500 silently ungoverned and would make adding a table to governance a migration rather than a policy decision. review_status is the load-bearing field: every row seeded by 20260831120000 is provisional, meaning "governed by a starting class, NOT confirmed by anybody with the standing to confirm it". ISS-2026-091 warns specifically against a copy-paste default, and no migration can answer that warning, because the mapping is a legal judgement about a particular business in a particular jurisdiction. app.confirm_data_retention_classification is how a row stops being provisional.';

comment on column app.data_retention_classifications.review_status is
  'provisional | confirmed. Provisional is the honest default and is NOT a defect -- it says the table is governed and the mapping has not been legally reviewed. The CHECK constraint makes a confirmed row impossible without a named reviewer and a timestamp.';

create index data_retention_classifications_domain_idx on app.data_retention_classifications (domain, review_status);

-- ===========================================================================
-- 3. Legal holds -- a record with a scope, never a boolean on a row
-- ===========================================================================

create table app.data_legal_holds (
  id uuid primary key default gen_random_uuid(),
  -- Null tenant_id = a platform-wide hold, which a Supreme Admin can place and a tenant admin
  -- cannot. Real holds arrive at that grain (an investigation touching the whole platform) as
  -- often as at a tenant's own.
  tenant_id uuid references app.tenants (id),
  -- Null table_name = every governed table. Null record_id with a table_name = that whole table.
  -- This is the shape a per-row boolean cannot express, and it is the common case: a hold
  -- usually arrives as "preserve everything about this customer", before anybody knows which
  -- rows that means -- including rows not yet written when the hold was placed.
  table_schema text not null default 'app',
  table_name text,
  record_id uuid,
  reason text not null,
  reference text,
  placed_by_auth_user_id uuid not null references auth.users (id),
  placed_at timestamptz not null default now(),
  released_by_auth_user_id uuid references auth.users (id),
  released_at timestamptz,
  release_reason text,
  created_at timestamptz not null default now(),
  constraint data_legal_holds_reason_check check (length(trim(reason)) > 0),
  constraint data_legal_holds_scope_check check (table_name is not null or record_id is null),
  -- A released hold must say who released it and why. Releasing a legal hold is the act that
  -- makes destruction possible again, so it carries at least as much evidence as placing one.
  constraint data_legal_holds_release_shape_check check (
    released_at is null or (released_by_auth_user_id is not null and release_reason is not null and length(trim(release_reason)) > 0)
  )
);

comment on table app.data_legal_holds is
  'ISS-2026-091/ISS-2026-142: a legal hold as a RECORD with a scope, not a boolean on a row. Scope widens as the fields go null: a record, a table, a tenant, or the platform. That shape is the reason this is not a per-row column -- a hold usually arrives as "preserve everything about this customer" before anybody knows which rows that means, INCLUDING rows not yet written when the hold was placed, which a per-row flag can never cover. Never deleted: releasing sets released_at/released_by/release_reason, so the history of what was held and when survives the hold itself.';

comment on column app.data_legal_holds.table_name is
  'Null means every governed table within the tenant scope. With a table_name and a null record_id, the whole table is held.';

create index data_legal_holds_active_idx on app.data_legal_holds (tenant_id, table_name, record_id) where released_at is null;

-- ===========================================================================
-- 4. The predicate a purge MUST consult
-- ===========================================================================

create function app.is_record_under_legal_hold(
  p_table_name text,
  p_tenant_id uuid default null,
  p_record_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.data_legal_holds h
    where h.released_at is null
      -- A platform-wide hold (null tenant_id) covers every tenant. A tenant hold covers only
      -- its own. The nulls widen the scope; they never narrow it.
      and (h.tenant_id is null or h.tenant_id = p_tenant_id)
      and (h.table_name is null or h.table_name = p_table_name)
      and (h.record_id is null or h.record_id = p_record_id)
  );
$$;

comment on function app.is_record_under_legal_hold is
  'ISS-2026-091/ISS-2026-142: the predicate any future purge routine MUST consult before deleting anything. Nulls in a hold WIDEN its scope and never narrow it: a hold with a null tenant_id covers every tenant, a null table_name covers every table, a null record_id covers every row of the named table. Deliberately answers for a record that does not exist yet -- a hold placed before the row was written still covers it, which is the whole reason holds are records rather than per-row flags.';

revoke execute on function app.is_record_under_legal_hold(text, uuid, uuid) from public;
grant execute on function app.is_record_under_legal_hold(text, uuid, uuid) to service_role;

-- ===========================================================================
-- 5. Governed operations
-- ===========================================================================

create function app.classify_table_retention(
  p_table_name text,
  p_class_code text,
  p_domain text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.data_retention_classifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.data_retention_classifications;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only a Supreme Admin may set a table''s retention classification'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from information_schema.tables t where t.table_schema = 'app' and t.table_name = p_table_name) then
    raise exception 'table_not_found: app.% is not a table in this database', p_table_name using errcode = 'no_data_found';
  end if;

  insert into app.data_retention_classifications as c (table_schema, table_name, class_code, domain, review_status)
  values ('app', p_table_name, p_class_code, p_domain, 'provisional')
  on conflict (table_schema, table_name) do update
  -- Re-classifying resets the review: a class that changed has not been reviewed under its new
  -- class, whatever was true of the old one.
  set class_code = excluded.class_code,
      domain = excluded.domain,
      review_status = case when c.class_code = excluded.class_code then c.review_status else 'provisional' end,
      reviewed_by_auth_user_id = case when c.class_code = excluded.class_code then c.reviewed_by_auth_user_id else null end,
      reviewed_at = case when c.class_code = excluded.class_code then c.reviewed_at else null end,
      updated_at = now()
  returning * into v_row;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'classify_table_retention',
    'app.data_retention_classifications', v_row.id, 'success', null, null,
    jsonb_build_object('table_name', p_table_name, 'class_code', p_class_code, 'review_status', v_row.review_status)
  );

  return v_row;
end;
$$;

comment on function app.classify_table_retention is
  'Supreme-Admin-only. Sets or changes which retention class governs a table, verified against information_schema so a typo cannot create governance for a table that does not exist. Changing the CLASS resets review_status to provisional and clears the reviewer -- a table reclassified from operational to finance_tax_10y has not been reviewed under its new class, whatever was true of the old one, and carrying the old confirmation forward would be a false assurance about the new rule.';

revoke execute on function app.classify_table_retention(text, text, text, uuid, text) from public;
grant execute on function app.classify_table_retention(text, text, text, uuid, text) to authenticated, service_role;

create function app.confirm_data_retention_classification(
  p_table_name text,
  p_review_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.data_retention_classifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.data_retention_classifications;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only a Supreme Admin may confirm a retention classification'
      using errcode = 'insufficient_privilege';
  end if;

  if p_review_note is null or length(trim(p_review_note)) = 0 then
    raise exception 'review_note_required: confirming a retention classification requires a note recording the basis for it'
      using errcode = 'check_violation';
  end if;

  update app.data_retention_classifications
  set review_status = 'confirmed',
      review_note = trim(p_review_note),
      reviewed_by_auth_user_id = p_actor_auth_user_id,
      reviewed_at = now(),
      updated_at = now()
  where table_schema = 'app' and table_name = p_table_name
  returning * into v_row;
  if not found then
    raise exception 'classification_not_found: app.% has no retention classification to confirm', p_table_name using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'confirm_data_retention_classification',
    'app.data_retention_classifications', v_row.id, 'success', null, null,
    jsonb_build_object('table_name', p_table_name, 'class_code', v_row.class_code)
  );

  return v_row;
end;
$$;

comment on function app.confirm_data_retention_classification is
  'The act that turns a provisional classification into a reviewed one. Supreme-Admin-only, and requires a note recording the basis -- a confirmation with no stated reason is not evidence of a review, it is a checkbox. This is the only path to review_status = confirmed; nothing seeds it.';

revoke execute on function app.confirm_data_retention_classification(text, text, uuid, text) from public;
grant execute on function app.confirm_data_retention_classification(text, text, uuid, text) to authenticated, service_role;

create function app.place_data_legal_hold(
  p_tenant_id uuid,
  p_table_name text,
  p_record_id uuid,
  p_reason text,
  p_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.data_legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_hold app.data_legal_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- A platform-wide hold (no tenant) is Supreme-Admin-only; a tenant-scoped one may also be
  -- placed by that tenant's own admin, who is the person a court order or a customer dispute
  -- actually reaches first.
  if p_tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only a Supreme Admin may place a platform-wide legal hold'
        using errcode = 'insufficient_privilege';
    end if;
  elsif not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not place a legal hold for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'hold_reason_required: a legal hold requires a stated reason' using errcode = 'check_violation';
  end if;

  if p_record_id is not null and p_table_name is null then
    raise exception 'hold_scope_invalid: a record-scoped hold must name the table the record is in' using errcode = 'check_violation';
  end if;

  insert into app.data_legal_holds (tenant_id, table_schema, table_name, record_id, reason, reference, placed_by_auth_user_id)
  values (p_tenant_id, 'app', p_table_name, p_record_id, trim(p_reason), p_reference, p_actor_auth_user_id)
  returning * into v_hold;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'place_data_legal_hold',
    'app.data_legal_holds', v_hold.id, 'success', null, null,
    jsonb_build_object('tenant_id', p_tenant_id, 'table_name', p_table_name, 'record_id', p_record_id, 'reference', p_reference)
  );

  return v_hold;
end;
$$;

comment on function app.place_data_legal_hold is
  'Places a legal hold. Scope widens as arguments go null: a record, a table, a tenant, or the platform. A platform-wide hold is Supreme-Admin-only; a tenant-scoped one may also be placed by that tenant''s own admin, who is who a court order or a customer dispute actually reaches first. A reason is mandatory -- an unexplained hold cannot be reviewed later by the person who has to decide whether to release it.';

revoke execute on function app.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text) from public;
grant execute on function app.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text) to authenticated, service_role;

create function app.release_data_legal_hold(
  p_hold_id uuid,
  p_release_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.data_legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_hold app.data_legal_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_hold from app.data_legal_holds where id = p_hold_id for update;
  if not found then
    raise exception 'hold_not_found: %', p_hold_id using errcode = 'no_data_found';
  end if;

  if v_hold.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only a Supreme Admin may release a platform-wide legal hold'
        using errcode = 'insufficient_privilege';
    end if;
  elsif not app.is_support_grant_authority(p_actor_auth_user_id, v_hold.tenant_id) then
    raise exception 'insufficient_authority: identity % may not release this hold', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_hold.released_at is not null then
    raise exception 'hold_already_released: hold % was released at %', p_hold_id, v_hold.released_at using errcode = 'check_violation';
  end if;

  if p_release_reason is null or length(trim(p_release_reason)) = 0 then
    raise exception 'release_reason_required: releasing a legal hold requires a stated reason' using errcode = 'check_violation';
  end if;

  -- Released, never deleted. The row IS the history of what was preserved and why.
  update app.data_legal_holds
  set released_at = now(), released_by_auth_user_id = p_actor_auth_user_id, release_reason = trim(p_release_reason)
  where id = p_hold_id
  returning * into v_hold;

  perform app.capture_audit_event(
    v_hold.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_data_legal_hold',
    'app.data_legal_holds', v_hold.id, 'success', null, null,
    jsonb_build_object('hold_id', v_hold.id, 'release_reason', v_hold.release_reason)
  );

  return v_hold;
end;
$$;

comment on function app.release_data_legal_hold is
  'Releases a hold, which is the act that makes destruction possible again -- so it carries at least as much evidence as placing one: a mandatory reason, the releasing identity, and the instant. The row is never deleted; it stays as the record of what was preserved, why, and for how long.';

revoke execute on function app.release_data_legal_hold(uuid, text, uuid, text) from public;
grant execute on function app.release_data_legal_hold(uuid, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 6. Visibility -- what is governed, what is reviewed, what is not governed at all
-- ===========================================================================

create function app._list_unclassified_tables()
returns table (table_name text)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select t.table_name::text
  from information_schema.tables t
  left join app.data_retention_classifications c
    on c.table_schema = 'app' and c.table_name = t.table_name
  where t.table_schema = 'app' and t.table_type = 'BASE TABLE' and c.id is null
  order by t.table_name;
$$;

comment on function app._list_unclassified_tables is
  'The tables carrying no retention classification at all. This is the artifact that turns "retention is unbuilt" from an invisible gap into a worklist: ISS-2026-091 and ISS-2026-142 both existed because nobody could see what was and was not governed. Read through app.get_data_retention_coverage, which is where it is authority-gated.';

-- app._ prefixed: a helper of app.get_data_retention_coverage with no independent meaning, and
-- the underscore exempts it from the public.* wrapper-parity gate, which is correct -- it should
-- not become a REST endpoint. get_data_retention_coverage is SECURITY DEFINER and reaches it as
-- the function owner.
revoke execute on function app._list_unclassified_tables() from public;
grant execute on function app._list_unclassified_tables() to service_role;

create function app.get_data_retention_coverage(p_actor_auth_user_id uuid)
returns table (total_tables integer, classified integer, confirmed integer, provisional integer, unclassified integer, active_holds integer)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only a Supreme Admin may read platform-wide retention coverage'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    (select count(*)::integer from information_schema.tables t where t.table_schema = 'app' and t.table_type = 'BASE TABLE'),
    (select count(*)::integer from app.data_retention_classifications),
    (select count(*)::integer from app.data_retention_classifications where review_status = 'confirmed'),
    (select count(*)::integer from app.data_retention_classifications where review_status = 'provisional'),
    (select count(*)::integer from app._list_unclassified_tables()),
    (select count(*)::integer from app.data_legal_holds where released_at is null);
end;
$$;

comment on function app.get_data_retention_coverage is
  'Supreme-Admin-only coverage summary. Reports provisional and confirmed SEPARATELY on purpose: collapsing them into one "classified" number would let a wall of unreviewed defaults read as compliance, which is the precise failure ISS-2026-091 warns about.';

revoke execute on function app.get_data_retention_coverage(uuid) from public;
grant execute on function app.get_data_retention_coverage(uuid) to authenticated, service_role;

-- ===========================================================================
-- 7. Seed the two domains the entries name
-- ===========================================================================
--
-- Seeded by PATTERN rather than by a hand-typed list of 100+ names, because a hand-typed list is
-- wrong the moment a table is added and nobody notices. Every row lands `provisional`.

insert into app.data_retention_classifications (table_schema, table_name, class_code, domain, review_status)
select 'app', t.table_name, 'finance_tax_10y', 'hr_payroll', 'provisional'
from information_schema.tables t
where t.table_schema = 'app' and t.table_type = 'BASE TABLE'
  and (t.table_name like 'payroll_%' or t.table_name like 'timesheet_%' or t.table_name like 'overtime_%')
on conflict (table_schema, table_name) do nothing;

insert into app.data_retention_classifications (table_schema, table_name, class_code, domain, review_status)
select 'app', t.table_name, 'operational_contract_plus_90d', 'hr_people', 'provisional'
from information_schema.tables t
where t.table_schema = 'app' and t.table_type = 'BASE TABLE'
  and (t.table_name in ('employees', 'candidates', 'job_applications', 'job_offers', 'interviews', 'interview_feedback', 'candidate_assessments')
       or t.table_name like 'employee_%' or t.table_name like 'leave_%' or t.table_name like 'performance_%'
       or t.table_name like 'training_%' or t.table_name like 'attendance_%' or t.table_name like 'onboarding_%')
on conflict (table_schema, table_name) do nothing;

-- Phase 8. The six append-only Loyalty ledger tables ISS-2026-142 names by name are financial
-- records -- points and vouchers are a liability the tenant owes a customer -- so they take the
-- finance class, while the portal's own operational tables take the operational one.
insert into app.data_retention_classifications (table_schema, table_name, class_code, domain, review_status)
select 'app', t.table_name, 'finance_tax_10y', 'loyalty_ledger', 'provisional'
from information_schema.tables t
where t.table_schema = 'app' and t.table_type = 'BASE TABLE'
  and (t.table_name like 'loyalty_%ledger%' or t.table_name like 'loyalty_point_%' or t.table_name like 'loyalty_%entitlement%'
       or t.table_name like 'loyalty_redemption%' or t.table_name like 'loyalty_earning%' or t.table_name like 'loyalty_%liability%')
on conflict (table_schema, table_name) do nothing;

insert into app.data_retention_classifications (table_schema, table_name, class_code, domain, review_status)
select 'app', t.table_name, 'operational_contract_plus_90d', 'customer_portal', 'provisional'
from information_schema.tables t
where t.table_schema = 'app' and t.table_type = 'BASE TABLE'
  and (t.table_name like 'customer_portal_%' or t.table_name like 'loyalty_%')
on conflict (table_schema, table_name) do nothing;

-- ===========================================================================
-- 8. Grants and RLS
-- ===========================================================================

grant select on app.data_retention_classes to authenticated, service_role;
grant select on app.data_retention_classifications to authenticated, service_role;
grant insert, update on app.data_retention_classifications to service_role;
grant select, insert, update on app.data_legal_holds to service_role;

alter table app.data_legal_holds enable row level security;

-- `(select auth.uid())`, never a bare call: inside a policy clause the bare form is re-evaluated
-- per row (scripts/security/check-rls-initplan.ts enforces this repository-wide).
create policy data_legal_holds_select_scoped on app.data_legal_holds
  for select to authenticated
  using (tenant_id is not null and app.is_support_grant_authority((select auth.uid()), tenant_id));

comment on table app.data_retention_classes is
  'RPD-025 retention vocabulary. Deliberately the same three classes scripts/data-classification/registry.ts already names, rather than a new parallel set -- two disagreeing retention vocabularies in one repository would be worse than none. retention_months null means "no scheduled expiry", a real policy answer, never "not yet decided".';

-- ===========================================================================
-- 9. public.* wrappers (RGL-394 Option 2)
-- ===========================================================================
--
-- `from anon, ...` on each, never `from public` alone: Supabase's ALTER DEFAULT PRIVILEGES grants
-- anon EXECUTE explicitly at CREATE time in schema public, and an explicit grant survives a
-- PUBLIC revoke -- the ISS-2026-309 mechanism.

create function public.classify_table_retention(p_table_name text, p_class_code text, p_domain text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.data_retention_classifications
language sql security definer set search_path = app, public, pg_temp
as $wrap$ select * from app.classify_table_retention(p_table_name, p_class_code, p_domain, p_actor_auth_user_id, p_actor_label); $wrap$;
comment on function public.classify_table_retention(text, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.classify_table_retention, never a reimplementation.';
revoke execute on function public.classify_table_retention(text, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.classify_table_retention(text, text, text, uuid, text) to authenticated, service_role;

create function public.confirm_data_retention_classification(p_table_name text, p_review_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.data_retention_classifications
language sql security definer set search_path = app, public, pg_temp
as $wrap$ select * from app.confirm_data_retention_classification(p_table_name, p_review_note, p_actor_auth_user_id, p_actor_label); $wrap$;
comment on function public.confirm_data_retention_classification(text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.confirm_data_retention_classification, never a reimplementation.';
revoke execute on function public.confirm_data_retention_classification(text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.confirm_data_retention_classification(text, text, uuid, text) to authenticated, service_role;

create function public.place_data_legal_hold(p_tenant_id uuid, p_table_name text, p_record_id uuid, p_reason text, p_reference text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.data_legal_holds
language sql security definer set search_path = app, public, pg_temp
as $wrap$ select * from app.place_data_legal_hold(p_tenant_id, p_table_name, p_record_id, p_reason, p_reference, p_actor_auth_user_id, p_actor_label); $wrap$;
comment on function public.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.place_data_legal_hold, never a reimplementation.';
revoke execute on function public.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text) to authenticated, service_role;

create function public.release_data_legal_hold(p_hold_id uuid, p_release_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.data_legal_holds
language sql security definer set search_path = app, public, pg_temp
as $wrap$ select * from app.release_data_legal_hold(p_hold_id, p_release_reason, p_actor_auth_user_id, p_actor_label); $wrap$;
comment on function public.release_data_legal_hold(uuid, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.release_data_legal_hold, never a reimplementation.';
revoke execute on function public.release_data_legal_hold(uuid, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.release_data_legal_hold(uuid, text, uuid, text) to authenticated, service_role;

create function public.get_data_retention_coverage(p_actor_auth_user_id uuid)
returns table (total_tables integer, classified integer, confirmed integer, provisional integer, unclassified integer, active_holds integer)
language sql stable security definer set search_path = app, public, pg_temp
as $wrap$ select * from app.get_data_retention_coverage(p_actor_auth_user_id); $wrap$;
comment on function public.get_data_retention_coverage(uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.get_data_retention_coverage, never a reimplementation.';
revoke execute on function public.get_data_retention_coverage(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_data_retention_coverage(uuid) to authenticated, service_role;

-- The purge predicate gets a wrapper too, with a grant set matching its app.* counterpart
-- EXACTLY: service_role and nothing else. It is a real API -- any future purge routine, in SQL or
-- in a worker, must call it -- so unlike app._list_unclassified_tables it should not be hidden
-- behind an underscore. But "callable" here still means service_role only.
create function public.is_record_under_legal_hold(p_table_name text, p_tenant_id uuid default null, p_record_id uuid default null)
returns boolean
language sql stable security definer set search_path = app, public, pg_temp
as $wrap$ select app.is_record_under_legal_hold(p_table_name, p_tenant_id, p_record_id); $wrap$;
comment on function public.is_record_under_legal_hold(text, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.is_record_under_legal_hold, never a reimplementation. service_role-only, matching the app.* grant set exactly -- an authenticated session has no business asking whether an arbitrary record is under legal hold.';
revoke execute on function public.is_record_under_legal_hold(text, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.is_record_under_legal_hold(text, uuid, uuid) to service_role;
