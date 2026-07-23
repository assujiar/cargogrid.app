-- Commercial capability COM-143 (Lead Management, CG-S7-COM-002)
-- The first Commercial-domain (and first business-domain) table in this repository.
-- Canonical tenant-aware lead lifecycle across manual/import/api/referral/campaign/
-- integration sources with idempotent capture, normalized duplicate detection, versioned
-- explainable scoring, ownership/assignment, and qualify/disqualify/merge transitions.
--
-- Record-scope (own/team/department/branch/company) is enforced by composing two
-- already-VERIFIED Platform Core primitives rather than inventing a new authority model:
-- app.can_access_record() (PLT-114, Field-Level and Record-Level Access -- proven only by
-- direct call until now, per that migration's own header, since no business-domain table
-- existed yet) and app.org_unit_ancestor_ids() (PLT-109, Organization Hierarchy). Passing
-- a lead's own org unit plus every one of its ancestors as the "shared scope" set means an
-- actor whose own org_unit_id is the lead's team, or any ancestor branch/department/company
-- node above it, is granted access -- the full "own/team/department/branch/company" scope
-- ladder Prompt 143 §16 requires, with zero new mechanism: whoever sits at the tenant's
-- root org unit already sees every lead beneath it, by construction of the ancestor chain.
--
-- Every mutation is a SECURITY DEFINER function performing its own authority check
-- in-body (RBAC entitlement via app.evaluate_permission(), record-scope via
-- app.can_access_record()) and is granted to `authenticated` directly (unlike the
-- master-data engine's service-role-only convention) precisely because record-scope here
-- varies per lead and per actor -- a blanket service-role bypass would defeat the very
-- scope check this capability exists to enforce. Reads go through RLS directly (no
-- function needed), matching the identical "RLS for reads, checked functions for writes"
-- split used since PLT-105.

-- Canonical permission catalogue extension (PLT-111's app.permissions is stable but
-- additive -- new actions/modules are seeded via later migrations, the same pattern
-- PLT-120 used for app.master_types' 'vendor_rate' row). 'Assign' is already a valid
-- action per the existing permissions_action_check constraint (used by OPS/TKT); this
-- migration is the first to need it for 'COM'.
insert into app.permissions (action, resource_module_code, category, protected) values
  ('Assign', 'COM', 'standard', false);

create table app.leads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  source text not null,
  external_reference text,
  company_name text,
  contact_name text not null,
  email text,
  phone text,
  normalized_email text,
  normalized_phone text,
  duplicate_fingerprint text not null,
  status text not null default 'new',
  disqualify_reason text,
  score integer not null default 0,
  score_explanation jsonb not null default '{}'::jsonb,
  score_version integer not null default 1,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  assigned_at timestamptz,
  assigned_by text,
  qualified_at timestamptz,
  disqualified_at timestamptz,
  merged_into_id uuid references app.leads (id),
  merged_at timestamptz,
  merged_by text,
  converted_at timestamptz,
  last_activity_at timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leads_source_check check (source in ('manual', 'import', 'api', 'referral', 'campaign', 'integration')),
  constraint leads_status_check check (status in ('new', 'contacted', 'qualified', 'disqualified', 'merged', 'converted')),
  constraint leads_score_check check (score between 0 and 100),
  constraint leads_disqualify_reason_check check (
    (status = 'disqualified' and disqualify_reason is not null and length(trim(disqualify_reason)) > 0)
    or (status <> 'disqualified')
  ),
  constraint leads_merged_check check (
    (status = 'merged' and merged_into_id is not null)
    or (status <> 'merged' and merged_into_id is null)
  ),
  constraint leads_not_self_merged check (merged_into_id is null or merged_into_id <> id),
  constraint leads_contact_identifier_check check (email is not null or phone is not null)
);

comment on table app.leads is
  'COM-143: canonical tenant-aware lead identity, the first trusted identity in Commercial''s lineage chain (lead -> prospect -> ... -> Job Order). duplicate_fingerprint is computed server-side (app.set_lead_computed_fields trigger) from normalized email/phone/company -- never entered directly, never a second source of truth. merged_into_id preserves lineage exactly like app.master_records.merged_into_id (PLT-120) -- the duplicate row is never deleted.';

-- Idempotent capture per external system: a repeated capture with the same
-- (tenant, source, external_reference) must return the original lead, never create a
-- second one. Only meaningful for source in (''import'',''api'',''integration'') --
-- manual/referral/campaign leads have no external system of record.
create unique index leads_tenant_source_external_ref_unique
  on app.leads (tenant_id, source, external_reference)
  where external_reference is not null;

create index leads_tenant_fingerprint_idx on app.leads (tenant_id, duplicate_fingerprint);
create index leads_tenant_status_idx on app.leads (tenant_id, status);
create index leads_tenant_owner_idx on app.leads (tenant_id, owner_user_id);
create index leads_tenant_aging_idx on app.leads (tenant_id, last_activity_at);
create index leads_merged_into_idx on app.leads (merged_into_id) where merged_into_id is not null;

create function app.normalize_lead_email(p_email text)
returns text
language sql
immutable
as $$
  select nullif(lower(trim(p_email)), '');
$$;

create function app.normalize_lead_phone(p_phone text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;

comment on function app.normalize_lead_phone is
  'COM-143: digits-only normalization (strips spaces/dashes/parentheses/country-code punctuation) -- a deliberately simple, deterministic rule, not a full E.164 parser, matching this task''s bounded scope.';

create function app.compute_lead_duplicate_fingerprint(
  p_tenant_id uuid,
  p_normalized_email text,
  p_normalized_phone text,
  p_company_name text
)
returns text
language sql
immutable
as $$
  select md5(
    p_tenant_id::text || '|' ||
    coalesce(p_normalized_email, '') || '|' ||
    coalesce(p_normalized_phone, '') || '|' ||
    coalesce(lower(trim(p_company_name)), '')
  );
$$;

comment on function app.compute_lead_duplicate_fingerprint is
  'COM-143: deterministic identity key over normalized email + normalized phone + lowercased company name, scoped per tenant (never leaks a cross-tenant match -- the tenant id is part of the hash input). Used both to populate app.leads.duplicate_fingerprint and to search for candidates before insert.';

create function app.set_lead_computed_fields()
returns trigger
language plpgsql
as $$
begin
  new.normalized_email := app.normalize_lead_email(new.email);
  new.normalized_phone := app.normalize_lead_phone(new.phone);
  new.duplicate_fingerprint := app.compute_lead_duplicate_fingerprint(
    new.tenant_id, new.normalized_email, new.normalized_phone, new.company_name
  );
  new.updated_at := now();
  return new;
end;
$$;

create trigger leads_set_computed_fields
  before insert or update of email, phone, company_name on app.leads
  for each row
  execute function app.set_lead_computed_fields();

-- Narrow SECURITY DEFINER wrapper -- the same "answer exactly one bounded question"
-- pattern app.has_view_personal_data (PLT-114) already established, rather than widening
-- app.org_unit_ancestor_ids' own service_role-only grant (PLT-109) just for this one
-- caller. Returns the lead's own org unit plus every ancestor (branch/department/company)
-- above it -- the exact "shared scope" set app.can_access_record expects.
create function app.lead_record_scope_org_unit_ids(p_org_unit_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce(app.org_unit_ancestor_ids(p_org_unit_id), '{}'::uuid[])
    || coalesce(p_org_unit_id, '00000000-0000-0000-0000-000000000000'::uuid);
$$;

comment on function app.lead_record_scope_org_unit_ids is
  'COM-143: wraps app.org_unit_ancestor_ids (PLT-109, service_role-only) so authenticated callers -- the RLS policy on app.leads, plus every mutation function below -- can compute a lead''s own/team/department/branch/company scope set without widening that function''s original grant.';

-- Deterministic, explainable, versioned scoring (score_version=1 for this checkpoint's
-- one rule generation). Rule-based only -- no AI/ML call, per RPD-boundary "AI outputs
-- are advisory-only" (01_MODULE_DEPENDENCY_MAP.md line 147) and Phase 9's own exclusive
-- ownership of any learned/ML scoring model. A future score_version bump is how a revised
-- rule set would ship without silently reinterpreting already-scored leads' history.
create function app.compute_lead_score(p_lead app.leads)
returns table (score integer, explanation jsonb)
language plpgsql
immutable
as $$
declare
  v_score integer := 0;
  v_explanation jsonb := '[]'::jsonb;
begin
  if p_lead.email is not null then
    v_score := v_score + 20;
    v_explanation := v_explanation || jsonb_build_object('rule', 'has_email', 'points', 20);
  end if;
  if p_lead.phone is not null then
    v_score := v_score + 20;
    v_explanation := v_explanation || jsonb_build_object('rule', 'has_phone', 'points', 20);
  end if;
  if p_lead.company_name is not null and length(trim(p_lead.company_name)) > 0 then
    v_score := v_score + 15;
    v_explanation := v_explanation || jsonb_build_object('rule', 'has_company_name', 'points', 15);
  end if;
  if p_lead.source in ('referral', 'campaign') then
    v_score := v_score + 15;
    v_explanation := v_explanation || jsonb_build_object('rule', 'warm_source', 'points', 15, 'source', p_lead.source);
  end if;
  if p_lead.external_reference is not null then
    v_score := v_score + 30;
    v_explanation := v_explanation || jsonb_build_object('rule', 'known_external_system', 'points', 30);
  end if;

  return query select least(v_score, 100), jsonb_build_object('version', 1, 'rules', v_explanation);
end;
$$;

comment on function app.compute_lead_score is
  'COM-143: pure, deterministic, capped-at-100 scoring function. Informs workflow only (Prompt 143 §24: "does not silently make a protected business decision") -- no gate anywhere blocks a low-scored lead from being contacted/qualified.';

create function app.find_duplicate_leads(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_email text,
  p_phone text,
  p_company_name text
)
returns setof app.leads
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_lead_duplicate_fingerprint(
    p_tenant_id, app.normalize_lead_email(p_email), app.normalize_lead_phone(p_phone), p_company_name
  );

  return query
    select * from app.leads
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status <> 'merged'
    order by created_at;
end;
$$;

comment on function app.find_duplicate_leads is
  'COM-143: tenant-scoped only (fails closed on missing membership before any search runs) -- structurally cannot be used to probe another tenant''s leads, per Prompt 143 §16.';

create function app.capture_lead(
  p_tenant_id uuid,
  p_source text,
  p_external_reference text,
  p_company_name text,
  p_contact_name text,
  p_email text,
  p_phone text,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.leads;
  v_lead app.leads;
  v_decision app.rbac_decision;
  v_scored record;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_external_reference is not null then
    select * into v_existing
    from app.leads
    where tenant_id = p_tenant_id and source = p_source and external_reference = p_external_reference;
    if found then
      return v_existing;
    end if;
  end if;

  insert into app.leads (
    tenant_id, source, external_reference, company_name, contact_name, email, phone,
    owner_user_id, org_unit_id, created_by
  ) values (
    p_tenant_id, p_source, p_external_reference, p_company_name, p_contact_name, p_email, p_phone,
    p_owner_user_id, p_org_unit_id, p_created_by
  )
  returning * into v_lead;

  select * into v_scored from app.compute_lead_score(v_lead);
  update app.leads set score = v_scored.score, score_explanation = v_scored.explanation
  where id = v_lead.id
  returning * into v_lead;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'capture_lead',
    'app.leads', v_lead.id, 'success', null, null, to_jsonb(v_lead)
  );

  return v_lead;
exception
  when unique_violation then
    select * into v_existing
    from app.leads
    where tenant_id = p_tenant_id and source = p_source and external_reference = p_external_reference;
    return v_existing;
end;
$$;

comment on function app.capture_lead is
  'COM-143: idempotent for import/api/integration sources (repeated capture with the same external_reference returns the original row, including under a race -- the unique_violation handler re-selects rather than raising). Duplicate *candidates* (by fingerprint) are surfaced separately via app.find_duplicate_leads, never silently blocked here -- capture always succeeds; merge is an explicit later action (Prompt 143 §22).';

create function app.score_lead(
  p_lead_id uuid,
  p_actor_auth_user_id uuid
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
  v_scored record;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_scored from app.compute_lead_score(v_lead);

  update app.leads
  set score = v_scored.score, score_explanation = v_scored.explanation, last_activity_at = now()
  where id = p_lead_id
  returning * into v_lead;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, null, 'score_lead',
    'app.leads', v_lead.id, 'success', null, null, jsonb_build_object('score', v_lead.score, 'score_version', v_lead.score_version)
  );

  return v_lead;
end;
$$;

create function app.assign_lead(
  p_lead_id uuid,
  p_expected_version integer,
  p_new_owner_user_id uuid,
  p_new_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
  v_decision app.rbac_decision;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if v_lead.record_version <> p_expected_version then
    raise exception 'stale_version: lead % expected version % but found %', p_lead_id, p_expected_version, v_lead.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_lead.status = 'merged' then
    raise exception 'invalid_transition: lead % is merged and cannot be reassigned', p_lead_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lead.tenant_id, 'COM', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lead.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set owner_user_id = p_new_owner_user_id,
      org_unit_id = p_new_org_unit_id,
      assigned_at = now(),
      assigned_by = p_actor_label,
      last_activity_at = now(),
      record_version = record_version + 1
  where id = p_lead_id and record_version = p_expected_version
  returning * into v_lead;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_lead',
    'app.leads', v_lead.id, 'success', null, null,
    jsonb_build_object('new_owner_user_id', p_new_owner_user_id, 'new_org_unit_id', p_new_org_unit_id)
  );

  return v_lead;
end;
$$;

comment on function app.assign_lead is
  'COM-143: optimistic-concurrency-checked (p_expected_version) ownership transfer. Requires both COM:Assign entitlement and app.can_access_record() against the lead''s *current* owner/scope before transfer -- an actor cannot reassign a lead they cannot themselves access.';

-- Shared transition core for qualify/disqualify -- both wrap this with a fixed target
-- status and their own extra validation, avoiding three copies of the same optimistic-
-- concurrency-check-plus-audit boilerplate.
create function app.transition_lead_status(
  p_lead_id uuid,
  p_expected_version integer,
  p_new_status text,
  p_allowed_from_statuses text[],
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_action_name text
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if v_lead.record_version <> p_expected_version then
    raise exception 'stale_version: lead % expected version % but found %', p_lead_id, p_expected_version, v_lead.record_version
      using errcode = 'serialization_failure';
  end if;

  if not (v_lead.status = any(p_allowed_from_statuses)) then
    raise exception 'invalid_transition: lead % is % and cannot become %', p_lead_id, v_lead.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set status = p_new_status,
      disqualify_reason = case when p_new_status = 'disqualified' then p_reason else disqualify_reason end,
      qualified_at = case when p_new_status = 'qualified' then now() else qualified_at end,
      disqualified_at = case when p_new_status = 'disqualified' then now() else disqualified_at end,
      last_activity_at = now(),
      record_version = record_version + 1
  where id = p_lead_id and record_version = p_expected_version
  returning * into v_lead;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, p_action_name,
    'app.leads', v_lead.id, 'success', null, null,
    jsonb_build_object('new_status', p_new_status, 'reason', p_reason)
  );

  return v_lead;
end;
$$;

create function app.qualify_lead(
  p_lead_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  return app.transition_lead_status(
    p_lead_id, p_expected_version, 'qualified',
    array['new', 'contacted'], null, p_actor_auth_user_id, p_actor_label, 'qualify_lead'
  );
end;
$$;

create function app.disqualify_lead(
  p_lead_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: disqualifying a lead requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  return app.transition_lead_status(
    p_lead_id, p_expected_version, 'disqualified',
    array['new', 'contacted', 'qualified'], p_reason, p_actor_auth_user_id, p_actor_label, 'disqualify_lead'
  );
end;
$$;

comment on function app.disqualify_lead is
  'COM-143: reason is validated before app.transition_lead_status is ever called (Prompt 143 §24: "Disqualification requires a configured reason") -- the shared transition function''s own CHECK constraint on app.leads is the second, database-level line of defense, not the only one.';

create function app.merge_leads(
  p_survivor_lead_id uuid,
  p_duplicate_lead_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.leads
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_survivor app.leads;
  v_duplicate app.leads;
begin
  if p_survivor_lead_id = p_duplicate_lead_id then
    raise exception 'invalid_merge: a lead cannot be merged into itself' using errcode = 'check_violation';
  end if;

  select * into v_survivor from app.leads where id = p_survivor_lead_id;
  select * into v_duplicate from app.leads where id = p_duplicate_lead_id;
  if v_survivor.id is null or v_duplicate.id is null then
    raise exception 'lead_not_found: survivor % or duplicate %', p_survivor_lead_id, p_duplicate_lead_id
      using errcode = 'no_data_found';
  end if;

  if v_survivor.tenant_id <> v_duplicate.tenant_id then
    raise exception 'cross_tenant_merge_denied: survivor and duplicate belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_duplicate.status = 'merged' then
    raise exception 'invalid_merge: lead % is already merged', p_duplicate_lead_id using errcode = 'check_violation';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_survivor.tenant_id, v_survivor.owner_user_id,
      app.lead_record_scope_org_unit_ids(v_survivor.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_duplicate.tenant_id, v_duplicate.owner_user_id,
      app.lead_record_scope_org_unit_ids(v_duplicate.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both leads being merged', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set status = 'merged', merged_into_id = p_survivor_lead_id, merged_at = now(), merged_by = p_actor_label,
      last_activity_at = now(), record_version = record_version + 1
  where id = p_duplicate_lead_id
  returning * into v_duplicate;

  update app.leads set last_activity_at = now() where id = p_survivor_lead_id returning * into v_survivor;

  perform app.capture_audit_event(
    v_survivor.tenant_id, p_actor_auth_user_id, p_actor_label, 'merge_leads',
    'app.leads', v_duplicate.id, 'success', null, null,
    jsonb_build_object('survivor_lead_id', p_survivor_lead_id, 'duplicate_lead_id', p_duplicate_lead_id)
  );

  return v_survivor;
end;
$$;

comment on function app.merge_leads is
  'COM-143: the duplicate row is never deleted, only marked status=''merged''/merged_into_id -- the exact app.master_records.merged_into_id lineage-preservation pattern (PLT-120), reused here. Cross-tenant merge is structurally denied before any write.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.leads enable row level security;

-- Record-scope read policy: own lead (owner match), team/department/branch/company
-- scope (actor's org_unit is the lead's own unit or any of its ancestors), or Supreme
-- Admin -- all composed through app.can_access_record(), never a bespoke policy
-- expression. Tenant membership is enforced inside that function as a hard prerequisite.
create policy leads_select_scoped on app.leads
  for select to authenticated
  using (
    app.can_access_record(
      auth.uid(), tenant_id, owner_user_id,
      app.lead_record_scope_org_unit_ids(org_unit_id),
      null
    )
  );

grant usage on schema app to authenticated;
grant select on app.leads to authenticated, service_role;
-- Direct insert/update/delete stay ungranted for `authenticated` -- every mutation flows
-- through a SECURITY DEFINER function below, each performing its own entitlement
-- (app.evaluate_permission) and record-scope (app.can_access_record) check in-body.
-- Granting table-level INSERT/UPDATE to `authenticated` in addition would let a caller
-- bypass those functions entirely via a raw REST/PostgREST write -- not done here.
grant insert, update, delete on app.leads to service_role;

grant execute on function app.normalize_lead_email(text) to authenticated, service_role;
grant execute on function app.normalize_lead_phone(text) to authenticated, service_role;
grant execute on function app.compute_lead_duplicate_fingerprint(uuid, text, text, text) to authenticated, service_role;
grant execute on function app.compute_lead_score(app.leads) to authenticated, service_role;
grant execute on function app.lead_record_scope_org_unit_ids(uuid) to authenticated, service_role;
grant execute on function app.find_duplicate_leads(uuid, uuid, text, text, text) to authenticated, service_role;
grant execute on function app.capture_lead(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.score_lead(uuid, uuid) to authenticated, service_role;
grant execute on function app.assign_lead(uuid, integer, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.transition_lead_status(uuid, integer, text, text[], text, uuid, text, text) to authenticated, service_role;
grant execute on function app.qualify_lead(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.disqualify_lead(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.merge_leads(uuid, uuid, uuid, text) to authenticated, service_role;
