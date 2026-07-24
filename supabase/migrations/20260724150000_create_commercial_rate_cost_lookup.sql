-- Commercial capability COM-149 (Rate and Cost Lookup, CG-S7-COM-008)
-- The single canonical basic vendor/service/rate and internal-cost lookup foundation
-- consumed by Commercial (this migration) and extended by Phase 6 Procurement later
-- (Prompt 149 §4/§24). Per ADR-0015 (docs/adr/ADR-0015-commercial-vendor-service-rate-lookup-ownership.md),
-- this is the ONE new migration Commercial ever adds on top of PLT-120's master-data
-- foundation: exactly one child table (app.vendor_rate_versions) keyed by
-- master_record_id references app.master_records(id) (master_type_code constrained to
-- 'vendor_rate'), carrying the structured rate-version fields app.master_records'
-- generic attributes jsonb cannot index efficiently, plus read views -- never a second,
-- independently-writable rate master. Write authority for the interim period (Phase 2
-- through Phase 5, before Procurement ships) reuses app.is_support_grant_authority
-- unchanged, exactly as ADR-0015 mandates ("must not invent a parallel authority model").
--
-- Scope boundaries (disclosed, not silently narrowed):
--  1. Vendor/service identity is registered here via app.create_master_record under the
--     seeded 'vendor_rate' master type (PLT-120) -- this migration does not add a second
--     vendor-identity table; app.vendor_rate_versions is purely the structured detail
--     child, one row per priced version of one master_record.
--  2. 'service_type'/'mode'/'equipment_type' stay free text (mirrors COM-147/148's own
--     disclosed boundary) -- no Operations service-catalogue master exists yet.
--  3. app.search_vendor_rates is a bounded, single-lane comparison lookup (ordered by
--     cost, capped at p_limit, no cursor-based pagination) -- not a paginated full
--     master-data browse; app.search_master_records (PLT-120) already serves that
--     broader, generic purpose. Prompt 149's own scope is "look up and compare a
--     shortlist of rates for one lane/service," not "browse the entire rate catalogue."
--  4. Selecting a rate for one costing request (app.select_vendor_rate) snapshots the
--     exact rate-version detail at selection time into app.rate_selections -- a later
--     edit or supersede of the source vendor_rate_versions row never silently reprices
--     an already-issued quote (Prompt 149 §24), the same no-reentry snapshot rule every
--     prior Commercial capability follows (opportunities.requirements,
--     costing_requests.requirements_snapshot, ...).
--
-- Field masking reuses app.has_view_cost (COM-148) directly -- no new permission is
-- seeded here. Applies the COM-147/148 lesson from the start: every masked view below is
-- security_invoker = false with its own explicit row filter, since an invoker-mode view
-- cannot read a column-REVOKEd field at all (proven the hard way in COM-147's own build
-- log §3.3; no need to rediscover it a third time).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC before its final
-- grants, the standing per-migration convention since PLT-118.

create table app.vendor_rate_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.master_records (id),
  service_type text not null,
  mode text,
  origin_lane text not null,
  destination_lane text not null,
  equipment_type text,
  cargo_weight_min numeric(14, 3),
  cargo_weight_max numeric(14, 3),
  cargo_volume_min numeric(14, 3),
  cargo_volume_max numeric(14, 3),
  currency text not null,
  base_amount numeric(14, 2) not null,
  minimum_amount numeric(14, 2),
  surcharge_components jsonb not null default '[]'::jsonb,
  approval_status text not null default 'pending_approval',
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  supersedes_version_id uuid references app.vendor_rate_versions (id),
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_rate_versions_approval_status_check check (
    approval_status in ('pending_approval', 'approved', 'rejected', 'withdrawn', 'superseded')
  ),
  constraint vendor_rate_versions_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint vendor_rate_versions_base_amount_check check (base_amount >= 0),
  constraint vendor_rate_versions_minimum_amount_check check (minimum_amount is null or minimum_amount >= 0),
  constraint vendor_rate_versions_validity_check check (effective_to is null or effective_to > effective_from),
  constraint vendor_rate_versions_weight_range_check check (
    cargo_weight_min is null or cargo_weight_max is null or cargo_weight_min <= cargo_weight_max
  ),
  constraint vendor_rate_versions_volume_range_check check (
    cargo_volume_min is null or cargo_volume_max is null or cargo_volume_min <= cargo_volume_max
  ),
  constraint vendor_rate_versions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id),
  constraint vendor_rate_versions_rejected_reason_check check (
    (approval_status = 'rejected' and rejected_reason is not null and length(trim(rejected_reason)) > 0)
    or approval_status <> 'rejected'
  ),
  constraint vendor_rate_versions_withdrawn_reason_check check (
    (approval_status = 'withdrawn' and withdrawn_reason is not null and length(trim(withdrawn_reason)) > 0)
    or approval_status <> 'withdrawn'
  )
);

comment on table app.vendor_rate_versions is
  'COM-149: one structured, priced version row per (tenant, vendor_rate master record) -- the child detail table ADR-0015 mandates on top of app.master_records (PLT-120), never a second independently-writable rate master. A revision creates a new row (supersedes_version_id) and marks the prior superseded -- never edited in place, so any rate_selections snapshot already taken from a prior version stays exactly as it was quoted (Prompt 149 §24: "later rate edits never silently reprice an issued quote").';

create index vendor_rate_versions_tenant_lane_idx on app.vendor_rate_versions (tenant_id, origin_lane, destination_lane, service_type);
create index vendor_rate_versions_master_record_idx on app.vendor_rate_versions (master_record_id);
create index vendor_rate_versions_tenant_status_idx on app.vendor_rate_versions (tenant_id, approval_status);

create table app.rate_selections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  costing_request_id uuid not null references app.costing_requests (id),
  rate_version_id uuid references app.vendor_rate_versions (id),
  is_adhoc boolean not null default false,
  currency text not null,
  amount numeric(14, 2) not null,
  snapshot jsonb not null,
  override_reason text,
  selected_by text,
  created_at timestamptz not null default now(),
  constraint rate_selections_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint rate_selections_amount_check check (amount >= 0),
  constraint rate_selections_adhoc_shape_check check (
    (is_adhoc = false and rate_version_id is not null)
    or (is_adhoc = true and rate_version_id is null and override_reason is not null and length(trim(override_reason)) > 0)
  )
);

comment on table app.rate_selections is
  'COM-149: a point-in-time snapshot of the rate detail selected for one costing request -- never a live re-typed reference to app.vendor_rate_versions (the same no-reentry rule every prior Commercial capability follows). is_adhoc=true is a governed escape hatch for a quote with no canonical rate on file, and always requires a non-empty override_reason; selecting a non-approved rate_version also requires one (enforced in app.select_vendor_rate, not a CHECK constraint, since it requires a cross-table lookup).';

create index rate_selections_request_idx on app.rate_selections (costing_request_id);
create index rate_selections_rate_version_idx on app.rate_selections (rate_version_id);

-- Field-masked, all-statuses projection (COM-149, mirrors COM-148's
-- app.costing_responses_directory) -- security_invoker=false from the start (COM-147/148's
-- proven lesson, not rediscovered here). Adds its own explicit tenant-membership row
-- filter (mirrors app.master_records' own RLS shape -- vendor rates are tenant-wide
-- reference data, not per-owner/org-unit-scoped like leads/opportunities/costing
-- requests, so app.can_access_record is not the right primitive here).
create view app.vendor_rate_versions_directory
as
select
  v.id as rate_version_id,
  v.tenant_id,
  v.master_record_id,
  m.code as vendor_code,
  m.name as vendor_name,
  v.service_type,
  v.mode,
  v.origin_lane,
  v.destination_lane,
  v.equipment_type,
  v.cargo_weight_min,
  v.cargo_weight_max,
  v.cargo_volume_min,
  v.cargo_volume_max,
  case when app.has_view_cost(v.tenant_id) then v.currency else null end as currency,
  case when app.has_view_cost(v.tenant_id) then v.base_amount else null end as base_amount,
  case when app.has_view_cost(v.tenant_id) then v.minimum_amount else null end as minimum_amount,
  case when app.has_view_cost(v.tenant_id) then v.surcharge_components else null end as surcharge_components,
  not app.has_view_cost(v.tenant_id) as cost_masked,
  v.approval_status,
  v.effective_from,
  v.effective_to,
  v.supersedes_version_id,
  v.approved_by,
  v.approved_at,
  v.rejected_reason,
  v.withdrawn_reason,
  v.record_version,
  v.created_by,
  v.created_at,
  v.updated_at
from app.vendor_rate_versions v
join app.master_records m on m.id = v.master_record_id
where app.has_active_tenant_membership(v.tenant_id) or app.is_supreme_admin();

comment on view app.vendor_rate_versions_directory is
  'COM-149: field-masked projection of app.vendor_rate_versions across every approval_status (management/review view) -- currency/base_amount/minimum_amount/surcharge_components are nulled out (cost_masked=true) for any caller lacking the real, seeded COM:View cost permission. authenticated has no direct column-level grant on those four columns on app.vendor_rate_versions itself (see column grant below), forcing every read through this view.';

-- The exact convenience view docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §4 names
-- and ADR-0015 requires Commercial's lookup/comparison/snapshot service to query --
-- enhanced here (dropped and recreated, not CREATE OR REPLACE, since the column shape
-- changes entirely and nothing has consumed the PLT-120-seeded definition yet) to become
-- validity/approval-aware: only rows that are approved and currently within their
-- effective window, composed directly on top of app.vendor_rate_versions_directory so
-- the masking logic is defined in exactly one place.
drop view app.v_active_vendor_rates;

create view app.v_active_vendor_rates
as
select *
from app.vendor_rate_versions_directory
where approval_status = 'approved'
  and effective_from <= now()
  and (effective_to is null or effective_to > now());

comment on view app.v_active_vendor_rates is
  'COM-149: the same view name PLT-120 seeded (docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §4), now validity/approval-aware and composed on app.vendor_rate_versions_directory -- only approved, currently-effective rate versions, with the same cost masking. This is the read path app.search_vendor_rates queries.';

-- Field-masked projection of app.rate_selections (mirrors app.costing_responses_directory
-- exactly, scoped via can_access_record through the owning costing_request -- unlike
-- vendor_rate_versions itself, a rate_selection is tied to one costing request's own
-- record-scope, not tenant-wide reference data).
create view app.rate_selections_directory
as
select
  s.id,
  s.tenant_id,
  s.costing_request_id,
  s.rate_version_id,
  s.is_adhoc,
  case when app.has_view_cost(s.tenant_id) then s.currency else null end as currency,
  case when app.has_view_cost(s.tenant_id) then s.amount else null end as amount,
  case when app.has_view_cost(s.tenant_id) then s.snapshot else null end as snapshot,
  not app.has_view_cost(s.tenant_id) as cost_masked,
  s.override_reason,
  s.selected_by,
  s.created_at
from app.rate_selections s
join app.costing_requests cr on cr.id = s.costing_request_id
where app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null);

comment on view app.rate_selections_directory is
  'COM-149: field-masked projection of app.rate_selections -- currency/amount/snapshot are nulled out (cost_masked=true) for any caller lacking COM:View cost. Scoped via the owning costing_request''s own record-scope (app.can_access_record), the same join-through pattern app.costing_responses_directory established.';

create function app.create_rate_version(
  p_tenant_id uuid,
  p_vendor_code text,
  p_vendor_name text,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_equipment_type text,
  p_cargo_weight_min numeric,
  p_cargo_weight_max numeric,
  p_cargo_volume_min numeric,
  p_cargo_volume_max numeric,
  p_currency text,
  p_base_amount numeric,
  p_minimum_amount numeric,
  p_surcharge_components jsonb,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_master_record_id uuid;
  v_prior app.vendor_rate_versions;
  v_new app.vendor_rate_versions;
begin
  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_prior from app.vendor_rate_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_prior.tenant_id <> p_tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_supersedes_version_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
    if v_prior.approval_status not in ('pending_approval', 'approved') then
      raise exception 'invalid_transition: rate version % is % and cannot be superseded', p_supersedes_version_id, v_prior.approval_status
        using errcode = 'check_violation';
    end if;
    -- A revision stays under the same vendor/lane identity as its source -- the master
    -- record is never re-resolved from p_vendor_code/p_vendor_name on this branch.
    v_master_record_id := v_prior.master_record_id;
  else
    -- Idempotent get-or-create of the vendor/lane identity row (PLT-120) -- a repeated
    -- call with the same code returns the existing master record, never a duplicate.
    select id into v_master_record_id from app.create_master_record(
      'vendor_rate', p_tenant_id, p_vendor_code, p_vendor_name, '[]'::jsonb, '{}'::jsonb, p_actor_auth_user_id, p_actor_label
    );
  end if;

  insert into app.vendor_rate_versions (
    tenant_id, master_record_id, service_type, mode, origin_lane, destination_lane, equipment_type,
    cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
    currency, base_amount, minimum_amount, surcharge_components,
    effective_from, effective_to, supersedes_version_id, created_by
  ) values (
    p_tenant_id, v_master_record_id, p_service_type, p_mode, p_origin_lane, p_destination_lane, p_equipment_type,
    p_cargo_weight_min, p_cargo_weight_max, p_cargo_volume_min, p_cargo_volume_max,
    p_currency, p_base_amount, p_minimum_amount, coalesce(p_surcharge_components, '[]'::jsonb),
    coalesce(p_effective_from, now()), p_effective_to, p_supersedes_version_id, p_actor_label
  )
  returning * into v_new;

  if p_supersedes_version_id is not null then
    update app.vendor_rate_versions
    set approval_status = 'superseded', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_rate_version',
    'app.vendor_rate_versions', v_new.id, 'success', null, null, to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.create_rate_version is
  'COM-149: gated by app.is_support_grant_authority (Supreme Admin or tenant_admin), reused unchanged per ADR-0015 -- no parallel authority model. p_supersedes_version_id is optional: when supplied, the new row inherits the source''s master_record_id (never re-resolves vendor identity) and immediately marks the source superseded, the same "revise = create new + mark old superseded" pattern every prior Commercial capability follows (never an in-place edit).';

create function app.approve_rate_version(
  p_rate_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be approved', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'approved', approved_by = p_actor_label, approved_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', null, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$$;

create function app.reject_rate_version(
  p_rate_version_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: rejecting a rate version requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be rejected', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'rejected', rejected_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$$;

create function app.withdraw_rate_version(
  p_rate_version_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: withdrawing a rate version requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'approved' then
    raise exception 'invalid_transition: rate version % is % and only an approved rate can be withdrawn', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'withdrawn', withdrawn_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$$;

-- Bounded, single-lane comparison lookup (task boundary 3 above) -- ordered by cost.
-- Ordering by the already-masked base_amount column is safe: masking is a per-caller
-- (not per-row) decision (app.has_view_cost(p_tenant_id, p_actor_auth_user_id) is
-- constant for the whole call), so a caller lacking COM:View cost sees every row's
-- base_amount as null and the ORDER BY degrades to the deterministic tie-break columns
-- alone -- no relative-cost signal ever leaks through sort position.
--
-- Deliberately queries app.vendor_rate_versions/app.master_records directly rather than
-- app.v_active_vendor_rates / app.vendor_rate_versions_directory: those views mask and
-- scope visibility via app.has_view_cost/app.has_active_tenant_membership's *default*
-- auth.uid() argument (the real-session path every other Commercial *_directory view
-- uses, since it is normally queried straight from PostgREST under the caller's own
-- JWT). This function, like every other Commercial function, authenticates its actor via
-- an explicit p_actor_auth_user_id parameter instead -- composing it on top of a view
-- keyed to auth.uid() would silently return zero rows whenever this function is called
-- without a live session GUC set (found the hard way authoring this capability's own
-- db-test suite). Explicit-actor masking keeps this function correct regardless of the
-- calling context, and does not duplicate business logic: the approved/current-window
-- filter and the cost-masking CASE expressions are the same ones those views apply.
create function app.search_vendor_rates(
  p_tenant_id uuid,
  p_service_type text,
  p_origin_lane text,
  p_destination_lane text,
  p_mode text,
  p_actor_auth_user_id uuid,
  p_limit integer default 20
)
returns setof app.vendor_rate_versions_directory
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.tenant_id = p_tenant_id
    and v.approval_status = 'approved'
    and v.effective_from <= now()
    and (v.effective_to is null or v.effective_to > now())
    and (p_service_type is null or v.service_type = p_service_type)
    and (p_origin_lane is null or v.origin_lane = p_origin_lane)
    and (p_destination_lane is null or v.destination_lane = p_destination_lane)
    and (p_mode is null or v.mode = p_mode)
  order by base_amount nulls last, vendor_code, rate_version_id
  limit least(coalesce(p_limit, 20), 200);
end;
$$;

comment on function app.search_vendor_rates is
  'COM-149: a bounded shortlist lookup for one lane/service (<=200 rows, no cursor pagination -- app.search_master_records already serves generic full-catalogue browsing). Requires COM:View. Queries app.v_active_vendor_rates (approved, currently-effective only) so a masked caller still gets a usable comparison, just without cost figures.';

create function app.select_vendor_rate(
  p_costing_request_id uuid,
  p_rate_version_id uuid,
  p_is_adhoc boolean,
  p_adhoc_currency text,
  p_adhoc_amount numeric,
  p_override_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rate_selections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
begin
  select * into v_request from app.costing_requests where id = p_costing_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_costing_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot accept a rate selection', p_costing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to select a rate', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_costing_request_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_is_adhoc then
    if p_override_reason is null or length(trim(p_override_reason)) = 0 then
      raise exception 'reason_required: an ad-hoc rate selection requires a non-empty override reason'
        using errcode = 'not_null_violation';
    end if;
    if p_adhoc_currency is null or p_adhoc_currency !~ '^[A-Z]{3}$' or p_adhoc_amount is null or p_adhoc_amount < 0 then
      raise exception 'invalid_adhoc_rate: an ad-hoc selection requires a valid 3-letter currency and a non-negative amount'
        using errcode = 'check_violation';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, null, true, p_adhoc_currency, p_adhoc_amount,
      jsonb_build_object('is_adhoc', true, 'currency', p_adhoc_currency, 'amount', p_adhoc_amount, 'override_reason', p_override_reason),
      p_override_reason, p_actor_label
    )
    returning * into v_selection;
  else
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_request.tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_rate_version_id, v_request.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_rate.approval_status <> 'approved' and (p_override_reason is null or length(trim(p_override_reason)) = 0) then
      raise exception 'reason_required: selecting a % (not approved) rate version requires a non-empty override reason', v_rate.approval_status
        using errcode = 'not_null_violation';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, v_rate.id, false, v_rate.currency, v_rate.base_amount, to_jsonb(v_rate), p_override_reason, p_actor_label
    )
    returning * into v_selection;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'select_vendor_rate',
    'app.rate_selections', v_selection.id, 'success', null, null,
    jsonb_build_object('costing_request_id', p_costing_request_id, 'is_adhoc', v_selection.is_adhoc, 'rate_version_id', v_selection.rate_version_id)
  );

  return v_selection;
end;
$$;

comment on function app.select_vendor_rate is
  'COM-149: requires both COM:Edit and COM:View cost (mirrors app.submit_costing_response''s dual gate -- an actor cannot commit a cost figure to a costing request they are not entitled to see back). Snapshots the exact rate detail (or an ad-hoc entry) at selection time into app.rate_selections -- never a live reference. An ad-hoc selection, or selecting a non-approved rate version, always requires a non-empty override_reason (a governed escape hatch, not a silent bypass).';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.vendor_rate_versions enable row level security;
alter table app.rate_selections enable row level security;

-- Base-table select is tenant-wide (mirrors app.master_records' own RLS shape -- vendor
-- rates are tenant reference data, not per-owner/org-unit-scoped), but the four sensitive
-- columns are additionally withheld at the column-grant layer below --
-- app.vendor_rate_versions_directory / app.v_active_vendor_rates are the only paths that
-- can ever surface them, and only to a caller holding COM:View cost.
create policy vendor_rate_versions_select_scoped on app.vendor_rate_versions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy rate_selections_select_scoped on app.rate_selections
  for select to authenticated
  using (
    exists (
      select 1 from app.costing_requests cr
      where cr.id = rate_selections.costing_request_id
        and app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
    )
  );

grant usage on schema app to authenticated;

-- The database guarantee (matches PLT-114/COM-147/148's own proven technique): a bare
-- column-level REVOKE cannot carve an exception out of a broader table-level GRANT -- the
-- table-level grant must be revoked entirely and re-granted on an explicit column list
-- that omits the four cost-bearing columns.
grant select (
  id, tenant_id, master_record_id, service_type, mode, origin_lane, destination_lane, equipment_type,
  cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
  approval_status, effective_from, effective_to, supersedes_version_id,
  approved_by, approved_at, rejected_reason, withdrawn_reason,
  record_version, created_by, created_at, updated_at
) on app.vendor_rate_versions to authenticated;
grant select on app.vendor_rate_versions to service_role;

grant select (
  id, tenant_id, costing_request_id, rate_version_id, is_adhoc, override_reason, selected_by, created_at
) on app.rate_selections to authenticated;
grant select on app.rate_selections to service_role;

grant select on app.vendor_rate_versions_directory to authenticated, service_role;
grant select on app.v_active_vendor_rates to authenticated, service_role;
grant select on app.rate_selections_directory to authenticated, service_role;

grant execute on function app.create_rate_version(uuid, text, text, text, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, numeric, jsonb, timestamptz, timestamptz, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.approve_rate_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reject_rate_version(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_rate_version(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.search_vendor_rates(uuid, text, text, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.select_vendor_rate(uuid, uuid, boolean, text, numeric, text, uuid, text) to authenticated, service_role;
