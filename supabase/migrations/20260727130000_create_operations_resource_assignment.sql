-- Operations capability OPS-172 (Resource/Vendor Assignment, CG-S8-OPS-006)
-- Basic vendor, fleet, vehicle and driver assignment to a Shipment Order (OPS-169),
-- with availability/conflict checks -- explicitly NOT vendor onboarding or fleet/driver
-- master lifecycle ownership (Prompt 172 §24: "does not own vendor onboarding,
-- fleet/driver master lifecycle").
--
-- Master-type binding decision, disclosed rather than left implicit:
-- OPS-171 (Land/Air/Sea Baseline) deliberately left vehicle_ref/vendor_ref as plain
-- text, disclosing that "binding these fields to real canonical vendor/fleet/vehicle/
-- driver references is OPS-172's own explicit scope" -- this migration is that scope.
-- Rather than inventing a new bespoke reference table (which would itself become an
-- unauthorized "new master lifecycle"), this migration registers four new master types
-- into the ALREADY-BUILT generic master-data registry (`app.master_types` /
-- `app.master_records`, PLT-120) -- `vendor` and `fleet` and `vehicle` (owner_module_code
-- `PRC`, Procurement) and `driver` (owner_module_code `HRS`, HRIS) -- seeded the same
-- way PLT-120's own `vendor_rate` type was seeded: a direct INSERT, not a call to the
-- Supreme-Admin-gated `app.register_master_type`. This satisfies Prompt 172 §20 task 2's
-- "candidate lookup against existing canonical references without new master lifecycle"
-- literally: `app.master_records` IS the existing canonical reference system; creating,
-- updating, deactivating or merging vendor/fleet/vehicle/driver records themselves
-- remains PLT-120's own `app.create_master_record`/`app.update_master_record`/
-- `app.deactivate_master_record`/`app.merge_master_records` (service_role-gated,
-- tenant_admin/Supreme-authorized) -- this migration adds not one single mutating
-- function over `app.master_records` itself, only a read-only, minimized-projection
-- candidate-lookup function.
--
-- Engine-reuse note: `app.master_records.attributes` is a broad, tenant-membership-
-- scoped-readable jsonb bag (PLT-120's own `master_records_select_scoped` policy,
-- unmodified here) -- it may come to hold driver PII once a real HRIS/Procurement
-- capability populates it. Prompt 172 §26 ("driver/vendor PII and cost fields require
-- explicit permission") is honored within THIS capability's own new surface: this
-- migration's `app.resource_assignments.resource_snapshot` column is deliberately
-- limited to non-PII identifying fields only (`code`, `name`) -- never the full
-- `attributes` blob -- and `app.find_assignment_candidates` below projects only
-- `id`/`code`/`name`, never `attributes`. Broadening or narrowing `app.master_records`'
-- own base-table RLS is PLT-120's own capability surface, not reopened or silently
-- patched here.
--
-- Assignment model (Prompt 172 §24/§25): `app.resource_assignments` is a hybrid
-- append-only/in-place table. `is_current` marks which one row (if any) currently
-- occupies a given (shipment_order_id, role) slot -- enforced by a real partial unique
-- index, never merely a convention -- regardless of whether that current row's own
-- `status` is `active` or `held` (a hold pauses the assignment in place, it does not
-- vacate the role). `app.reassign_resource` is the one path that creates a genuinely
-- new row (preserving the prior row's own outcome/effects per §25 -- superseded_by_id
-- links backward, the prior row is never deleted or overwritten); `app.hold_resource_
-- assignment`/`app.resume_resource_assignment`/`app.unassign_resource` are in-place
-- status flips on the one current row. Conflict detection (Prompt 172 §20 task 1's
-- "availability/conflict checks") is deliberately bounded and simple for this "basic"
-- capability: a resource_id may not hold a live (`is_current` and `status='active'`)
-- assignment on more than one non-terminal Shipment Order at once, across any role.
-- Multi-resource scheduling, calendars, capacity/utilization optimization and true
-- time-window overlap arithmetic all remain explicit Phase 3/5 (Advanced TMS) scope,
-- never anticipated here (Prompt 172 §24).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
-- its final grants, the standing per-migration convention since `PLT-118`.

insert into app.master_types (code, name, scope, owner_module_code, registered_by) values
  ('vendor', 'Vendor', 'tenant', 'PRC', 'operations-resource-assignment-foundation'),
  ('fleet', 'Fleet', 'tenant', 'PRC', 'operations-resource-assignment-foundation'),
  ('vehicle', 'Vehicle', 'tenant', 'PRC', 'operations-resource-assignment-foundation'),
  ('driver', 'Driver', 'tenant', 'HRS', 'operations-resource-assignment-foundation');

create table app.resource_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  role text not null,
  resource_id uuid not null references app.master_records (id),
  resource_snapshot jsonb not null,
  status text not null default 'active',
  is_current boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  reason text,
  superseded_by_id uuid references app.resource_assignments (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint resource_assignments_role_check check (role in ('vendor', 'fleet', 'vehicle', 'driver')),
  constraint resource_assignments_status_check check (status in ('active', 'held', 'unassigned'))
);

comment on table app.resource_assignments is
  'OPS-172: one row per resource-assignment event on a Shipment Order (OPS-169). is_current marks the one row (if any) currently occupying a (shipment_order_id, role) slot -- enforced by resource_assignments_current_role_unique, a real partial unique index. resource_snapshot is deliberately limited to {code, name} only, never the full app.master_records.attributes blob (PII minimization, Prompt 172 §26). reassign creates a new row and points the prior row''s superseded_by_id at it (append-oriented, prior outcome preserved per §25); hold/resume/unassign are in-place status flips on the one current row.';

create index resource_assignments_tenant_shipment_idx on app.resource_assignments (tenant_id, shipment_order_id);
create index resource_assignments_tenant_resource_idx on app.resource_assignments (tenant_id, resource_id);

-- The one slot-occupancy guarantee (Prompt 172 §24: "one active assignment per required
-- role/effective slot unless explicit compatible rule permits otherwise"). Partial on
-- is_current (not status) -- a held assignment still occupies its role's slot.
create unique index resource_assignments_current_role_unique
  on app.resource_assignments (tenant_id, shipment_order_id, role) where is_current;

create function app.touch_resource_assignments_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger resource_assignments_touch_row
  before update on app.resource_assignments
  for each row
  execute function app.touch_resource_assignments_row();

-- Read-only, minimized-projection candidate lookup (Prompt 172 §20 task 2). Never
-- projects app.master_records.attributes -- only the same {id, code, name} identifying
-- shape resource_snapshot itself is limited to.
create function app.find_assignment_candidates(
  p_tenant_id uuid,
  p_role text,
  p_actor_auth_user_id uuid
)
returns table (id uuid, code text, name text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select mr.id, mr.code, mr.name
    from app.master_records mr
    where mr.master_type_code = p_role
      and mr.tenant_id = p_tenant_id
      and mr.canonical_status = 'active'
    order by mr.name;
end;
$$;

comment on function app.find_assignment_candidates is
  'OPS-172: tenant-scoped, active-only candidate lookup for a given role, projecting only {id, code, name} -- never app.master_records.attributes. The one read path this capability adds over the master-data registry; no create/update/deactivate/merge path is duplicated here (PLT-120 already owns those).';

-- The one path that creates the first assignment for a (shipment_order_id, role) slot.
create function app.assign_resource(
  p_shipment_order_id uuid,
  p_role text,
  p_resource_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.resource_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_resource app.master_records;
  v_decision app.rbac_decision;
  v_assignment app.resource_assignments;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status in ('cancelled', 'delivered', 'epod', 'closed') then
    raise exception 'invalid_transition: shipment order % is % and can no longer receive resource assignments', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  select * into v_resource from app.master_records where id = p_resource_id;
  if not found or v_resource.master_type_code <> p_role or v_resource.tenant_id <> v_shipment.tenant_id or v_resource.canonical_status <> 'active' then
    raise exception 'invalid_resource: % is not an active % master record for tenant %', p_resource_id, p_role, v_shipment.tenant_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.resource_id = p_resource_id
      and ra.is_current
      and ra.status = 'active'
      and ra.shipment_order_id <> p_shipment_order_id
  ) then
    raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', p_resource_id
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.shipment_order_id = p_shipment_order_id
      and ra.role = p_role
      and ra.is_current
  ) then
    raise exception 'already_assigned: shipment order % already has a current % assignment -- use reassign_resource', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;

  insert into app.resource_assignments (
    tenant_id, shipment_order_id, role, resource_id, resource_snapshot, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_role, p_resource_id,
    jsonb_build_object('code', v_resource.code, 'name', v_resource.name), p_actor_label
  )
  returning * into v_assignment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_resource',
    'app.resource_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'resource_id', p_resource_id)
  );

  return v_assignment;
end;
$$;

comment on function app.assign_resource is
  'OPS-172: the one path that creates the first assignment for a (shipment_order_id, role) slot -- already_assigned if a current row exists (points the caller at reassign_resource instead), assignment_conflict if the resource already holds a live assignment on a different, non-terminal shipment order. OPS:Assign-gated -- the first real consumer of this pre-seeded permission action.';

-- Reassignment (Prompt 172 §25): "requires reason and preserves prior outcome/effects"
-- -- creates a new row, never overwrites the prior one. The prior row is released
-- (is_current = false) before the new row is inserted so the partial unique index is
-- never violated even momentarily within the same transaction.
create function app.reassign_resource(
  p_shipment_order_id uuid,
  p_role text,
  p_new_resource_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.resource_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_resource app.master_records;
  v_decision app.rbac_decision;
  v_prior app.resource_assignments;
  v_assignment app.resource_assignments;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reassigning a resource requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status in ('cancelled', 'delivered', 'epod', 'closed') then
    raise exception 'invalid_transition: shipment order % is % and can no longer receive resource assignments', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  select * into v_resource from app.master_records where id = p_new_resource_id;
  if not found or v_resource.master_type_code <> p_role or v_resource.tenant_id <> v_shipment.tenant_id or v_resource.canonical_status <> 'active' then
    raise exception 'invalid_resource: % is not an active % master record for tenant %', p_new_resource_id, p_role, v_shipment.tenant_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prior
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment -- use assign_resource', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.resource_id = p_new_resource_id
      and ra.is_current
      and ra.status = 'active'
      and ra.shipment_order_id <> p_shipment_order_id
  ) then
    raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', p_new_resource_id
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set is_current = false, effective_to = now()
  where id = v_prior.id;

  insert into app.resource_assignments (
    tenant_id, shipment_order_id, role, resource_id, resource_snapshot, reason, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_role, p_new_resource_id,
    jsonb_build_object('code', v_resource.code, 'name', v_resource.name), p_reason, p_actor_label
  )
  returning * into v_assignment;

  update app.resource_assignments
  set superseded_by_id = v_assignment.id
  where id = v_prior.id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_resource',
    'app.resource_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'prior_assignment_id', v_prior.id, 'reason', p_reason)
  );

  return v_assignment;
end;
$$;

comment on function app.reassign_resource is
  'OPS-172: creates a new row and links the prior current row''s superseded_by_id at it -- the prior row is never deleted or overwritten (Prompt 172 §25). Reason is mandatory. The prior row is released (is_current=false) before the new row is inserted, so resource_assignments_current_role_unique is never violated.';

-- In-place status flip: active -> held. Reason mandatory (a hold is a disclosed
-- interruption, Prompt 172 §24/§25's own evidentiary discipline).
create function app.hold_resource_assignment(
  p_shipment_order_id uuid,
  p_role text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.resource_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: holding a resource assignment requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'active' then
    raise exception 'invalid_transition: current % assignment on shipment order % is % -- only an active assignment may be held', p_role, p_shipment_order_id, v_current.status
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set status = 'held', reason = p_reason
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_resource_assignment',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'reason', p_reason)
  );

  return v_current;
end;
$$;

comment on function app.hold_resource_assignment is
  'OPS-172: in-place status flip active -> held on the one current row for a (shipment_order_id, role) slot -- the assignment still occupies its slot while held (is_current stays true). Reason mandatory.';

-- In-place status flip: held -> active.
create function app.resume_resource_assignment(
  p_shipment_order_id uuid,
  p_role text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.resource_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'held' then
    raise exception 'invalid_transition: current % assignment on shipment order % is % -- only a held assignment may be resumed', p_role, p_shipment_order_id, v_current.status
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set status = 'active'
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'resume_resource_assignment',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role)
  );

  return v_current;
end;
$$;

comment on function app.resume_resource_assignment is
  'OPS-172: in-place status flip held -> active on the one current row for a (shipment_order_id, role) slot.';

-- In-place status flip: (active|held) -> unassigned, and releases the role slot
-- (is_current = false) so a subsequent assign_resource may create a fresh row.
create function app.unassign_resource(
  p_shipment_order_id uuid,
  p_role text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.resource_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: unassigning a resource requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set status = 'unassigned', is_current = false, effective_to = now(), reason = p_reason
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'unassign_resource',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'reason', p_reason)
  );

  return v_current;
end;
$$;

comment on function app.unassign_resource is
  'OPS-172: in-place status flip to unassigned and releases the (shipment_order_id, role) slot (is_current=false) -- a subsequent assign_resource may then create a fresh current row for the same role. Reason mandatory.';

create function app.get_resource_assignment_history(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.resource_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.resource_assignments
    where shipment_order_id = p_shipment_order_id
    order by created_at asc;
end;
$$;

comment on function app.get_resource_assignment_history is
  'OPS-172: full append-oriented assignment history for a Shipment Order, oldest first, authority-gated the same way every other Operations history reader in this session is (OPS:View + can_access_record).';

alter table app.resource_assignments enable row level security;

create policy resource_assignments_select_scoped on app.resource_assignments
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = resource_assignments.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.resource_assignments to authenticated, service_role;
grant insert, update, delete on app.resource_assignments to service_role;

grant execute on function app.find_assignment_candidates(uuid, text, uuid) to authenticated, service_role;
grant execute on function app.assign_resource(uuid, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_resource(uuid, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.hold_resource_assignment(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.resume_resource_assignment(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.unassign_resource(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_resource_assignment_history(uuid, uuid) to authenticated, service_role;
