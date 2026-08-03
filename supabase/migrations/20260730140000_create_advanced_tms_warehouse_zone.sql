-- Advanced TMS/WMS capability ATW-229 (CG-S10-ATW-010, Prompt 229, "Warehouse and
-- Zone" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements
-- the tenant/company warehouse and zone masters this prompt's own §4 objective names:
-- "tenant/company warehouse and zone masters with versioned topology, operational
-- eligibility and customer/owner scope" -- the controlled facility foundation every
-- later WMS task (§10 downstream: ATW-230..248) starts from.
--
-- Design boundary (disclosed):
--
-- 1. **Zones are flat -- one level under a warehouse, never self-referencing.** This
--    prompt's own §3 workstream names its epic "Facility Topology" (facility + zone
--    identity); Prompt 230's own epic is "Location Topology" (the deeper rack/shelf/
--    bin hierarchy). This migration owns only the shallower layer; a zone's own
--    `warehouse_id` is immutable once created (no RPC below ever lets a zone move to a
--    different warehouse), the structural mechanism -- not merely a documented promise
--    -- behind this prompt's own §23 "block... cross-warehouse link" exception-flow
--    rule.
-- 2. **`service_type_eligibility`/`zone_type` are free text, not a fabricated CHECK
--    enum.** `service_type` already stays free text across every prior Commercial
--    capability (COM-147/148: `app.vendor_rate_versions.service_type`,
--    `app.customer_contract_price_components.service_type`) rather than a hard-coded
--    list -- this migration reuses that same discipline rather than inventing a
--    logistics-service taxonomy no architecture document names. `zone_type` is the
--    identical case: Prompt 229 §27's own test-data requirement names "ambient/cold/
--    secure zones" as the *sourced* examples to cover, not an exhaustive enum (no
--    architecture document enumerates a canonical WMS zone-type list) -- a hard CHECK
--    listing only those three (or a larger, uncited list like hazmat/quarantine/
--    staging) would fabricate a business rule beyond what was actually asked. Both
--    columns are validated for non-empty content only; the test fixture below still
--    exercises all three named zone types.
-- 3. **`environment`/`restrictions` reuse `app.validate_master_attributes` (PLT-120)
--    verbatim** -- the same generic, already-proven "object, <=8KB, string leaves
--    reject angle brackets" structural/injection-safety validator PLT-120's own
--    `master_records.attributes` uses, rather than a second bespoke jsonb validator for
--    what is, structurally, the identical shape (a free-form attribute bag with no
--    business-defined schema yet).
-- 4. **`timezone` reuses `app.validate_timezone_name` (PLT-119) verbatim**; `site_geog`
--    reuses `app.geojson_point_to_geography`/`app.validate_geography_point` (PLT-134)
--    verbatim -- the same governed GeoJSON-in/geography-out/range-rejecting pipeline
--    every other Phase 5 spatial column already uses (`shipment_leg_stops.location_geog`
--    and friends), not a second parser.
-- 5. **Company/branch record scope reuses `app.lead_record_scope_org_unit_ids`
--    (COM-143) verbatim** -- ATW-227's own precedent already established that this
--    function, despite its name, is a domain-generic "org unit + every ancestor"
--    wrapper around `app.org_unit_ancestor_ids` (PLT-109), reused directly for
--    `app.shipment_orders`' own scope rather than a second copy. This migration's own
--    `app.warehouses.company_org_unit_id` is scoped the identical way -- a warehouse is
--    visible/editable to a caller whose own `app.users.org_unit_id` is the warehouse's
--    company org unit or any of its descendants' shared branches, matching this
--    prompt's own §26 "managers/users see assigned facility/zone" access rule, enforced
--    in the database (this migration's own RLS `select` policies below and every
--    mutation/read RPC's own explicit `app.can_access_record` check), never UI-only.
-- 6. **Customer eligibility is an explicit grant/revoke ledger**, mirroring
--    `app.role_assignments`' own `status in (active, revoked)` /
--    `granted_by`/`granted_at`/`revoked_at`/`revoked_reason` shape (PLT-111) exactly --
--    this prompt's own §24 "customer/owner eligibility is explicit and cannot broaden
--    access by itself" business rule. No RPC in this migration or any other yet reads
--    this table to widen a customer-portal principal's own access (ATW-242, the
--    contract this prompt's own §26 names as the read-only consumer, does not exist
--    yet) -- this migration ships the ledger only, disclosed as `NOT_RUN` for the
--    customer-facing read path, the same "mechanism proven, live wiring deferred"
--    posture PLT-121/PLT-106 already used for a future consumer that has not shipped.
-- 7. **Deactivation dependency-impact checking is real where a real dependency exists,
--    disclosed as deferred where none does yet.** A warehouse cannot be deactivated
--    while it still has an `active`/`on_hold` zone (checked directly against this same
--    migration's own `app.warehouse_zones` -- a real, checkable dependency, not a
--    placeholder). A zone's own deactivation does **not** check for stock/task
--    dependencies (this prompt's own §16/§33 "cannot orphan active inventory/tasks"
--    concern) because no bin/inventory/task table exists yet at this checkpoint --
--    Prompt 230 ("Bin and Racking") is the very next task in this session's own
--    explicit range and has not shipped. This is the identical disclosed boundary
--    PLT-120's own header already used ("no dependency-check mechanism exists... since
--    no downstream business-domain table references it yet"), not a silently-skipped
--    promise; `app.get_warehouse_deactivation_impact` and every zone-status RPC's own
--    comment name this explicitly, and Prompt 230 (or whichever future capability first
--    adds a real bin/inventory table) is the one obligated to wire a real check before
--    it lets a zone holding inventory deactivate.
-- 8. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL
--    FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Warehouse master.
create table app.warehouses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_org_unit_id uuid not null references app.org_units (id),
  code text not null,
  name text not null,
  site_address text,
  timezone text not null default 'Asia/Jakarta',
  site_geog geography(Point, 4326),
  service_type_eligibility text[] not null default '{}'::text[],
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouses_code_check check (length(trim(code)) > 0),
  constraint warehouses_name_check check (length(trim(name)) > 0),
  constraint warehouses_status_check check (status in ('active', 'inactive')),
  constraint warehouses_timezone_check check (app.validate_timezone_name(timezone)),
  constraint warehouses_site_geog_check check (site_geog is null or app.validate_geography_point(site_geog)),
  constraint warehouses_code_unique unique (tenant_id, code)
);

comment on table app.warehouses is
  'ATW-229: the tenant/company warehouse (facility) master -- a canonical record, never copied into a Job Order/Shipment Order (Prompt 229 §24). company_org_unit_id ties a warehouse to a company/branch app.org_units (PLT-109) node; record scope for every mutation/read RPC below is app.lead_record_scope_org_unit_ids(company_org_unit_id) (the node plus every ancestor), reused verbatim from COM-143/ATW-227''s own precedent. service_type_eligibility/timezone/site_geog validate against the already-established free-text/PLT-119/PLT-134 conventions (design notes 2/4 above) -- no new validator invented for shapes those already cover.';

create index warehouses_tenant_status_idx on app.warehouses (tenant_id, status);
create index warehouses_tenant_company_idx on app.warehouses (tenant_id, company_org_unit_id);

create function app.touch_warehouses_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger warehouses_touch_row
  before update on app.warehouses
  for each row
  execute function app.touch_warehouses_row();

-- 2. Warehouse zone master (flat, one level under a warehouse -- design note 1).
create table app.warehouse_zones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  code text not null,
  name text not null,
  zone_type text not null,
  environment jsonb not null default '{}'::jsonb,
  capacity_value numeric,
  capacity_uom text,
  restrictions jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  effective_from timestamptz,
  effective_to timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_zones_code_check check (length(trim(code)) > 0),
  constraint warehouse_zones_name_check check (length(trim(name)) > 0),
  constraint warehouse_zones_zone_type_check check (length(trim(zone_type)) > 0),
  constraint warehouse_zones_status_check check (status in ('active', 'inactive', 'on_hold')),
  constraint warehouse_zones_environment_check check (app.validate_master_attributes(environment)),
  constraint warehouse_zones_restrictions_check check (app.validate_master_attributes(restrictions)),
  constraint warehouse_zones_capacity_value_check check (capacity_value is null or capacity_value >= 0),
  constraint warehouse_zones_capacity_pair_check check ((capacity_value is null) = (capacity_uom is null)),
  constraint warehouse_zones_capacity_uom_check check (capacity_uom is null or length(trim(capacity_uom)) > 0),
  constraint warehouse_zones_effective_window_check check (effective_from is null or effective_to is null or effective_to > effective_from),
  constraint warehouse_zones_code_unique unique (tenant_id, warehouse_id, code)
);

comment on table app.warehouse_zones is
  'ATW-229: one flat zone per (warehouse, code) -- no self-referencing hierarchy (design note 1; Prompt 230''s own "Location Topology" epic owns the deeper rack/shelf/bin layer). status=''on_hold'' is Prompt 229 §22''s own alt-flow "temporarily hold/restrict a zone", distinct from a permanent ''inactive'' deactivation. effective_from/effective_to support the same §22 "schedule future zone" alt flow -- a zone may exist with a future effective_from before it is actually usable. environment/restrictions are free-form bags validated by app.validate_master_attributes (design note 3); zone_type is free text (design note 2).';

create index warehouse_zones_tenant_warehouse_status_idx on app.warehouse_zones (tenant_id, warehouse_id, status);
create index warehouse_zones_zone_type_idx on app.warehouse_zones (warehouse_id, zone_type);

create function app.touch_warehouse_zones_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger warehouse_zones_touch_row
  before update on app.warehouse_zones
  for each row
  execute function app.touch_warehouse_zones_row();

-- 3. Explicit customer/owner eligibility ledger (design note 6) -- mirrors
-- app.role_assignments' own active/revoked + granted/revoked shape (PLT-111) verbatim.
create table app.warehouse_customer_eligibility (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  customer_account_id uuid not null references app.accounts (id),
  status text not null default 'active',
  granted_by text,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_customer_eligibility_status_check check (status in ('active', 'revoked')),
  constraint warehouse_customer_eligibility_revoked_reason_check check (status <> 'revoked' or revoked_reason is not null),
  constraint warehouse_customer_eligibility_unique unique (tenant_id, warehouse_id, customer_account_id)
);

comment on table app.warehouse_customer_eligibility is
  'ATW-229: explicit per-warehouse customer eligibility (Prompt 229 §24 "customer/owner eligibility is explicit and cannot broaden access by itself") -- a ledger only; no consumer yet widens a customer-portal principal''s own access from this table (design note 6, ATW-242 not yet shipped).';

create index warehouse_customer_eligibility_tenant_warehouse_idx on app.warehouse_customer_eligibility (tenant_id, warehouse_id, status);
create index warehouse_customer_eligibility_customer_account_idx on app.warehouse_customer_eligibility (customer_account_id);

create function app.touch_warehouse_customer_eligibility_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger warehouse_customer_eligibility_touch_row
  before update on app.warehouse_customer_eligibility
  for each row
  execute function app.touch_warehouse_customer_eligibility_row();

-- 4. Warehouse mutations. Every mutation is idempotent on its own natural key (code
-- within tenant, or warehouse+customer for eligibility), RBAC-gated (OPS:Create/Edit)
-- and record-scope-gated (app.can_access_record against the warehouse's own company
-- org unit scope, design note 5), and audited.

create function app.create_warehouse(
  p_tenant_id uuid,
  p_company_org_unit_id uuid,
  p_code text,
  p_name text,
  p_site_address text,
  p_timezone text,
  p_site_geojson jsonb,
  p_service_type_eligibility text[],
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouses
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_org_unit app.org_units;
  v_existing app.warehouses;
  v_warehouse app.warehouses;
  v_geog geography;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_org_unit from app.org_units where id = p_company_org_unit_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'org_unit_not_found: % is not an org unit of tenant %', p_company_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(p_company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a warehouse under org unit %', p_actor_auth_user_id, p_company_org_unit_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_timezone is null or not app.validate_timezone_name(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_site_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_site_geojson);
  end if;

  select * into v_existing from app.warehouses where tenant_id = p_tenant_id and code = p_code;
  if found then
    if v_existing.company_org_unit_id <> p_company_org_unit_id then
      raise exception 'warehouse_code_conflict: code % already exists for tenant % under a different company org unit', p_code, p_tenant_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.warehouses (
      tenant_id, company_org_unit_id, code, name, site_address, timezone, site_geog, service_type_eligibility, created_by
    ) values (
      p_tenant_id, p_company_org_unit_id, p_code, p_name, p_site_address, p_timezone, v_geog, coalesce(p_service_type_eligibility, '{}'::text[]), p_actor_label
    )
    returning * into v_warehouse;
  exception
    when unique_violation then
      select * into v_warehouse from app.warehouses where tenant_id = p_tenant_id and code = p_code;
      if found then
        return v_warehouse;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse',
    'app.warehouses', v_warehouse.id, 'success', null, null,
    jsonb_build_object('code', p_code, 'name', p_name, 'company_org_unit_id', p_company_org_unit_id)
  );

  return v_warehouse;
end;
$$;

comment on function app.create_warehouse is
  'ATW-229: idempotent on (tenant_id, code) -- a same-code retry under the same company org unit returns the identical row; a different company org unit raises warehouse_code_conflict rather than silently re-parenting it. site_geojson is parsed/range-validated by app.geojson_point_to_geography (PLT-134); timezone by app.validate_timezone_name (PLT-119).';

create function app.update_warehouse(
  p_warehouse_id uuid,
  p_name text,
  p_site_address text,
  p_timezone text,
  p_site_geojson jsonb,
  p_service_type_eligibility text[],
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouses
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_geog geography;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_timezone is null or not app.validate_timezone_name(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_site_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_site_geojson);
  end if;

  update app.warehouses set
    name = p_name,
    site_address = p_site_address,
    timezone = p_timezone,
    site_geog = v_geog,
    service_type_eligibility = coalesce(p_service_type_eligibility, '{}'::text[])
  where id = p_warehouse_id
  returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse',
    'app.warehouses', v_warehouse.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'timezone', p_timezone)
  );

  return v_warehouse;
end;
$$;

comment on function app.update_warehouse is
  'ATW-229: mutable fields only -- code, tenant_id and company_org_unit_id are immutable once created (no re-parenting path exists). Optimistic-concurrency gated (record_version).';

create function app.set_warehouse_status(
  p_warehouse_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouses
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_active_zone_count integer;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid warehouse status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if v_warehouse.status = p_new_status then
    return v_warehouse;
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a warehouse' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_zone_count from app.warehouse_zones where warehouse_id = p_warehouse_id and status in ('active', 'on_hold');
    if v_active_zone_count > 0 then
      raise exception 'warehouse_has_active_zones: % cannot be deactivated while % active/on-hold zone(s) exist', p_warehouse_id, v_active_zone_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouses set status = p_new_status where id = p_warehouse_id returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_status',
    'app.warehouses', v_warehouse.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_warehouse;
end;
$$;

comment on function app.set_warehouse_status is
  'ATW-229: active <-> inactive only. Deactivation is blocked while any active/on_hold app.warehouse_zones row still exists under this warehouse (a real, checkable dependency -- design note 7) -- release/deactivate every zone first. Does not check bin/inventory/task dependencies below the zone layer; none exist yet at this checkpoint (design note 7).';

create type app.warehouse_deactivation_impact as (
  active_zone_count integer,
  on_hold_zone_count integer,
  active_customer_eligibility_count integer
);

create function app.get_warehouse_deactivation_impact(p_warehouse_id uuid, p_actor_auth_user_id uuid)
returns app.warehouse_deactivation_impact
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_result app.warehouse_deactivation_impact;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select count(*) filter (where status = 'active'), count(*) filter (where status = 'on_hold')
    into v_result.active_zone_count, v_result.on_hold_zone_count
    from app.warehouse_zones where warehouse_id = p_warehouse_id;
  select count(*) into v_result.active_customer_eligibility_count
    from app.warehouse_customer_eligibility where warehouse_id = p_warehouse_id and status = 'active';

  return v_result;
end;
$$;

comment on function app.get_warehouse_deactivation_impact is
  'ATW-229: read-only dependency-impact preview (Prompt 229 §14/§15 "dependency-impact operations"/"dependency view") for an admin considering deactivation -- active_zone_count/on_hold_zone_count mirror exactly what app.set_warehouse_status itself will block on; active_customer_eligibility_count is informational only (eligibility grants are not themselves a deactivation blocker).';

-- 5. Customer eligibility grant/revoke (design note 6).

create function app.grant_warehouse_customer_eligibility(
  p_warehouse_id uuid,
  p_customer_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_customer_eligibility
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_account app.accounts;
  v_existing app.warehouse_customer_eligibility;
  v_row app.warehouse_customer_eligibility;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.accounts where id = p_customer_account_id and tenant_id = v_warehouse.tenant_id;
  if not found then
    raise exception 'account_not_found: % is not an account of tenant %', p_customer_account_id, v_warehouse.tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.warehouse_customer_eligibility
    where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and customer_account_id = p_customer_account_id;
  if found then
    if v_existing.status = 'active' then
      return v_existing;
    end if;
    update app.warehouse_customer_eligibility
      set status = 'active', granted_by = p_actor_label, granted_at = now(), revoked_at = null, revoked_reason = null
      where id = v_existing.id
      returning * into v_row;
  else
    begin
      insert into app.warehouse_customer_eligibility (tenant_id, warehouse_id, customer_account_id, granted_by)
      values (v_warehouse.tenant_id, p_warehouse_id, p_customer_account_id, p_actor_label)
      returning * into v_row;
    exception
      when unique_violation then
        select * into v_row from app.warehouse_customer_eligibility
          where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and customer_account_id = p_customer_account_id;
        if not found then
          raise;
        end if;
    end;
  end if;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'grant_warehouse_customer_eligibility',
    'app.warehouse_customer_eligibility', v_row.id, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'customer_account_id', p_customer_account_id)
  );

  return v_row;
end;
$$;

comment on function app.grant_warehouse_customer_eligibility is
  'ATW-229: idempotent on (tenant_id, warehouse_id, customer_account_id) -- granting an already-active eligibility returns it unchanged; granting a previously-revoked one reactivates the same row (never a second row) rather than accumulating history rows.';

create function app.revoke_warehouse_customer_eligibility(
  p_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_customer_eligibility
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.warehouse_customer_eligibility;
  v_warehouse app.warehouses;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke warehouse customer eligibility' using errcode = 'check_violation';
  end if;

  select * into v_row from app.warehouse_customer_eligibility where id = p_id;
  if not found then
    raise exception 'eligibility_not_found: %', p_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_row.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_row.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, v_row.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: eligibility % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'check_violation';
  end if;
  if v_row.status = 'revoked' then
    raise exception 'invalid_transition: eligibility % is already revoked', p_id using errcode = 'check_violation';
  end if;

  update app.warehouse_customer_eligibility set status = 'revoked', revoked_at = now(), revoked_reason = p_reason where id = p_id returning * into v_row;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_warehouse_customer_eligibility',
    'app.warehouse_customer_eligibility', v_row.id, 'success', p_reason, null,
    jsonb_build_object('warehouse_id', v_row.warehouse_id, 'customer_account_id', v_row.customer_account_id)
  );

  return v_row;
end;
$$;

comment on function app.revoke_warehouse_customer_eligibility is
  'ATW-229: active -> revoked only, optimistic-concurrency gated, mandatory reason.';

-- 6. Zone mutations. code/zone_type/warehouse_id are immutable once created (design
-- note 1) -- update never accepts them, structurally preventing "cross-warehouse
-- link"/"duplicate code" (Prompt 229 §23).

create function app.create_warehouse_zone(
  p_warehouse_id uuid,
  p_code text,
  p_name text,
  p_zone_type text,
  p_environment jsonb,
  p_capacity_value numeric,
  p_capacity_uom text,
  p_restrictions jsonb,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_zones
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.warehouse_zones;
  v_zone app.warehouse_zones;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_zone_type is null or length(trim(p_zone_type)) = 0 then
    raise exception 'invalid_zone_type: zone_type is required' using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot add a zone to it', p_warehouse_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a zone under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if p_effective_from is not null and p_effective_to is not null and p_effective_to <= p_effective_from then
    raise exception 'invalid_effective_window: effective_to must be after effective_from' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.warehouse_zones where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
  if found then
    if v_existing.zone_type <> p_zone_type then
      raise exception 'zone_code_conflict: code % already exists for warehouse % with a different zone type', p_code, p_warehouse_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.warehouse_zones (
      tenant_id, warehouse_id, code, name, zone_type, environment, capacity_value, capacity_uom, restrictions, effective_from, effective_to, created_by
    ) values (
      v_warehouse.tenant_id, p_warehouse_id, p_code, p_name, p_zone_type, coalesce(p_environment, '{}'::jsonb), p_capacity_value, p_capacity_uom, coalesce(p_restrictions, '{}'::jsonb), p_effective_from, p_effective_to, p_actor_label
    )
    returning * into v_zone;
  exception
    when unique_violation then
      select * into v_zone from app.warehouse_zones where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
      if found then
        return v_zone;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse_zone',
    'app.warehouse_zones', v_zone.id, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'code', p_code, 'zone_type', p_zone_type)
  );

  return v_zone;
end;
$$;

comment on function app.create_warehouse_zone is
  'ATW-229: idempotent on (tenant_id, warehouse_id, code). Requires the parent warehouse to be active. capacity_value/capacity_uom must both be present or both be null (Prompt 229 §24 "use exact UOM").';

create function app.update_warehouse_zone(
  p_zone_id uuid,
  p_name text,
  p_environment jsonb,
  p_capacity_value numeric,
  p_capacity_uom text,
  p_restrictions jsonb,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_zones
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
begin
  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_effective_from is not null and p_effective_to is not null and p_effective_to <= p_effective_from then
    raise exception 'invalid_effective_window: effective_to must be after effective_from' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  update app.warehouse_zones set
    name = p_name,
    environment = coalesce(p_environment, '{}'::jsonb),
    capacity_value = p_capacity_value,
    capacity_uom = p_capacity_uom,
    restrictions = coalesce(p_restrictions, '{}'::jsonb),
    effective_from = p_effective_from,
    effective_to = p_effective_to
  where id = p_zone_id
  returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse_zone',
    'app.warehouse_zones', v_zone.id, 'success', null, null, jsonb_build_object('name', p_name)
  );

  return v_zone;
end;
$$;

comment on function app.update_warehouse_zone is
  'ATW-229: mutable fields only -- code/zone_type/warehouse_id are immutable (design note 1). Optimistic-concurrency gated.';

create function app.set_warehouse_zone_status(
  p_zone_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_zones
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
begin
  if p_new_status not in ('active', 'inactive', 'on_hold') then
    raise exception 'invalid_status: % is not a valid zone status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if v_zone.status = p_new_status then
    return v_zone;
  end if;
  if p_new_status in ('inactive', 'on_hold') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to set a zone to %', p_new_status using errcode = 'check_violation';
  end if;

  update app.warehouse_zones set status = p_new_status where id = p_zone_id returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_zone_status',
    'app.warehouse_zones', v_zone.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_zone;
end;
$$;

comment on function app.set_warehouse_zone_status is
  'ATW-229: active/inactive/on_hold transitions (on_hold = Prompt 229 §22''s own "temporarily hold/restrict a zone" alt flow). Does not check bin/inventory/task dependencies -- none exist yet at this checkpoint (design note 7); a future capability that adds a real bin/inventory table under a zone is obligated to add that check before this function may let such a zone deactivate.';

-- 7. Read/list projections.

create function app.list_tenant_warehouses(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null)
returns table (
  id uuid,
  company_org_unit_id uuid,
  code text,
  name text,
  site_address text,
  timezone text,
  site_geog_geojson jsonb,
  service_type_eligibility text[],
  status text,
  zone_count integer,
  active_zone_count integer,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    w.id, w.company_org_unit_id, w.code, w.name, w.site_address, w.timezone,
    app.geography_to_geojson_point(w.site_geog), w.service_type_eligibility, w.status,
    (select count(*)::integer from app.warehouse_zones z where z.warehouse_id = w.id),
    (select count(*)::integer from app.warehouse_zones z where z.warehouse_id = w.id and z.status = 'active'),
    w.record_version, w.created_at, w.updated_at
  from app.warehouses w
  where w.tenant_id = p_tenant_id
    and (p_status_filter is null or w.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by w.code;
end;
$$;

comment on function app.list_tenant_warehouses is
  'ATW-229: one row per warehouse the caller can access (design note 5), including zone_count/active_zone_count so the admin topology list (Prompt 229 §15) can render without a second per-warehouse round trip. Selective columns only, ordered by code -- never SELECT *.';

create function app.list_warehouse_zones(p_warehouse_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null)
returns setof app.warehouse_zones
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.warehouse_zones z
  where z.warehouse_id = p_warehouse_id and (p_status_filter is null or z.status = p_status_filter)
  order by z.code;
end;
$$;

comment on function app.list_warehouse_zones is
  'ATW-229: every zone under one warehouse the caller can access, ordered by code.';

create function app.list_warehouse_customer_eligibility(p_warehouse_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  warehouse_id uuid,
  customer_account_id uuid,
  customer_legal_name text,
  status text,
  granted_by text,
  granted_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
begin
  -- Table-qualified (not a bare "where id = ...") -- this function's own RETURNS
  -- TABLE column named "id" would otherwise make a bare "id" reference ambiguous
  -- with app.warehouses.id inside this plpgsql body.
  select w.* into v_warehouse from app.warehouses w where w.id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  return query
  select e.id, e.warehouse_id, e.customer_account_id, a.legal_name, e.status, e.granted_by, e.granted_at, e.revoked_at, e.revoked_reason, e.record_version
  from app.warehouse_customer_eligibility e
  join app.accounts a on a.id = e.customer_account_id
  where e.warehouse_id = p_warehouse_id
  order by a.legal_name;
end;
$$;

comment on function app.list_warehouse_customer_eligibility is
  'ATW-229: every customer eligibility grant/revocation for one warehouse the caller can access, joined to the account''s own legal_name for display.';

-- 8. RLS -- record scope enforced in the database (design note 5), not UI-only.

alter table app.warehouses enable row level security;

create policy warehouses_select_scoped on app.warehouses
  for select to authenticated
  using (app.can_access_record(auth.uid(), tenant_id, null, app.lead_record_scope_org_unit_ids(company_org_unit_id), null));

alter table app.warehouse_zones enable row level security;

create policy warehouse_zones_select_scoped on app.warehouse_zones
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = warehouse_zones.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.warehouse_customer_eligibility enable row level security;

create policy warehouse_customer_eligibility_select_scoped on app.warehouse_customer_eligibility
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = warehouse_customer_eligibility.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.warehouses, app.warehouse_zones, app.warehouse_customer_eligibility to authenticated, service_role;
grant insert, update, delete on app.warehouses, app.warehouse_zones, app.warehouse_customer_eligibility to service_role;

grant execute on function app.create_warehouse(uuid, uuid, text, text, text, text, jsonb, text[], uuid, text) to authenticated, service_role;
grant execute on function app.update_warehouse(uuid, text, text, text, jsonb, text[], integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_warehouse_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_warehouse_deactivation_impact(uuid, uuid) to authenticated, service_role;
grant execute on function app.grant_warehouse_customer_eligibility(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_warehouse_customer_eligibility(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.create_warehouse_zone(uuid, text, text, text, jsonb, numeric, text, jsonb, timestamptz, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.update_warehouse_zone(uuid, text, jsonb, numeric, text, jsonb, timestamptz, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_warehouse_zone_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_tenant_warehouses(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_warehouse_zones(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_warehouse_customer_eligibility(uuid, uuid) to authenticated, service_role;
