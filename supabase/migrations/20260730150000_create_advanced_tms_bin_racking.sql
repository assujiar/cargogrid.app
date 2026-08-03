-- Advanced TMS/WMS capability ATW-230 (CG-S10-ATW-011, Prompt 230, "Bin and Racking" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements the
-- flexible warehouse location hierarchy this prompt's own §4 objective names: "rack,
-- shelf, floor, staging, dock and bin positions without forcing one physical layout" --
-- the deeper "Location Topology" epic Prompt 229's own "Facility Topology" epic
-- deliberately left to this task (ATW-229's own design note 1).
--
-- Design boundary (disclosed):
--
-- 1. **Materialized path/depth, reusing `app.org_units`' own proven mechanism
--    (PLT-109) verbatim** -- Prompt 230 §17 itself names "materialized path/ltree or
--    repository-approved indexed hierarchy" as the governed choice; no `ltree`
--    extension exists anywhere in this repository, and `app.org_units` already
--    established the exact `path uuid[]` (root-first ancestor list, self excluded) +
--    `depth integer` + a `before insert or update of parent_id` trigger pair
--    (shape/cycle validation, then path/depth recomputation) as this repository's own
--    "repository-approved indexed hierarchy." This migration reuses that identical
--    trigger pair and the identical descendant-path-splice cascade `app.move_org_unit`
--    already proved, rather than inventing a second hierarchy mechanism.
-- 2. **`location_type` is a real closed CHECK enum, unlike `zone_type`/`service_type`
--    (ATW-229's own free-text design note 2).** Prompt 230's own §4 objective, §13
--    database impact, and §27 test-data requirement all independently name the
--    identical six-value set ("rack, shelf, floor, staging, dock and bin") -- a
--    repeated, closed, sourced taxonomy, not a single test-data mention -- so this
--    migration constrains it directly rather than leaving it open.
-- 3. **Depth is bounded by a governed constant function, not a bare literal or an
--    unbounded tree.** No architecture document names an exact maximum rack/shelf/bin
--    depth; `app.warehouse_location_max_depth()` (a disclosed reasoned default, the
--    same class `ATW-224`'s own `app.route_planning_default_speed_kmh()` already used
--    without minting a fresh ADR) returns `8` -- comfortably covers any real
--    zone/aisle/rack/shelf/tier/bin layout while structurally preventing the
--    unbounded-depth risk Prompt 230 §17/§25 both name ("depth-bounded").
-- 4. **A location's `zone_id` is optional and validated only against its own
--    warehouse**, not inherited/enforced across an entire subtree -- Prompt 230 §22's
--    own "use floor/staging/dock location without rack" alt flow implies some
--    locations legitimately have no zone context at all; a zone, when given, must
--    belong to the same warehouse and be active (Prompt 230 §23's own "incompatible
--    zone" exception), the same "belongs to the same parent" check ATW-229 itself
--    already applied to a zone's own warehouse_id.
-- 5. **A location may never move to a different warehouse (no cross-warehouse
--    parent), and moving is restricted to a `draft`-status node** -- Prompt 230 §22's
--    own alt flow names "relocate an *empty unused draft* node with impact preview"
--    verbatim; a `draft` node structurally cannot hold real stock/tasks yet (no such
--    table exists downstream of this checkpoint regardless -- see design note 6), so
--    restricting move to `draft` is the real, sourced safety gate rather than a
--    fabricated one.
-- 6. **Deactivation dependency-impact checking is real where a real dependency
--    exists, disclosed as deferred where none does yet** -- identical boundary to
--    `ATW-229`'s own design note 7. A location cannot deactivate while any
--    `draft`/`active` child location still exists under it (checked directly against
--    this same table -- a real, checkable dependency, mirroring `app.org_units`' own
--    "cannot deactivate while active children exist" rule). Stock/task-level
--    dependency checking (Prompt 230 §24/§33's own "cannot orphan active stock/task")
--    is **not** implemented here -- no inbound/inventory/task table exists yet at this
--    checkpoint (`ATW-231` WMS Inbound is the very next Warehouse Foundation task);
--    whichever future capability first adds one is obligated to wire a real check
--    before letting a stocked/tasked location deactivate or move.
-- 7. **A barcode resolves a candidate location; it never itself authorizes anything**
--    (Prompt 230 §24 verbatim) -- `app.resolve_warehouse_location_by_barcode` is a
--    plain, record-scope-gated read, structurally incapable of performing or
--    authorizing any putaway/pick/inventory action, since no such action exists in
--    this repository yet. Barcode uniqueness is enforced tenant-wide (a partial unique
--    index on non-null values) -- the governed scope a real physical barcode registry
--    should never collide within, and it carries no secret/classification weight of
--    its own (Prompt 230 §16's own "barcode IDs never authorize by themselves").
-- 8. **Restricted-zone/secure-area access beyond standard record-scope is disclosed as
--    deferred, not built.** `app.warehouse_zones.restrictions` (ATW-229) remains a
--    descriptive jsonb bag; no per-user zone-restriction-grant mechanism has ever been
--    requested or built in this repository. A location's own visibility/mutation
--    authority is exactly its warehouse's own company-org-unit record scope (design
--    note 4's own reuse of `app.lead_record_scope_org_unit_ids`) -- the identical,
--    already-governed mechanism every other Phase 5 capability uses; inventing a
--    second, zone-restriction-specific ACL layer now would be new-feature authoring
--    beyond what this task's own scope or any prior capability established.
-- 9. **List reads are bounded, one level at a time, never a full recursive tree
--    fetch** -- Prompt 230 §17's own explicit "no full warehouse tree in browser"
--    anti-pattern. `app.list_warehouse_locations` returns exactly one parent's own
--    direct children (or a warehouse's own root nodes), selective columns, ordered by
--    `sequence` then `code` -- the same "selective subtree loading" §17 names.
-- 10. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

create function app.warehouse_location_max_depth()
returns integer
language sql
immutable
as $$
  select 8::integer;
$$;

comment on function app.warehouse_location_max_depth is
  'ATW-230: the governed maximum warehouse-location hierarchy depth (design note 3) -- a disclosed reasoned default, enforced by app.enforce_warehouse_location_parent_shape(), not merely documented.';

-- 1. Flexible location hierarchy.
create table app.warehouse_locations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  zone_id uuid references app.warehouse_zones (id),
  parent_id uuid references app.warehouse_locations (id),
  code text not null,
  name text not null,
  location_type text not null,
  path uuid[] not null default '{}'::uuid[],
  depth integer not null default 0,
  sequence integer not null default 0,
  capacity_value numeric,
  capacity_uom text,
  environment jsonb not null default '{}'::jsonb,
  restrictions jsonb not null default '{}'::jsonb,
  barcode text,
  pick_enabled boolean not null default false,
  putaway_enabled boolean not null default false,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_locations_code_check check (length(trim(code)) > 0),
  constraint warehouse_locations_name_check check (length(trim(name)) > 0),
  constraint warehouse_locations_location_type_check check (location_type in ('rack', 'shelf', 'floor', 'staging', 'dock', 'bin')),
  constraint warehouse_locations_status_check check (status in ('draft', 'active', 'inactive')),
  constraint warehouse_locations_environment_check check (app.validate_master_attributes(environment)),
  constraint warehouse_locations_restrictions_check check (app.validate_master_attributes(restrictions)),
  constraint warehouse_locations_capacity_value_check check (capacity_value is null or capacity_value >= 0),
  constraint warehouse_locations_capacity_pair_check check ((capacity_value is null) = (capacity_uom is null)),
  constraint warehouse_locations_capacity_uom_check check (capacity_uom is null or length(trim(capacity_uom)) > 0),
  constraint warehouse_locations_not_self_parent check (parent_id is distinct from id),
  constraint warehouse_locations_depth_check check (depth >= 0 and depth <= app.warehouse_location_max_depth()),
  constraint warehouse_locations_code_unique unique (tenant_id, warehouse_id, code)
);

comment on table app.warehouse_locations is
  'ATW-230: flexible rack/shelf/floor/staging/dock/bin location hierarchy under a warehouse (and optionally a zone). path/depth are materialized ancestor state (root-first, self excluded), maintained exclusively by app.recompute_warehouse_location_path() -- never hand-written by an RPC. Rack is optional (Prompt 230 §24) -- a location may sit directly under a warehouse/zone with no parent at all (parent_id null, depth 0).';

create unique index warehouse_locations_barcode_unique on app.warehouse_locations (tenant_id, barcode) where barcode is not null;
create index warehouse_locations_tenant_warehouse_status_idx on app.warehouse_locations (tenant_id, warehouse_id, status);
create index warehouse_locations_parent_id_idx on app.warehouse_locations (parent_id);
create index warehouse_locations_warehouse_root_idx on app.warehouse_locations (warehouse_id) where parent_id is null;
create index warehouse_locations_path_gin_idx on app.warehouse_locations using gin (path);

create function app.touch_warehouse_locations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger warehouse_locations_touch_row
  before update on app.warehouse_locations
  for each row
  execute function app.touch_warehouse_locations_row();

-- Shape/cycle guard (design note 1, mirroring app.enforce_org_unit_parent_shape
-- verbatim): a parent must exist, belong to the same tenant AND the same warehouse
-- (Prompt 230 §23's own "cross-warehouse parent" block), and a move can never target
-- the node's own descendant (or itself).
create function app.enforce_warehouse_location_parent_shape()
returns trigger
language plpgsql
as $$
declare
  v_parent app.warehouse_locations;
begin
  if new.parent_id is null then
    return new;
  end if;

  select * into v_parent from app.warehouse_locations where id = new.parent_id;
  if not found then
    raise exception 'warehouse_location_parent_not_found: parent % does not exist', new.parent_id
      using errcode = 'no_data_found';
  end if;

  if v_parent.tenant_id <> new.tenant_id then
    raise exception 'cross_tenant_parent: parent % belongs to a different tenant', new.parent_id
      using errcode = 'check_violation';
  end if;

  if v_parent.warehouse_id <> new.warehouse_id then
    raise exception 'cross_warehouse_parent: parent % belongs to a different warehouse', new.parent_id
      using errcode = 'check_violation';
  end if;

  if tg_op = 'UPDATE' and (v_parent.path @> array[old.id] or v_parent.id = old.id) then
    raise exception 'warehouse_location_cycle: % cannot be moved under its own descendant %', old.id, new.parent_id
      using errcode = 'check_violation';
  end if;

  if v_parent.depth + 1 > app.warehouse_location_max_depth() then
    raise exception 'warehouse_location_depth_exceeded: moving/creating under % would exceed the governed maximum depth of %', new.parent_id, app.warehouse_location_max_depth()
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger warehouse_locations_enforce_parent_shape
  before insert or update of parent_id on app.warehouse_locations
  for each row
  execute function app.enforce_warehouse_location_parent_shape();

-- Recomputes this row's own path/depth from its (already shape/cycle-validated)
-- parent -- runs after the guard above, mirroring app.recompute_org_unit_path
-- verbatim.
create function app.recompute_warehouse_location_path()
returns trigger
language plpgsql
as $$
declare
  v_parent app.warehouse_locations;
begin
  if new.parent_id is null then
    new.path := '{}'::uuid[];
    new.depth := 0;
    return new;
  end if;

  select * into v_parent from app.warehouse_locations where id = new.parent_id;
  new.path := v_parent.path || v_parent.id;
  new.depth := v_parent.depth + 1;
  return new;
end;
$$;

create trigger warehouse_locations_recompute_path
  before insert or update of parent_id on app.warehouse_locations
  for each row
  execute function app.recompute_warehouse_location_path();

-- app.create_warehouse_location -- idempotent on (tenant_id, warehouse_id, code).
create function app.create_warehouse_location(
  p_warehouse_id uuid,
  p_zone_id uuid,
  p_parent_id uuid,
  p_code text,
  p_name text,
  p_location_type text,
  p_sequence integer,
  p_capacity_value numeric,
  p_capacity_uom text,
  p_environment jsonb,
  p_restrictions jsonb,
  p_barcode text,
  p_pick_enabled boolean,
  p_putaway_enabled boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_locations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_zone app.warehouse_zones;
  v_existing app.warehouse_locations;
  v_location app.warehouse_locations;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_location_type not in ('rack', 'shelf', 'floor', 'staging', 'dock', 'bin') then
    raise exception 'invalid_location_type: % is not a valid location type', p_location_type using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot add a location to it', p_warehouse_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a location under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if p_zone_id is not null then
    select * into v_zone from app.warehouse_zones where id = p_zone_id;
    if not found or v_zone.warehouse_id <> p_warehouse_id then
      raise exception 'incompatible_zone: zone % does not belong to warehouse %', p_zone_id, p_warehouse_id using errcode = 'check_violation';
    end if;
    if v_zone.status <> 'active' then
      raise exception 'incompatible_zone: zone % is not active', p_zone_id using errcode = 'check_violation';
    end if;
  end if;

  if p_capacity_value is not null and p_capacity_value < 0 then
    raise exception 'invalid_capacity: capacity_value must not be negative' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.warehouse_locations where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
  if found then
    if v_existing.location_type <> p_location_type or v_existing.parent_id is distinct from p_parent_id then
      raise exception 'location_code_conflict: code % already exists for warehouse % with a different type/parent', p_code, p_warehouse_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.warehouse_locations (
      tenant_id, warehouse_id, zone_id, parent_id, code, name, location_type, sequence,
      capacity_value, capacity_uom, environment, restrictions, barcode, pick_enabled, putaway_enabled, created_by
    ) values (
      v_warehouse.tenant_id, p_warehouse_id, p_zone_id, p_parent_id, p_code, p_name, p_location_type, coalesce(p_sequence, 0),
      p_capacity_value, p_capacity_uom, coalesce(p_environment, '{}'::jsonb), coalesce(p_restrictions, '{}'::jsonb),
      p_barcode, coalesce(p_pick_enabled, false), coalesce(p_putaway_enabled, false), p_actor_label
    )
    returning * into v_location;
  exception
    when unique_violation then
      if p_barcode is not null and exists (select 1 from app.warehouse_locations where tenant_id = v_warehouse.tenant_id and barcode = p_barcode) then
        raise exception 'duplicate_barcode: barcode % is already assigned within this tenant', p_barcode using errcode = 'unique_violation';
      end if;
      select * into v_location from app.warehouse_locations where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
      if found then
        return v_location;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse_location',
    'app.warehouse_locations', v_location.id, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'zone_id', p_zone_id, 'parent_id', p_parent_id, 'code', p_code, 'location_type', p_location_type)
  );

  return v_location;
end;
$$;

comment on function app.create_warehouse_location is
  'ATW-230: idempotent on (tenant_id, warehouse_id, code). A parent (if given) is shape/cycle/depth-validated by app.enforce_warehouse_location_parent_shape() at INSERT time; a zone (if given) must belong to the same warehouse and be active. capacity_value/capacity_uom must both be present or both be null. Starts life status=draft (Prompt 230 §21: "validates... and activates them" -- activation is a distinct, explicit step, app.set_warehouse_location_status).';

-- app.update_warehouse_location -- mutable fields only; code/location_type/
-- warehouse_id/zone_id/parent_id are immutable through this path (parent changes go
-- through app.move_warehouse_location only, design note 5).
create function app.update_warehouse_location(
  p_location_id uuid,
  p_name text,
  p_sequence integer,
  p_capacity_value numeric,
  p_capacity_uom text,
  p_environment jsonb,
  p_restrictions jsonb,
  p_barcode text,
  p_pick_enabled boolean,
  p_putaway_enabled boolean,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_locations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
begin
  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_location.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_location.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_capacity_value is not null and p_capacity_value < 0 then
    raise exception 'invalid_capacity: capacity_value must not be negative' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  begin
    update app.warehouse_locations set
      name = p_name,
      sequence = coalesce(p_sequence, 0),
      capacity_value = p_capacity_value,
      capacity_uom = p_capacity_uom,
      environment = coalesce(p_environment, '{}'::jsonb),
      restrictions = coalesce(p_restrictions, '{}'::jsonb),
      barcode = p_barcode,
      pick_enabled = coalesce(p_pick_enabled, false),
      putaway_enabled = coalesce(p_putaway_enabled, false)
    where id = p_location_id
    returning * into v_location;
  exception
    when unique_violation then
      raise exception 'duplicate_barcode: barcode % is already assigned within this tenant', p_barcode using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_location.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse_location',
    'app.warehouse_locations', v_location.id, 'success', null, null, jsonb_build_object('name', p_name, 'barcode', p_barcode)
  );

  return v_location;
end;
$$;

comment on function app.update_warehouse_location is
  'ATW-230: mutable fields only -- code/location_type/warehouse_id/zone_id/parent_id are immutable (design note 5; use app.move_warehouse_location for parent changes). Optimistic-concurrency gated.';

-- app.move_warehouse_location -- relocates a draft-status node (design note 5),
-- cascading path/depth to every descendant exactly like app.move_org_unit.
create function app.move_warehouse_location(
  p_location_id uuid,
  p_new_parent_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_locations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_current app.warehouse_locations;
  v_updated app.warehouse_locations;
  v_warehouse app.warehouses;
  v_old_path_prefix uuid[];
  v_new_path_prefix uuid[];
  v_depth_delta integer;
begin
  select * into v_current from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_current.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_current.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_current.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_current.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot move location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'draft' then
    raise exception 'location_not_draft: % is % -- only a draft (empty, unused) location may be moved', p_location_id, v_current.status
      using errcode = 'check_violation';
  end if;

  v_old_path_prefix := v_current.path || v_current.id;

  update app.warehouse_locations
  set parent_id = p_new_parent_id
  where id = p_location_id
  returning * into v_updated;

  v_new_path_prefix := v_updated.path || v_updated.id;
  v_depth_delta := v_updated.depth - v_current.depth;

  update app.warehouse_locations d
  set path = v_new_path_prefix || d.path[array_length(v_old_path_prefix, 1) + 1 : array_length(d.path, 1)],
      depth = d.depth + v_depth_delta
  where d.path @> array[p_location_id];

  perform app.capture_audit_event(
    v_current.tenant_id, p_actor_auth_user_id, p_actor_label, 'move_warehouse_location',
    'app.warehouse_locations', v_updated.id, 'success', null,
    jsonb_build_object('parent_id', v_current.parent_id), jsonb_build_object('parent_id', p_new_parent_id)
  );

  return v_updated;
end;
$$;

comment on function app.move_warehouse_location is
  'ATW-230: relocates a draft-status location under a new parent (which must belong to the same warehouse and not be this node''s own descendant -- app.enforce_warehouse_location_parent_shape enforces both), cascading path/depth to every descendant via the identical array-splice app.move_org_unit (PLT-109) already proved. Restricted to draft nodes only (design note 5) -- an active location holds no real stock/task table yet, but is never eligible for silent relocation regardless.';

-- app.set_warehouse_location_status -- draft/active/inactive lifecycle.
create function app.set_warehouse_location_status(
  p_location_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_locations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_active_child_count integer;
begin
  if p_new_status not in ('draft', 'active', 'inactive') then
    raise exception 'invalid_status: % is not a valid location status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_location.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_location.record_version
      using errcode = 'check_violation';
  end if;
  if v_location.status = p_new_status then
    return v_location;
  end if;

  if p_new_status = 'active' and v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot activate a location under it', v_location.warehouse_id using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a location' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_child_count from app.warehouse_locations where parent_id = p_location_id and status in ('draft', 'active');
    if v_active_child_count > 0 then
      raise exception 'location_has_active_children: % cannot be deactivated while % draft/active child location(s) exist', p_location_id, v_active_child_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouse_locations set status = p_new_status where id = p_location_id returning * into v_location;

  perform app.capture_audit_event(
    v_location.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_location_status',
    'app.warehouse_locations', v_location.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_location;
end;
$$;

comment on function app.set_warehouse_location_status is
  'ATW-230: draft/active/inactive transitions. Deactivation is blocked while any draft/active child location still exists (design note 6, a real checkable dependency) -- deeper stock/task dependency checking is deferred, disclosed, to whichever future WMS capability first adds a real bin/inventory table.';

-- app.get_warehouse_location_deactivation_impact -- read-only preview.
create type app.warehouse_location_deactivation_impact as (
  active_child_count integer,
  draft_child_count integer
);

create function app.get_warehouse_location_deactivation_impact(p_location_id uuid, p_actor_auth_user_id uuid)
returns app.warehouse_location_deactivation_impact
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_result app.warehouse_location_deactivation_impact;
begin
  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  select count(*) filter (where status = 'active'), count(*) filter (where status = 'draft')
    into v_result.active_child_count, v_result.draft_child_count
    from app.warehouse_locations where parent_id = p_location_id;

  return v_result;
end;
$$;

comment on function app.get_warehouse_location_deactivation_impact is
  'ATW-230: read-only preview mirroring exactly what app.set_warehouse_location_status itself blocks a deactivation on.';

-- app.list_warehouse_locations -- one level at a time, never a full tree (design note 9).
create function app.list_warehouse_locations(p_warehouse_id uuid, p_actor_auth_user_id uuid, p_parent_id uuid default null, p_status_filter text default null)
returns setof app.warehouse_locations
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
  select * from app.warehouse_locations l
  where l.warehouse_id = p_warehouse_id
    and l.parent_id is not distinct from p_parent_id
    and (p_status_filter is null or l.status = p_status_filter)
  order by l.sequence, l.code;
end;
$$;

comment on function app.list_warehouse_locations is
  'ATW-230: exactly one parent''s own direct children (p_parent_id null -- the warehouse''s own root nodes), ordered by sequence then code -- bounded subtree loading, never a full recursive tree (design note 9).';

-- app.resolve_warehouse_location_by_barcode -- informational only (design note 7).
create function app.resolve_warehouse_location_by_barcode(p_tenant_id uuid, p_barcode text, p_actor_auth_user_id uuid)
returns app.warehouse_locations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
begin
  if p_barcode is null or length(trim(p_barcode)) = 0 then
    raise exception 'invalid_barcode: barcode is required' using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_location from app.warehouse_locations where tenant_id = p_tenant_id and barcode = p_barcode;
  if not found then
    raise exception 'location_not_found: no location with barcode %', p_barcode using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view location %', p_actor_auth_user_id, v_location.id using errcode = 'insufficient_privilege';
  end if;

  return v_location;
end;
$$;

comment on function app.resolve_warehouse_location_by_barcode is
  'ATW-230: resolves a scanned barcode to a candidate location row only -- structurally incapable of authorizing or performing any putaway/pick/inventory action itself (Prompt 230 §24, design note 7), since no such downstream action exists in this repository yet.';

alter table app.warehouse_locations enable row level security;

create policy warehouse_locations_select_scoped on app.warehouse_locations
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = warehouse_locations.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.warehouse_locations to authenticated, service_role;
grant insert, update, delete on app.warehouse_locations to service_role;

grant execute on function app.warehouse_location_max_depth() to authenticated, service_role;
grant execute on function app.create_warehouse_location(uuid, uuid, uuid, text, text, text, integer, numeric, text, jsonb, jsonb, text, boolean, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.update_warehouse_location(uuid, text, integer, numeric, text, jsonb, jsonb, text, boolean, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.move_warehouse_location(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_warehouse_location_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_warehouse_location_deactivation_impact(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_warehouse_locations(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_warehouse_location_by_barcode(uuid, text, uuid) to authenticated, service_role;
