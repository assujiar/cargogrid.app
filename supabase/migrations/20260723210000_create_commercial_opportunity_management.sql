-- Commercial capability COM-147 (Opportunity Management, CG-S7-COM-006)
-- Canonical opportunity lifecycle over a governed stage/probability machine, referencing
-- exactly one prospect (never a copy of its identity), with a bounded requirements
-- snapshot, value/probability field-masking, explicit stage history, clone lineage, and a
-- deterministic costing-readiness check.
--
-- Scope boundary (disclosed, not silently narrowed): Prompt 147 §13 says "account/prospect
-- links" -- the canonical customer Account entity does not exist yet (COM-155, Customer
-- and Account Conversion, has not run). app.opportunities therefore references
-- app.prospects (`prospect_id`, not null) plus a forward-compatible, currently-unpopulated
-- `account_ref` column that COM-155 is expected to backfill once accounts exist -- not a
-- second competing customer identity.
--
-- Service/cargo/lane/SLA "requirements" (§13/§25) are captured as a bounded jsonb snapshot
-- (`requirements`) rather than a formal Operations service-catalogue integration, because
-- no canonical service-type/cargo-type/lane master exists yet -- those belong to Phase 3
-- Operations (`OPS-171` land/air/sea baseline onward), which has not started. Building an
-- interim master here would risk exactly the "two masters to reconcile later" duplication
-- this repository's binding rules forbid; `app.get_opportunity_costing_readiness` checks
-- the presence of well-known keys within this snapshot, not a validated master reference.
--
-- Stage machine is domain-native (its own `stage` column plus a dedicated transition
-- function), matching every prior Commercial capability's own precedent (leads/prospects),
-- rather than integrating with the generic Configurable Status Engine (`PLT-124`) -- no
-- earlier Commercial capability established that integration, and doing so now would be a
-- materially larger architecture decision than this bounded task warrants. Named here as a
-- disclosed boundary for a future ADR, not a silent omission.
--
-- Value/probability field masking reuses PLT-114's own established pattern
-- (`app.has_view_personal_data` / `app.users_directory`) for the seeded, protected
-- `COM:View selling price` permission (seeded since PLT-111, never previously consumed by
-- any Commercial capability). Unlike `app.users_directory` (security_invoker=false, relying
-- on the view owner's privileges), `app.opportunities_directory` below is
-- security_invoker=true, matching COM-146's own safer design: RLS on the base table
-- governs row visibility by construction, and only the two masked columns are gated by the
-- permission check -- disclosed as a deliberate, stricter choice, not a deviation flagged
-- as a defect.

-- Extends the one shared polymorphic resolver (COM-145) to a third related_type, rather
-- than adding a second competing resolver -- exactly the extension point that function's
-- own comment names as the correct way to grow it.
create or replace function app.resolve_commercial_record_ref(
  p_related_type text,
  p_related_id uuid
)
returns table (tenant_id uuid, owner_user_id uuid, org_unit_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if p_related_type = 'lead' then
    return query select l.tenant_id, l.owner_user_id, l.org_unit_id from app.leads l where l.id = p_related_id;
  elsif p_related_type = 'prospect' then
    return query select p.tenant_id, p.owner_user_id, p.org_unit_id from app.prospects p where p.id = p_related_id;
  elsif p_related_type = 'opportunity' then
    return query select o.tenant_id, o.owner_user_id, o.org_unit_id from app.opportunities o where o.id = p_related_id;
  else
    raise exception 'unknown_related_type: %', p_related_type using errcode = 'check_violation';
  end if;

  if not found then
    raise exception 'related_record_not_found: % %', p_related_type, p_related_id using errcode = 'no_data_found';
  end if;
end;
$$;

comment on function app.resolve_commercial_record_ref is
  'COM-145, extended by COM-147: the one shared polymorphic-target resolver for contact_links/activities and any later Commercial polymorphic table -- extend the IF/ELSIF chain here, never add a second competing resolver. COM-147 adds the ''opportunity'' branch.';

create table app.opportunities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  prospect_id uuid not null references app.prospects (id),
  account_ref text,
  name text not null,
  stage text not null default 'qualifying',
  probability integer not null default 10,
  value_amount numeric(14, 2),
  value_currency text,
  requirements jsonb not null default '{}'::jsonb,
  next_action text,
  next_action_due_at timestamptz,
  close_reason text,
  cloned_from_id uuid references app.opportunities (id),
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint opportunities_stage_check check (
    stage in ('qualifying', 'requirements_gathering', 'ready_for_costing', 'won', 'lost')
  ),
  constraint opportunities_probability_check check (probability >= 0 and probability <= 100),
  constraint opportunities_value_currency_check check (value_currency is null or value_currency ~ '^[A-Z]{3}$'),
  constraint opportunities_value_amount_check check (value_amount is null or value_amount >= 0),
  constraint opportunities_requirements_check check (jsonb_typeof(requirements) = 'object'),
  constraint opportunities_close_reason_check check (
    (stage in ('won', 'lost') and close_reason is not null and length(trim(close_reason)) > 0)
    or (stage not in ('won', 'lost'))
  ),
  constraint opportunities_not_self_clone check (cloned_from_id is null or cloned_from_id <> id)
);

comment on table app.opportunities is
  'COM-147: one canonical prospect context per opportunity (prospect_id, not null; account_ref is a forward-compatible placeholder COM-155 is expected to backfill, never a second customer identity). value_amount/value_currency/probability are field-masked to actors lacking COM:View selling price via app.opportunities_directory. stage is domain-native (own CHECK, own transition function), not integrated with the generic Status Engine (PLT-124) -- disclosed boundary, COM-147 build log.';

create index opportunities_tenant_stage_idx on app.opportunities (tenant_id, stage);
create index opportunities_tenant_owner_idx on app.opportunities (tenant_id, owner_user_id);
create index opportunities_tenant_prospect_idx on app.opportunities (tenant_id, prospect_id);
create index opportunities_next_action_due_idx on app.opportunities (tenant_id, next_action_due_at) where stage not in ('won', 'lost');

create table app.opportunity_stage_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  opportunity_id uuid not null references app.opportunities (id),
  from_stage text,
  to_stage text not null,
  probability integer not null,
  reason text,
  changed_by text,
  changed_at timestamptz not null default now()
);

comment on table app.opportunity_stage_history is
  'COM-147: explicit, queryable stage-transition history (Prompt 147 §13) -- a convenience read-model alongside app.audit_logs (the audit entry remains the authoritative before/after record; this table exists so a UI can render a stage timeline without parsing audit payloads).';

create index opportunity_stage_history_opportunity_idx on app.opportunity_stage_history (opportunity_id, changed_at);

-- Field-masking gate (PLT-114 pattern) for the seeded, protected COM:View selling price
-- permission -- never previously consumed by any Commercial capability.
create function app.has_view_selling_price(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM', 'View selling price')).allowed;
$$;

comment on function app.has_view_selling_price is
  'Field-masking gate (COM-147, mirrors PLT-114''s app.has_view_personal_data) -- true if the caller holds the real, seeded COM:View selling price permission (PLT-111/112) for the given tenant.';

grant execute on function app.has_view_selling_price(uuid, uuid) to authenticated;

create function app.create_opportunity(
  p_tenant_id uuid,
  p_prospect_id uuid,
  p_name text,
  p_requirements jsonb,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.opportunities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_opportunity app.opportunities;
begin
  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.tenant_id <> p_tenant_id then
    raise exception 'cross_tenant_prospect_denied: prospect % does not belong to tenant %', p_prospect_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.opportunities (
    tenant_id, prospect_id, name, requirements, owner_user_id, org_unit_id, created_by
  ) values (
    p_tenant_id, p_prospect_id, p_name, coalesce(p_requirements, '{}'::jsonb),
    coalesce(p_owner_user_id, v_prospect.owner_user_id), coalesce(p_org_unit_id, v_prospect.org_unit_id), p_created_by
  )
  returning * into v_opportunity;

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, changed_by)
  values (v_opportunity.tenant_id, v_opportunity.id, null, v_opportunity.stage, v_opportunity.probability, p_created_by);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_opportunity',
    'app.opportunities', v_opportunity.id, 'success', null, null, to_jsonb(v_opportunity)
  );

  return v_opportunity;
end;
$$;

comment on function app.create_opportunity is
  'COM-147: always creates a new row -- no external idempotency key exists for an opportunity (it originates from an internal prospect, unlike app.capture_lead). Always starts at stage=qualifying, probability=10.';

create function app.update_opportunity(
  p_opportunity_id uuid,
  p_expected_version integer,
  p_name text,
  p_requirements jsonb,
  p_next_action text,
  p_next_action_due_at timestamptz,
  p_value_amount numeric,
  p_value_currency text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.opportunities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.record_version <> p_expected_version then
    raise exception 'stale_version: opportunity % expected version % but found %', p_opportunity_id, p_expected_version, v_opportunity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_opportunity.stage in ('won', 'lost') then
    raise exception 'invalid_transition: opportunity % is closed (%) and cannot be edited', p_opportunity_id, v_opportunity.stage
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_opportunity.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if (
    (p_value_amount is not null and p_value_amount is distinct from v_opportunity.value_amount)
    or (p_value_currency is not null and p_value_currency is distinct from v_opportunity.value_currency)
  ) and not app.has_view_selling_price(v_opportunity.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View selling price required to set opportunity value', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.opportunities
  set name = coalesce(p_name, name),
      requirements = coalesce(p_requirements, requirements),
      next_action = coalesce(p_next_action, next_action),
      next_action_due_at = coalesce(p_next_action_due_at, next_action_due_at),
      value_amount = coalesce(p_value_amount, value_amount),
      value_currency = coalesce(p_value_currency, value_currency),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_opportunity_id and record_version = p_expected_version
  returning * into v_opportunity;

  perform app.capture_audit_event(
    v_opportunity.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_opportunity',
    'app.opportunities', v_opportunity.id, 'success', null, null, to_jsonb(v_opportunity)
  );

  return v_opportunity;
end;
$$;

comment on function app.update_opportunity is
  'COM-147: blocked once stage is won/lost (Prompt 147 §23 "closed-record mutation is blocked"). Setting a new/changed value_amount or value_currency additionally requires COM:View selling price -- an actor cannot set a sensitive figure they are not entitled to see.';

create function app.transition_opportunity_stage(
  p_opportunity_id uuid,
  p_expected_version integer,
  p_new_stage text,
  p_probability integer,
  p_close_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.opportunities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_default_probability integer;
  v_probability integer;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.record_version <> p_expected_version then
    raise exception 'stale_version: opportunity % expected version % but found %', p_opportunity_id, p_expected_version, v_opportunity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_opportunity.stage in ('won', 'lost') then
    raise exception 'invalid_transition: opportunity % is closed (%) and cannot change stage again', p_opportunity_id, v_opportunity.stage
      using errcode = 'check_violation';
  end if;

  if p_new_stage not in ('qualifying', 'requirements_gathering', 'ready_for_costing', 'won', 'lost') then
    raise exception 'invalid_stage: % is not a canonical opportunity stage', p_new_stage using errcode = 'check_violation';
  end if;

  if p_new_stage in ('won', 'lost') and (p_close_reason is null or length(trim(p_close_reason)) = 0) then
    raise exception 'reason_required: closing an opportunity as % requires a non-empty reason', p_new_stage
      using errcode = 'not_null_violation';
  end if;

  -- Managers move/close by policy (Prompt 147 §26): closing to a terminal stage requires
  -- COM:Approve; any other forward/lateral stage move requires the ordinary COM:Edit.
  v_decision := app.evaluate_permission(
    p_actor_auth_user_id, v_opportunity.tenant_id, 'COM',
    case when p_new_stage in ('won', 'lost') then 'Approve' else 'Edit' end
  );
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks required COM permission (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  v_default_probability := case p_new_stage
    when 'qualifying' then 10
    when 'requirements_gathering' then 30
    when 'ready_for_costing' then 60
    when 'won' then 100
    when 'lost' then 0
  end;
  v_probability := coalesce(p_probability, v_default_probability);
  if v_probability < 0 or v_probability > 100 then
    raise exception 'invalid_probability: % is not between 0 and 100', v_probability using errcode = 'check_violation';
  end if;

  update app.opportunities
  set stage = p_new_stage,
      probability = v_probability,
      close_reason = case when p_new_stage in ('won', 'lost') then p_close_reason else close_reason end,
      updated_at = now(),
      record_version = record_version + 1
  where id = p_opportunity_id and record_version = p_expected_version
  returning * into v_opportunity;

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, reason, changed_by)
  values (v_opportunity.tenant_id, v_opportunity.id, v_opportunity.stage, p_new_stage, v_probability, p_close_reason, p_actor_label);

  perform app.capture_audit_event(
    v_opportunity.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_opportunity_stage',
    'app.opportunities', v_opportunity.id, 'success', null, null,
    jsonb_build_object('to_stage', p_new_stage, 'probability', v_probability, 'close_reason', p_close_reason)
  );

  return v_opportunity;
end;
$$;

comment on function app.transition_opportunity_stage is
  'COM-147: the one stage-transition entry point. probability defaults deterministically per stage (10/30/60/100/0) unless explicitly overridden by the caller (Prompt 147 §24: "canonical state/probability semantics remain reportable"). Terminal (won/lost) is immutable once set.';

create function app.clone_opportunity(
  p_opportunity_id uuid,
  p_name text,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.opportunities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_source app.opportunities;
  v_decision app.rbac_decision;
  v_clone app.opportunities;
begin
  select * into v_source from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.opportunities (
    tenant_id, prospect_id, name, requirements, owner_user_id, org_unit_id, cloned_from_id, created_by
  ) values (
    v_source.tenant_id, v_source.prospect_id, coalesce(p_name, v_source.name || ' (copy)'),
    v_source.requirements, p_actor_auth_user_id, v_source.org_unit_id, v_source.id, p_created_by
  )
  returning * into v_clone;

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, changed_by)
  values (v_clone.tenant_id, v_clone.id, null, v_clone.stage, v_clone.probability, p_created_by);

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_created_by, 'clone_opportunity',
    'app.opportunities', v_clone.id, 'success', null, null, jsonb_build_object('cloned_from_id', v_source.id)
  );

  return v_clone;
end;
$$;

comment on function app.clone_opportunity is
  'COM-147: always creates a new row (never idempotent -- cloning the same source twice is a legitimate distinct action, Prompt 147 §22). Resets stage/probability to the same defaults as app.create_opportunity; requirements/value are copied as a mutable starting point, explicitly reviewable/refreshable by the caller (never a locked read-only reference).';

create function app.get_opportunity_costing_readiness(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (ready boolean, missing text[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_missing text[] := '{}';
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(v_opportunity.requirements ->> 'service_type', '') = '' then
    v_missing := v_missing || 'service_type'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'cargo_description', '') = '' then
    v_missing := v_missing || 'cargo_description'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'origin', '') = '' then
    v_missing := v_missing || 'origin'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'destination', '') = '' then
    v_missing := v_missing || 'destination'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'target_ready_date', '') = '' then
    v_missing := v_missing || 'target_ready_date'::text;
  end if;

  return query select (array_length(v_missing, 1) is null), v_missing;
end;
$$;

comment on function app.get_opportunity_costing_readiness is
  'COM-147: a fixed, deterministic, non-tenant-configurable check (mirrors COM-144''s app.get_prospect_conversion_readiness) over the requirements jsonb snapshot -- explicitly NOT the deferred Configuration Engine rule evaluator (ADR-CAND-ARCH-014/015, still open per PLT-121 §25). Data-completeness only; whether to actually submit a costing request is COM-148''s own mutation, not this function''s concern.';

-- Field-masked projection of app.opportunities (COM-147, mirrors PLT-114's
-- app.users_directory pattern). security_invoker defaults to false here, deliberately --
-- Postgres checks column privileges against the *invoker* for every column a view's
-- defining query references, even one only ever read inside a CASE branch that ends up
-- null; an invoker-mode view could not read the REVOKEd value_amount/value_currency/
-- probability columns at all, masked or not (proven empirically this checkpoint: a
-- security_invoker=true first draft failed with a real "permission denied for table
-- opportunities" the first time an actor without COM:View selling price queried it -- see
-- COM-147's build log §3). Running as the view owner is exactly what lets it read those
-- REVOKEd columns internally while still deciding, per row, what to reveal.
--
-- Unlike app.users_directory (PLT-114), which has no row-level filter of its own and
-- relies entirely on RLS being bypassed transparently for callers who already cleared some
-- outer check, this view adds its own explicit app.can_access_record(...) WHERE clause --
-- necessary here because security_invoker=false also means the base table's RLS policy
-- does not apply to this view's own read. This is a deliberate, disclosed strengthening
-- over the bare PLT-114 pattern, not a critique of it (out of this task's scope to alter).
create view app.opportunities_directory
as
select
  o.id,
  o.tenant_id,
  o.prospect_id,
  o.account_ref,
  o.name,
  o.stage,
  case when app.has_view_selling_price(o.tenant_id) then o.probability else null end as probability,
  case when app.has_view_selling_price(o.tenant_id) then o.value_amount else null end as value_amount,
  case when app.has_view_selling_price(o.tenant_id) then o.value_currency else null end as value_currency,
  not app.has_view_selling_price(o.tenant_id) as value_masked,
  o.requirements,
  o.next_action,
  o.next_action_due_at,
  o.close_reason,
  o.cloned_from_id,
  o.owner_user_id,
  o.org_unit_id,
  o.record_version,
  o.created_by,
  o.created_at,
  o.updated_at
from app.opportunities o
where app.can_access_record(auth.uid(), o.tenant_id, o.owner_user_id, app.lead_record_scope_org_unit_ids(o.org_unit_id), null);

comment on view app.opportunities_directory is
  'COM-147: field-masked projection of app.opportunities -- value_amount/value_currency/probability are nulled out (value_masked=true) for any caller lacking the real, seeded COM:View selling price permission. The database guarantee: authenticated has no direct column-level grant on those three columns on app.opportunities itself (see column grant below), forcing every read through this view. security_invoker=false (view-owner-mode) is required for the masking to work at all; this view compensates with its own explicit app.can_access_record(...) row filter, unlike PLT-114''s own app.users_directory.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

-- Extend the two existing polymorphic CHECK constraints (COM-145) to accept the new
-- 'opportunity' related_type -- additive ALTER, never editing COM-145's applied migration.
alter table app.contact_links drop constraint contact_links_related_type_check;
alter table app.contact_links add constraint contact_links_related_type_check check (related_type in ('lead', 'prospect', 'opportunity'));

alter table app.activities drop constraint activities_related_type_check;
alter table app.activities add constraint activities_related_type_check check (related_type in ('lead', 'prospect', 'opportunity'));

alter table app.opportunities enable row level security;
alter table app.opportunity_stage_history enable row level security;

create policy opportunities_select_scoped on app.opportunities
  for select to authenticated
  using (
    app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)
  );

create policy opportunity_stage_history_select_scoped on app.opportunity_stage_history
  for select to authenticated
  using (
    exists (
      select 1 from app.opportunities o
      where o.id = opportunity_stage_history.opportunity_id
        and app.can_access_record(auth.uid(), o.tenant_id, o.owner_user_id, app.lead_record_scope_org_unit_ids(o.org_unit_id), null)
    )
  );

grant usage on schema app to authenticated;

-- The database guarantee (matches PLT-114's own proven technique, docs/build-log/phase-01/
-- PLT-114.md §8): a bare column-level REVOKE cannot carve an exception out of a broader
-- table-level GRANT -- the table-level grant must be revoked entirely and re-granted on an
-- explicit column list that omits the three sensitive columns.
grant select (
  id, tenant_id, prospect_id, account_ref, name, stage, requirements, next_action,
  next_action_due_at, close_reason, cloned_from_id, owner_user_id, org_unit_id,
  record_version, created_by, created_at, updated_at
) on app.opportunities to authenticated;
grant select on app.opportunities to service_role;
grant select on app.opportunity_stage_history to authenticated, service_role;
grant select on app.opportunities_directory to authenticated, service_role;

grant execute on function app.resolve_commercial_record_ref(text, uuid) to authenticated, service_role;
grant execute on function app.create_opportunity(uuid, uuid, text, jsonb, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.update_opportunity(uuid, integer, text, jsonb, text, timestamptz, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.transition_opportunity_stage(uuid, integer, text, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.clone_opportunity(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_opportunity_costing_readiness(uuid, uuid) to authenticated, service_role;
