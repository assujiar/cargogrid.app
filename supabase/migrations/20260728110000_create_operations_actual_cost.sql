-- Operations capability OPS-178 (Actual Cost, CG-S8-OPS-012)
-- Componentized, exact (numeric, never float) actual-cost capture with vendor/internal
-- source and assignment/document lineage, approval, and estimated-versus-actual
-- variance -- operational cost recording only, no Finance/AP posting (Prompt 178 §4/§24).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **No new permission action is registered.** `OPS-174` already registered
--   `OPS:View cost` (the pre-approved, fixed 19-action `PLT-111` vocabulary, paired
--   with the `OPS` module) for exactly this "restrict sensitive cost data" purpose.
--   `app.has_view_actual_cost` is this capability's own thin wrapper over the identical
--   `app.evaluate_permission(..., 'OPS', 'View cost')` check -- the same
--   "one shared permission action, one wrapper function per consuming capability"
--   precedent `COM-148`'s `has_view_cost`/`COM-156`'s `has_view_margin`/`OPS-174`'s
--   `has_view_exception_cost` already established. Writing cost data
--   (`app.add_actual_cost_component`) requires both `OPS:Edit` and `OPS:View cost` --
--   an actor who cannot see this data cannot blindly set it either.
-- * **A cost component is either fully visible or fully hidden, never field-masked.**
--   Unlike `app.job_orders_directory`/`app.exceptions_directory` (which null out a
--   handful of columns on an otherwise-visible row), every column on a cost component
--   is itself cost-shaped (rate, vendor, amount) -- there is no partial "safe"
--   projection of a line item. `app.shipment_actual_cost_components` therefore grants
--   `authenticated` no direct table access at all (service_role only); the only read
--   path is `app.list_actual_cost_components`, which denies outright (no partial
--   result) to an actor lacking `OPS:View cost`. The header row's own `total_amount`/
--   `estimated_amount` are similarly cost-shaped, so `app.shipment_actual_costs_directory`
--   masks those two columns (not the whole row) for a record-scoped actor lacking
--   `OPS:View cost` -- status/version/currency remain visible (matches Prompt 178 §26's
--   "sellers/customers/public cannot infer restricted cost" while still letting a
--   non-cost-viewer see that a cost record exists and its lifecycle state).
-- * **Exact decimal arithmetic, never float** (§24/§25): `numeric(14,4)` for
--   quantity/rate, `numeric(14,2)` for every money-shaped column, matching every other
--   money column in this repository. `app.compute_actual_cost_component_amount` is the
--   one place `greatest(quantity * rate, coalesce(minimum_charge, 0)) + surcharge` is
--   computed and rounded (`round(..., 2)`, Postgres's own round-half-away-from-zero for
--   `numeric` -- the exact "half up" semantics this migration commits to; no
--   configurable rounding-mode column is added, since no second mode is actually
--   implemented -- inventing an unused config knob would misrepresent scope).
-- * **Estimated cost is an optional, actor-supplied snapshot, never fabricated.**
--   `docs/build-log/phase-03/00_OPERATIONS_WBS.md` §3 already disclosed that
--   `app.job_orders.revenue_snapshot` carries the Commercial *selling*-price basis
--   Phase 4/`OPS-179` profitability will read -- it is not a vendor-cost baseline, and
--   Commercial's own vendor rate-selection detail (`app.rate_selections`/
--   `app.vendor_rate_versions`) was deliberately never copied onto the Job Order (same
--   field-mapping document). No governed actual-cost estimate exists anywhere in this
--   repository yet to compare against, so `estimated_amount` is recorded verbatim as
--   whatever value the draft's own creator supplies (nullable) -- `app.evaluate_actual_cost_variance`
--   returns `variance_available=false` rather than fabricating a linkage to a table this
--   capability has no governed right to read.
-- * **Versioned, adjustments preserve lineage, never silently overwritten** (§24):
--   `app.shipment_actual_costs` is a `draft -> submitted -> approved|rejected` lifecycle,
--   one row per version; `app.create_actual_cost_adjustment` only starts from an
--   `approved` version, copies its component lines onto a brand-new draft version (new
--   ids, `supersedes_version_id` set), and flips the prior version's own `is_current` to
--   false -- the prior approved version and its components are never deleted or mutated.
-- * **No Finance/AP/tax/journal/settlement scope is introduced** (§24): this migration
--   creates zero vendor-bill, ledger, or payment table; `amount`/`currency` are recorded,
--   non-authoritative-for-payment operational figures, the same disclosed boundary
--   `OPS-174`'s own `claim_amount`/`claim_currency` already established.
-- * Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
--   explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
--   its final grants, the standing per-migration convention since PLT-118.

create function app.has_view_actual_cost(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'OPS', 'View cost')).allowed;
$$;

comment on function app.has_view_actual_cost is
  'OPS-178: thin wrapper over app.evaluate_permission(..., ''OPS'', ''View cost'') -- the same pre-registered permission action OPS-174''s own app.has_view_exception_cost already uses, reused here rather than registering a duplicate catalogue row.';

create table app.shipment_actual_costs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  version_number integer not null default 1,
  is_current boolean not null default true,
  supersedes_version_id uuid references app.shipment_actual_costs (id),
  status text not null default 'draft',
  currency text not null,
  estimated_amount numeric(14, 2),
  total_amount numeric(14, 2) not null default 0,
  approved_by_auth_user_id uuid,
  approved_at timestamptz,
  rejection_reason text,
  adjustment_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_actual_costs_status_check check (status in ('draft', 'submitted', 'approved', 'rejected')),
  constraint shipment_actual_costs_version_number_check check (version_number > 0),
  constraint shipment_actual_costs_total_amount_check check (total_amount >= 0),
  constraint shipment_actual_costs_estimated_amount_check check (estimated_amount is null or estimated_amount >= 0),
  constraint shipment_actual_costs_rejection_reason_check check (status <> 'rejected' or (rejection_reason is not null and length(trim(rejection_reason)) > 0)),
  constraint shipment_actual_costs_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.shipment_actual_costs is
  'OPS-178: one versioned actual-cost header per shipment (draft -> submitted -> approved|rejected). is_current is exclusive (partial unique index) -- an adjustment always starts a brand-new version via app.create_actual_cost_adjustment, never mutating an approved version in place. total_amount is server-recomputed on every component add/remove, never client-supplied.';

create unique index shipment_actual_costs_one_current_idx on app.shipment_actual_costs (shipment_order_id) where is_current;
create unique index shipment_actual_costs_one_draft_idx on app.shipment_actual_costs (shipment_order_id) where status = 'draft';
create index shipment_actual_costs_tenant_shipment_idx on app.shipment_actual_costs (tenant_id, shipment_order_id);

create function app.touch_shipment_actual_costs_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_actual_costs_touch_row
  before update on app.shipment_actual_costs
  for each row
  execute function app.touch_shipment_actual_costs_row();

create table app.shipment_actual_cost_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  actual_cost_id uuid not null references app.shipment_actual_costs (id),
  category text not null,
  source_type text not null,
  vendor_id uuid references app.master_records (id),
  assignment_id uuid references app.resource_assignments (id),
  document_file_id uuid references app.files (id),
  description text,
  quantity numeric(14, 4) not null default 1,
  uom text,
  rate numeric(14, 4) not null,
  minimum_charge numeric(14, 2),
  surcharge numeric(14, 2) not null default 0,
  amount numeric(14, 2) not null,
  currency text not null,
  idempotency_key text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint shipment_actual_cost_components_category_check check (category in ('freight', 'trucking', 'fuel_surcharge', 'handling', 'customs', 'warehousing', 'other')),
  constraint shipment_actual_cost_components_source_type_check check (source_type in ('vendor', 'internal')),
  constraint shipment_actual_cost_components_vendor_required_check check (source_type <> 'vendor' or vendor_id is not null),
  constraint shipment_actual_cost_components_quantity_check check (quantity > 0),
  constraint shipment_actual_cost_components_rate_check check (rate >= 0),
  constraint shipment_actual_cost_components_minimum_charge_check check (minimum_charge is null or minimum_charge >= 0),
  constraint shipment_actual_cost_components_surcharge_check check (surcharge >= 0),
  constraint shipment_actual_cost_components_amount_check check (amount >= 0),
  constraint shipment_actual_cost_components_idempotency_unique unique (tenant_id, actual_cost_id, idempotency_key)
);

comment on table app.shipment_actual_cost_components is
  'OPS-178: one exact, componentized cost line per row -- source lineage to a vendor master record (OPS-171) and/or a resource assignment (OPS-172) and/or an uploaded document (OPS-176/PLT-128), never re-entered free text where a live reference already exists. amount is always server-computed (app.compute_actual_cost_component_amount), never accepted from a caller.';

create index shipment_actual_cost_components_actual_cost_idx on app.shipment_actual_cost_components (actual_cost_id);
create index shipment_actual_cost_components_tenant_vendor_idx on app.shipment_actual_cost_components (tenant_id, vendor_id);

-- The one place quantity*rate/minimum/surcharge reconciles to an exact amount
-- (Prompt 178 §25) -- numeric arithmetic throughout, round-half-away-from-zero via
-- Postgres's own round(numeric, 2).
create function app.compute_actual_cost_component_amount(p_quantity numeric, p_rate numeric, p_minimum_charge numeric, p_surcharge numeric)
returns numeric
language sql
immutable
as $$
  select round(greatest(p_quantity * p_rate, coalesce(p_minimum_charge, 0)) + coalesce(p_surcharge, 0), 2);
$$;

create function app.recalculate_actual_cost_total(p_actual_cost_id uuid)
returns app.shipment_actual_costs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_total numeric(14, 2);
  v_updated app.shipment_actual_costs;
begin
  select coalesce(sum(amount), 0) into v_total from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id;
  update app.shipment_actual_costs set total_amount = v_total where id = p_actual_cost_id returning * into v_updated;
  return v_updated;
end;
$$;

create function app.create_actual_cost_draft(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_currency text,
  p_estimated_amount numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_actual_costs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_draft app.shipment_actual_costs;
  v_cost app.shipment_actual_costs;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft from app.shipment_actual_costs where shipment_order_id = p_shipment_order_id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  if exists (select 1 from app.shipment_actual_costs where shipment_order_id = p_shipment_order_id and is_current) then
    raise exception 'actual_cost_already_exists: shipment order % already has a current actual-cost version -- use app.create_actual_cost_adjustment to start a new one', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_actual_costs (tenant_id, shipment_order_id, currency, estimated_amount, created_by)
  values (v_shipment.tenant_id, p_shipment_order_id, p_currency, p_estimated_amount, p_actor_label)
  returning * into v_cost;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_actual_cost_draft',
    'app.shipment_actual_costs', v_cost.id, 'success', null, null, to_jsonb(v_cost)
  );

  return v_cost;
end;
$$;

create function app.add_actual_cost_component(
  p_actual_cost_id uuid,
  p_category text,
  p_source_type text,
  p_vendor_id uuid,
  p_assignment_id uuid,
  p_document_file_id uuid,
  p_description text,
  p_quantity numeric,
  p_uom text,
  p_rate numeric,
  p_minimum_charge numeric,
  p_surcharge numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_actual_cost_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_actual_cost_components;
  v_amount numeric(14, 2);
  v_component app.shipment_actual_cost_components;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and cannot accept new components', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if p_source_type = 'vendor' and p_vendor_id is null then
    raise exception 'actual_cost_vendor_required: a vendor_id is required when source_type is vendor' using errcode = 'check_violation';
  end if;
  if p_assignment_id is not null and not exists (select 1 from app.resource_assignments where id = p_assignment_id and shipment_order_id = v_cost.shipment_order_id) then
    raise exception 'actual_cost_assignment_mismatch: assignment % does not belong to shipment order %', p_assignment_id, v_cost.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if p_document_file_id is not null and not exists (select 1 from app.files where id = p_document_file_id and tenant_id = v_cost.tenant_id and record_type = 'shipment_order' and record_id = v_cost.shipment_order_id) then
    raise exception 'actual_cost_document_mismatch: document % does not belong to shipment order %', p_document_file_id, v_cost.shipment_order_id
      using errcode = 'check_violation';
  end if;

  v_amount := app.compute_actual_cost_component_amount(p_quantity, p_rate, p_minimum_charge, p_surcharge);

  insert into app.shipment_actual_cost_components (
    tenant_id, actual_cost_id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, idempotency_key, created_by
  ) values (
    v_cost.tenant_id, p_actual_cost_id, p_category, p_source_type, p_vendor_id, p_assignment_id, p_document_file_id,
    p_description, p_quantity, p_uom, p_rate, p_minimum_charge, coalesce(p_surcharge, 0), v_amount, v_cost.currency, p_idempotency_key, p_actor_label
  )
  returning * into v_component;

  perform app.recalculate_actual_cost_total(p_actual_cost_id);

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_actual_cost_component',
    'app.shipment_actual_cost_components', v_component.id, 'success', null, null, to_jsonb(v_component)
  );

  return v_component;
end;
$$;

create function app.remove_actual_cost_component(
  p_component_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.shipment_actual_cost_components;
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_component from app.shipment_actual_cost_components where id = p_component_id;
  if not found then
    raise exception 'actual_cost_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;
  select * into v_cost from app.shipment_actual_costs where id = v_component.actual_cost_id;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and its components can no longer be removed', v_cost.id, v_cost.status
      using errcode = 'check_violation';
  end if;

  delete from app.shipment_actual_cost_components where id = p_component_id;
  perform app.recalculate_actual_cost_total(v_cost.id);

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_actual_cost_component',
    'app.shipment_actual_cost_components', p_component_id, 'success', null, to_jsonb(v_component), null
  );
end;
$$;

create function app.submit_actual_cost(
  p_actual_cost_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_actual_costs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_component_count integer;
  v_updated app.shipment_actual_costs;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  if v_cost.record_version <> p_expected_version then
    raise exception 'concurrent_modification: actual cost % has moved from expected version % to %', p_actual_cost_id, p_expected_version, v_cost.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and cannot be submitted', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_component_count from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id;
  if v_component_count = 0 then
    raise exception 'actual_cost_no_components: at least one cost component is required before submission' using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs set status = 'submitted' where id = p_actual_cost_id returning * into v_updated;

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_actual_cost',
    'app.shipment_actual_costs', v_updated.id, 'success', null, to_jsonb(v_cost), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.decide_actual_cost(
  p_actual_cost_id uuid,
  p_decision text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_actual_costs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.shipment_actual_costs;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'actual_cost_invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;

  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  if v_cost.record_version <> p_expected_version then
    raise exception 'concurrent_modification: actual cost % has moved from expected version % to %', p_actual_cost_id, p_expected_version, v_cost.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'submitted' then
    raise exception 'invalid_transition: actual cost % is % and cannot be decided', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'actual_cost_rejection_reason_required: a reason is required to reject' using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs
  set status = p_decision,
      approved_by_auth_user_id = case when p_decision = 'approved' then p_actor_auth_user_id else null end,
      approved_at = case when p_decision = 'approved' then now() else null end,
      rejection_reason = case when p_decision = 'rejected' then p_reason else null end
  where id = p_actual_cost_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_actual_cost',
    'app.shipment_actual_costs', v_updated.id, 'success', null, to_jsonb(v_cost), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- approved -> a brand-new draft version (never mutates the approved row). Component
-- lines are copied verbatim (new ids, same amounts) as the adjustment's own starting
-- point -- the prior approved version and its own components remain, permanently.
create function app.create_actual_cost_adjustment(
  p_previous_actual_cost_id uuid,
  p_adjustment_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_actual_costs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prev app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new app.shipment_actual_costs;
begin
  if p_adjustment_reason is null or length(trim(p_adjustment_reason)) = 0 then
    raise exception 'actual_cost_adjustment_reason_required: a reason is required to adjust an approved actual cost' using errcode = 'check_violation';
  end if;

  select * into v_prev from app.shipment_actual_costs where id = p_previous_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_previous_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_prev.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prev.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_prev.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_prev.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prev.status <> 'approved' then
    raise exception 'invalid_transition: actual cost % is % and cannot be adjusted -- only an approved version may be adjusted', p_previous_actual_cost_id, v_prev.status
      using errcode = 'check_violation';
  end if;
  if not v_prev.is_current then
    raise exception 'actual_cost_not_current: actual cost % is not the current version', p_previous_actual_cost_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs set is_current = false where id = v_prev.id;

  insert into app.shipment_actual_costs (tenant_id, shipment_order_id, version_number, is_current, supersedes_version_id, status, currency, estimated_amount, adjustment_reason, created_by)
  values (v_prev.tenant_id, v_prev.shipment_order_id, v_prev.version_number + 1, true, v_prev.id, 'draft', v_prev.currency, v_prev.estimated_amount, p_adjustment_reason, p_actor_label)
  returning * into v_new;

  insert into app.shipment_actual_cost_components (
    tenant_id, actual_cost_id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, created_by
  )
  select
    tenant_id, v_new.id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, p_actor_label
  from app.shipment_actual_cost_components
  where actual_cost_id = v_prev.id;

  perform app.recalculate_actual_cost_total(v_new.id);
  select * into v_new from app.shipment_actual_costs where id = v_new.id;

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_actual_cost_adjustment',
    'app.shipment_actual_costs', v_new.id, 'success', p_adjustment_reason, to_jsonb(v_prev), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

-- Pure, side-effect-free variance evaluation -- the disclosed forward seam OPS-179
-- (Basic Job Profitability) will call. variance_available is false whenever no
-- estimated_amount was ever supplied (never a fabricated zero baseline).
create function app.evaluate_actual_cost_variance(
  p_actual_cost_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  total_amount numeric,
  estimated_amount numeric,
  variance_amount numeric,
  variance_available boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    v_cost.total_amount,
    v_cost.estimated_amount,
    case when v_cost.estimated_amount is not null then v_cost.total_amount - v_cost.estimated_amount else null end,
    v_cost.estimated_amount is not null;
end;
$$;

-- The only read path for cost components -- denies outright (no partial result) to an
-- actor lacking OPS:View cost, since every column here is itself cost-shaped.
create function app.list_actual_cost_components(
  p_actual_cost_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.shipment_actual_cost_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id order by created_at asc;
end;
$$;

alter table app.shipment_actual_costs enable row level security;
alter table app.shipment_actual_cost_components enable row level security;

create policy shipment_actual_costs_select_scoped on app.shipment_actual_costs
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_actual_costs.shipment_order_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

-- Field-masked projection -- total_amount/estimated_amount nulled out for a
-- record-scoped actor lacking OPS:View cost (status/version/currency remain visible).
create view app.shipment_actual_costs_directory
as
select
  sac.id, sac.tenant_id, sac.shipment_order_id, sac.version_number, sac.is_current, sac.supersedes_version_id, sac.status, sac.currency,
  case when app.has_view_actual_cost(sac.tenant_id) then sac.estimated_amount else null end as estimated_amount,
  case when app.has_view_actual_cost(sac.tenant_id) then sac.total_amount else null end as total_amount,
  not app.has_view_actual_cost(sac.tenant_id) as cost_masked,
  sac.approved_by_auth_user_id, sac.approved_at, sac.rejection_reason, sac.adjustment_reason, sac.record_version, sac.created_by, sac.created_at, sac.updated_at
from app.shipment_actual_costs sac
join app.shipment_orders so on so.id = sac.shipment_order_id
where app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null);

comment on view app.shipment_actual_costs_directory is
  'OPS-178: field-masked projection of app.shipment_actual_costs -- total_amount/estimated_amount nulled (cost_masked=true) without OPS:View cost.';

revoke execute on all functions in schema app from public;

grant select on app.shipment_actual_costs to authenticated, service_role;
grant insert, update, delete on app.shipment_actual_costs to service_role;
grant select on app.shipment_actual_costs_directory to authenticated, service_role;
grant select on app.shipment_actual_cost_components to service_role;
grant insert, update, delete on app.shipment_actual_cost_components to service_role;

grant execute on function app.has_view_actual_cost(uuid, uuid) to authenticated, service_role;
grant execute on function app.compute_actual_cost_component_amount(numeric, numeric, numeric, numeric) to authenticated, service_role;
grant execute on function app.recalculate_actual_cost_total(uuid) to service_role;
grant execute on function app.create_actual_cost_draft(uuid, uuid, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.add_actual_cost_component(uuid, text, text, uuid, uuid, uuid, text, numeric, text, numeric, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_actual_cost_component(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.submit_actual_cost(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_actual_cost(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.create_actual_cost_adjustment(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_actual_cost_variance(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_actual_cost_components(uuid, uuid) to authenticated, service_role;
