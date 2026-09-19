-- CG-AUDIT-2026-09-02 E2 (independent launch-readiness audit, finding E2): "One vehicle,
-- one shipment" -- app.assign_resource rejects a second active assignment for the same
-- resource, but the check was an unlocked `EXISTS` read-then-write with no row lock and no
-- exclusion constraint behind it: two concurrent assignment requests for the SAME resource
-- (a vehicle, driver, fleet, or vendor master record) on DIFFERENT shipment orders could
-- both pass the EXISTS check before either commits, so the rule held in the common case
-- and was racily bypassable under load. app.reassign_resource carried the byte-identical
-- unlocked check for its own new resource, and app.resume_resource_assignment (returning a
-- held assignment to active) carried no check of this kind AT ALL -- a held assignment on
-- shipment A could be resumed to active even after the SAME resource was validly assigned
-- to shipment B in the meantime, since holding never released is_current.
--
-- Fix: a real, DB-level partial unique index -- resource_assignments_active_resource_unique
-- on (tenant_id, resource_id) where is_current and status = 'active' -- makes "at most one
-- current, active assignment per resource" a genuine invariant the database itself
-- enforces, not merely an application-level read-then-write race. Each of the three
-- functions above now catches a real concurrent violation of it (mirroring
-- app.start_vendor_assessment's own established GET STACKED DIAGNOSTICS pattern for
-- distinguishing which unique index actually fired) and re-raises the same named
-- assignment_conflict error the existing sequential pre-checks already give, rather than a
-- raw unique_violation; app.assign_resource's own insert can additionally still race on
-- resource_assignments_current_role_unique (two concurrent first-time assignments for the
-- same shipment_order_id/role, different resource_id), now also disambiguated to the
-- existing already_assigned error instead of a raw unique_violation. app.
-- resume_resource_assignment gains both a sequential pre-check (a clean, immediate error
-- for the ordinary case) and the same race-safe handling on its own update.
--
-- The audit's own E2 paragraph also names app.milestone_codes shipping with 0 rows and no
-- seed (a dead-end dropdown on a fresh install). NOT fixed here: a direct-insert seed was
-- drafted and tried, but app.milestone_codes is a genuinely platform-wide, non-tenant-
-- scoped registry (app.register_milestone_code is idempotent -- "a repeated call with an
-- existing code returns that row, never raises"), and at least 16 existing scripts/
-- db-tests/*.sql fixtures already register their OWN code definitions for names that
-- collide with an obvious baseline set (delivered, departed_origin, out_for_delivery,
-- customs_hold among them) -- a migration-time seed running before every test file's own
-- setup would silently pre-empt those fixtures' own intended is_customer_visible/
-- affects_eta/is_terminal values instead of letting their own register_milestone_code call
-- take effect (confirmed live: operations-milestone-management.sql's own internal-only
-- customs_hold regressed to customer-visible against a first draft of this seed). Closing
-- this gap correctly needs a full audit of every existing register_milestone_code call
-- across the suite first, not a quick insert -- tracked separately, not attempted in this
-- bounded change.

create unique index resource_assignments_active_resource_unique on app.resource_assignments (tenant_id, resource_id) where is_current and status = 'active';

comment on index app.resource_assignments_active_resource_unique is
  'CG-AUDIT-2026-09-02 E2: at most one CURRENT, ACTIVE assignment per resource at a time -- the actual DB-level enforcement of "one vehicle, one shipment" behind app.assign_resource/app.reassign_resource/app.resume_resource_assignment''s own sequential pre-checks, closing the race the audit found (two concurrent requests both passing an unlocked EXISTS before either commits).';

create or replace function app.assign_resource(p_shipment_order_id uuid, p_role text, p_resource_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.resource_assignments
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_resource app.master_records;
  v_decision app.rbac_decision;
  v_assignment app.resource_assignments;
  v_constraint_name text;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
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

  -- CG-AUDIT-2026-09-02 E2: the two sequential pre-checks above give a clean, immediate
  -- error for the ordinary case; this insert can still race on either backing unique index
  -- (two genuinely concurrent callers, each already past their own pre-check before either
  -- commits) -- disambiguated via GET STACKED DIAGNOSTICS, mirroring
  -- app.start_vendor_assessment's own established pattern, rather than surfacing a raw
  -- unique_violation.
  begin
    insert into app.resource_assignments (
      tenant_id, shipment_order_id, role, resource_id, resource_snapshot, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_role, p_resource_id,
      jsonb_build_object('code', v_resource.code, 'name', v_resource.name), p_actor_label
    )
    returning * into v_assignment;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'resource_assignments_active_resource_unique' then
        raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', p_resource_id
          using errcode = 'check_violation';
      elsif v_constraint_name = 'resource_assignments_current_role_unique' then
        raise exception 'already_assigned: shipment order % already has a current % assignment -- use reassign_resource', p_shipment_order_id, p_role
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_resource',
    'app.resource_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'resource_id', p_resource_id)
  );

  return v_assignment;
end;
$function$;

create or replace function app.reassign_resource(p_shipment_order_id uuid, p_role text, p_new_resource_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.resource_assignments
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_resource app.master_records;
  v_decision app.rbac_decision;
  v_prior app.resource_assignments;
  v_assignment app.resource_assignments;
  v_constraint_name text;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reassigning a resource requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
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

  -- CG-AUDIT-2026-09-02 E2: the pre-check above gives a clean, immediate error for the
  -- ordinary case; this insert can still race on resource_assignments_active_resource_unique
  -- (two genuinely concurrent callers assigning the SAME new resource elsewhere, each
  -- already past their own pre-check before either commits) -- disambiguated via GET
  -- STACKED DIAGNOSTICS, mirroring app.start_vendor_assessment's own established pattern.
  -- An unrecognized constraint (e.g. a genuinely concurrent reassign of this SAME shipment
  -- order/role, a separate, pre-existing race out of this fix's own bounded scope) is
  -- re-raised unchanged, exactly its own prior raw behavior.
  begin
    insert into app.resource_assignments (
      tenant_id, shipment_order_id, role, resource_id, resource_snapshot, reason, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_role, p_new_resource_id,
      jsonb_build_object('code', v_resource.code, 'name', v_resource.name), p_reason, p_actor_label
    )
    returning * into v_assignment;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'resource_assignments_active_resource_unique' then
        raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', p_new_resource_id
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

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
$function$;

create or replace function app.resume_resource_assignment(p_shipment_order_id uuid, p_role text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.resource_assignments
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
  v_constraint_name text;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
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

  -- CG-AUDIT-2026-09-02 E2: a held assignment keeps is_current -- so the SAME resource
  -- could validly be assigned to a different shipment order while this one was held, and
  -- resuming it back to active previously carried no check of any kind for that at all
  -- (not merely racy -- entirely absent, even sequentially).
  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.resource_id = v_current.resource_id
      and ra.is_current
      and ra.status = 'active'
      and ra.id <> v_current.id
  ) then
    raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', v_current.resource_id
      using errcode = 'check_violation';
  end if;

  begin
    update app.resource_assignments
    set status = 'active'
    where id = v_current.id
    returning * into v_current;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'resource_assignments_active_resource_unique' then
        raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', v_current.resource_id
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'resume_resource_assignment',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role)
  );

  return v_current;
end;
$function$;

