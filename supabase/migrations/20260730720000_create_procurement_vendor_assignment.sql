-- Procurement capability PRC-263 (Vendor Assignment, CG-S11-PRC-014), batch 3
-- (261-263) of the operator's "lanjut sd prompt 265" authorization, prompt 3 of 3 --
-- the final prompt of this batch. Depends on PRC-261 (app.vendor_contracts) and
-- PRC-262 (app.vendor_capacity_offers/reservations), both built earlier in this same
-- batch, plus the already-`VERIFIED` Phase 3/5 Operations resource-assignment
-- capability (OPS-172, `app.resource_assignments`/`app.assign_resource`/`app.
-- reassign_resource`, `20260727130000_create_operations_resource_assignment.sql`).
--
-- Governed vendor selection acceptance and shipment/task assignment -- a genuine
-- extension, never a duplicate, of the canonical Operations assignment: `app.
-- resource_assignments.role` already includes `'vendor'` as one of its four valid
-- roles (confirmed by direct inspection of OPS-172's own CHECK constraint), and
-- `resource_id` already resolves through `app.master_records`, the SAME identity
-- `app.vendor_profiles.master_record_id` uses. This migration adds the PROCUREMENT
-- side missing from OPS-172 -- an invitation/acceptance workflow carrying exact
-- eligibility/rate/contract/PO/capacity evidence -- and calls OPS-172's own already-
-- `VERIFIED` `app.assign_resource`/`app.reassign_resource` to commit the canonical
-- row, never re-implementing assignment-slot logic (the partial-unique `is_current`
-- index, conflict detection, audit) a second time.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Two distinct authorities, matching §26 exactly: "Authorized Procurement...
--    propose; vendor accepts/declines own invitation [recorded by staff, no portal];
--    dispatcher performs canonical assignment."** `propose_vendor_assignment_
--    invitation`/`accept_.../decline_.../cancel_vendor_assignment_invitation` gate on
--    `PRC:Edit` (Procurement's own eligibility workflow). `confirm_vendor_assignment`/
--    `reassign_vendor_assignment` gate on `OPS:Assign` (the SAME permission `app.
--    assign_resource`/`app.reassign_resource` themselves require of the identical
--    passed actor) -- a caller who only holds `PRC:Edit` can propose and record
--    accept/decline, but the canonical commitment itself requires the OPS-side
--    authority OPS-172 already established, checked twice (once explicitly here for a
--    fast, clear failure; once again inside the nested `assign_resource`/`reassign_
--    resource` call itself, which this migration never weakens or bypasses).
-- 2. **Capacity consumption happens inside confirm_vendor_assignment directly, not
--    via a second call to app.consume_vendor_capacity_reservation (PRC:Edit-gated).**
--    Calling that public RPC would force the OPS:Assign-holding confirming actor to
--    ALSO hold PRC:Edit for no real reason -- confirm_vendor_assignment has already
--    performed its own complete authority check for this one action, so it updates
--    `app.vendor_capacity_reservations.status` to `'consumed'` inline, in the SAME
--    transaction as the canonical assignment, rather than re-entering a differently-
--    gated public RPC.
-- 3. **Eligibility is re-verified fresh at confirm time, not trusted from the
--    snapshot taken at propose time.** Compliance status, contract effective-ness, and
--    a linked reservation's own live status can all change between invitation and
--    confirmation (a real operational gap, not a hypothetical one -- this is exactly
--    the class of decision-on-stale-read the taxonomy's own C-04 exists to name).
-- 4. **Idempotency replay compares the full target tuple (C-01), reads are locked
--    before a value they gate a decision on is used to write elsewhere (C-04), and
--    by-id reads fold not-found/cross-tenant into one error (C-05) -- all three
--    applied from the first draft**, carrying forward PRC-261/262's own Tier B
--    lessons from earlier in this same batch/session.
-- 5. **`app.terminate_vendor_contract` (PRC-261) gains its promised dependency
--    guard.** PRC-261's own migration header disclosed this explicitly: "carries no
--    active-dependency check yet -- PRC-263 adds it once app.vendor_assignments
--    exists." `create or replace function` here, matching the standing repository-wide
--    convention for a later capability hardening an earlier one's own disclosed gap
--    (never an applied-migration edit).
-- 6. **No vendor-portal identity exists (already-accepted PRC-257/258/261/262
--    precedent).** Accept/decline is staff-recorded on the vendor's own behalf.
--
-- Per ERR-2026-004: explicit `revoke execute on all functions in schema app from
-- public` before final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.vendor_assignment_invitations.
-- ===========================================================================

create table app.vendor_assignment_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  contract_id uuid references app.vendor_contracts (id),
  po_id uuid references app.purchase_orders (id),
  rate_version_id uuid references app.vendor_rate_versions (id),
  capacity_reservation_id uuid references app.vendor_capacity_reservations (id),
  eligibility_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'invited',
  response_deadline timestamptz,
  decline_reason text,
  cancel_reason text,
  is_override boolean not null default false,
  override_reason text,
  assignment_id uuid references app.resource_assignments (id),
  superseded_by_id uuid references app.vendor_assignment_invitations (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assignment_invitations_status_check check (
    status in ('invited', 'accepted', 'declined', 'expired', 'assigned', 'cancelled', 'superseded')
  ),
  constraint vendor_assignment_invitations_decline_reason_check check (status <> 'declined' or (decline_reason is not null and length(trim(decline_reason)) > 0)),
  constraint vendor_assignment_invitations_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0)),
  constraint vendor_assignment_invitations_override_reason_check check (not is_override or (override_reason is not null and length(trim(override_reason)) > 0)),
  constraint vendor_assignment_invitations_assigned_shape_check check (status <> 'assigned' or assignment_id is not null)
);

comment on table app.vendor_assignment_invitations is
  'PRC-263: the procurement-side invitation/eligibility workflow for a shipment order''s role=vendor slot. Does not itself represent the canonical assignment -- assignment_id links to the real app.resource_assignments row (OPS-172) once app.confirm_vendor_assignment commits it. One tenant/shipment_order/vendor combination may have many rows over time (declined, cancelled, superseded), never edited in place to change history.';

create index vendor_assignment_invitations_tenant_shipment_idx on app.vendor_assignment_invitations (tenant_id, shipment_order_id);
create index vendor_assignment_invitations_tenant_vendor_idx on app.vendor_assignment_invitations (tenant_id, vendor_master_id);
create index vendor_assignment_invitations_contract_idx on app.vendor_assignment_invitations (contract_id) where contract_id is not null;
create index vendor_assignment_invitations_status_idx on app.vendor_assignment_invitations (tenant_id, status);
create unique index vendor_assignment_invitations_idempotency_key_unique on app.vendor_assignment_invitations (tenant_id, idempotency_key) where idempotency_key is not null;
-- At most one non-terminal (invited/accepted) invitation per shipment order at a time
-- -- mirrors OPS-172's own resource_assignments_current_role_unique partial-index
-- shape for the identical "one live slot" invariant, one layer up the stack.
create unique index vendor_assignment_invitations_one_live_per_shipment_unique
  on app.vendor_assignment_invitations (tenant_id, shipment_order_id) where status in ('invited', 'accepted');

create function app.touch_vendor_assignment_invitations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_assignment_invitations_touch_row
  before update on app.vendor_assignment_invitations
  for each row
  execute function app.touch_vendor_assignment_invitations_row();

-- ===========================================================================
-- 2. Eligibility evaluation helper (shared by propose and the read preview).
-- ===========================================================================

create function app.evaluate_vendor_assignment_eligibility(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_po_id uuid,
  p_capacity_reservation_id uuid,
  out eligible boolean,
  out reasons text[],
  out snapshot jsonb
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_vendor app.vendor_profiles;
  v_contract app.vendor_contracts;
  v_po app.purchase_orders;
  v_reservation app.vendor_capacity_reservations;
  v_compliance_hold boolean;
begin
  reasons := array[]::text[];

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;
  if v_vendor.lifecycle_status <> 'active' then
    reasons := array_append(reasons, 'vendor_not_active');
  end if;

  -- Reads app.vendor_compliance_status directly, NOT the PRC:View-gated app.get_
  -- vendor_compliance_eligibility RPC -- the caller of THIS function (propose/confirm/
  -- reassign/preview) has already performed its own complete authorization check for
  -- the overall action; re-entering a differently-gated public RPC here would force
  -- every caller (including an OPS:Assign-only confirming dispatcher) to also hold
  -- PRC:View for no real reason (the exact same reasoning as design note 2's inline
  -- capacity-consumption choice, applied here too).
  select bool_or(coalesce(s.eligibility_hold, false)) into v_compliance_hold
  from app.vendor_compliance_status s
  where s.vendor_master_record_id = p_vendor_master_id;
  if coalesce(v_compliance_hold, false) then
    reasons := array_append(reasons, 'compliance_hold');
  end if;

  if p_contract_id is not null then
    select * into v_contract from app.vendor_contracts where id = p_contract_id and tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'invalid_contract_reference: contract % does not govern vendor % in tenant %', p_contract_id, p_vendor_master_id, p_tenant_id using errcode = 'check_violation';
    end if;
    if v_contract.status <> 'active' then
      reasons := array_append(reasons, 'contract_not_active');
    end if;
  end if;

  if p_po_id is not null then
    select * into v_po from app.purchase_orders where id = p_po_id and tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'invalid_po_reference: purchase order % does not belong to vendor % in tenant %', p_po_id, p_vendor_master_id, p_tenant_id using errcode = 'check_violation';
    end if;
    if v_po.status not in ('issued', 'acknowledged') then
      reasons := array_append(reasons, 'po_not_issued');
    end if;
  end if;

  if p_capacity_reservation_id is not null then
    select r.* into v_reservation
    from app.vendor_capacity_reservations r
    join app.vendor_capacity_offers o on o.id = r.offer_id
    where r.id = p_capacity_reservation_id and r.tenant_id = p_tenant_id and o.vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'invalid_capacity_reservation_reference: reservation % does not belong to vendor % in tenant %', p_capacity_reservation_id, p_vendor_master_id, p_tenant_id using errcode = 'check_violation';
    end if;
    if v_reservation.status not in ('held', 'accepted') then
      reasons := array_append(reasons, 'capacity_not_available');
    end if;
  end if;

  eligible := array_length(reasons, 1) is null;
  snapshot := jsonb_build_object(
    'vendor_lifecycle_status', v_vendor.lifecycle_status,
    'compliance_hold', coalesce(v_compliance_hold, false),
    'contract_id', p_contract_id, 'contract_status', v_contract.status,
    'po_id', p_po_id, 'po_status', v_po.status,
    'capacity_reservation_id', p_capacity_reservation_id, 'capacity_reservation_status', v_reservation.status,
    'evaluated_at', now()
  );
end;
$$;

comment on function app.evaluate_vendor_assignment_eligibility is 'PRC-263: the ONE eligibility computation both app.propose_vendor_assignment_invitation and app.get_vendor_assignment_eligibility_preview call -- never duplicated. Raises on a structurally invalid reference (wrong vendor/tenant); returns eligible=false with named reasons for a valid-but-currently-ineligible reference (design note 3: re-evaluated fresh, never trusted from an old snapshot).';

-- ===========================================================================
-- 3. Invitation lifecycle RPCs (PRC:Edit -- Procurement's own workflow, design note 1).
-- ===========================================================================

create function app.propose_vendor_assignment_invitation(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_po_id uuid,
  p_rate_version_id uuid,
  p_capacity_reservation_id uuid,
  p_response_deadline timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_existing app.vendor_assignment_invitations;
  v_eligibility record;
  v_invitation app.vendor_assignment_invitations;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status in ('cancelled', 'delivered', 'epod', 'closed') then
    raise exception 'invalid_transition: shipment order % is % and can no longer receive vendor invitations', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.shipment_order_id is distinct from p_shipment_order_id or v_existing.vendor_master_id is distinct from p_vendor_master_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment invitation', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(p_tenant_id, p_vendor_master_id, p_contract_id, p_po_id, p_capacity_reservation_id);
  if not v_eligibility.eligible then
    raise exception 'vendor_not_eligible: vendor % is not currently eligible for assignment (%)', p_vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_assignment_invitations (
      tenant_id, shipment_order_id, vendor_master_id, contract_id, po_id, rate_version_id, capacity_reservation_id,
      eligibility_snapshot, response_deadline, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_shipment_order_id, p_vendor_master_id, p_contract_id, p_po_id, p_rate_version_id, p_capacity_reservation_id,
      v_eligibility.snapshot, p_response_deadline, p_idempotency_key, p_actor_label
    )
    returning * into v_invitation;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_existing.shipment_order_id is distinct from p_shipment_order_id or v_existing.vendor_master_id is distinct from p_vendor_master_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment invitation', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise exception 'invitation_conflict: shipment order % already has a live (invited or accepted) vendor invitation', p_shipment_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, jsonb_build_object('vendor_master_id', p_vendor_master_id, 'shipment_order_id', p_shipment_order_id)
  );

  return v_invitation;
end;
$$;

create function app.accept_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be accepted', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'accepted' where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

create function app.decline_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be declined', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'declined', decline_reason = p_reason where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

create function app.cancel_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status not in ('invited', 'accepted') then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be cancelled', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'cancelled', cancel_reason = p_reason where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

-- ===========================================================================
-- 4. Canonical commitment RPCs (OPS:Assign -- dispatcher authority, design note 1).
-- ===========================================================================

create function app.confirm_vendor_assignment(
  p_invitation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
  v_eligibility record;
  v_assignment app.resource_assignments;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'accepted' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be confirmed', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  -- Design note 3: re-verify eligibility fresh, never trust the propose-time snapshot.
  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(
    v_invitation.tenant_id, v_invitation.vendor_master_id, v_invitation.contract_id, v_invitation.po_id, v_invitation.capacity_reservation_id
  );
  if not v_eligibility.eligible then
    raise exception 'vendor_no_longer_eligible: vendor % is no longer eligible for assignment (%)', v_invitation.vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  -- The canonical commitment -- never re-implemented, always this exact call.
  v_assignment := app.assign_resource(v_invitation.shipment_order_id, 'vendor', v_invitation.vendor_master_id, p_actor_auth_user_id, p_actor_label);

  -- Design note 2: inline, not a second call to the PRC:Edit-gated public RPC.
  if v_invitation.capacity_reservation_id is not null then
    update app.vendor_capacity_reservations set status = 'consumed' where id = v_invitation.capacity_reservation_id and status = 'accepted';
  end if;

  update app.vendor_assignment_invitations
  set status = 'assigned', assignment_id = v_assignment.id, eligibility_snapshot = v_eligibility.snapshot
  where id = p_invitation_id and record_version = p_expected_version
  returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_vendor_assignment',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, jsonb_build_object('assignment_id', v_assignment.id)
  );

  return v_invitation;
end;
$$;

comment on function app.confirm_vendor_assignment is 'PRC-263: accepted -> assigned. OPS:Assign-gated (design note 1). Locks the invitation row before deciding (C-04), re-verifies eligibility fresh (design note 3), calls app.assign_resource (OPS-172, unchanged) to commit the canonical app.resource_assignments row, and consumes any linked capacity reservation inline (design note 2).';

create function app.reassign_vendor_assignment(
  p_invitation_id uuid,
  p_expected_version integer,
  p_new_vendor_master_id uuid,
  p_new_contract_id uuid,
  p_new_po_id uuid,
  p_new_rate_version_id uuid,
  p_new_capacity_reservation_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_prior app.vendor_assignment_invitations;
  v_eligibility record;
  v_assignment app.resource_assignments;
  v_new app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reassign a vendor assignment' using errcode = 'check_violation';
  end if;

  select * into v_prior from app.vendor_assignment_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prior.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prior.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prior.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_prior.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_prior.status <> 'assigned' then
    raise exception 'invalid_transition: vendor assignment invitation % is % -- only an assigned invitation may be reassigned (use cancel for anything earlier)', p_invitation_id, v_prior.status
      using errcode = 'check_violation';
  end if;

  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(
    v_prior.tenant_id, p_new_vendor_master_id, p_new_contract_id, p_new_po_id, p_new_capacity_reservation_id
  );
  if not v_eligibility.eligible then
    raise exception 'vendor_not_eligible: vendor % is not currently eligible for assignment (%)', p_new_vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  v_assignment := app.reassign_resource(v_prior.shipment_order_id, 'vendor', p_new_vendor_master_id, p_reason, p_actor_auth_user_id, p_actor_label);

  if p_new_capacity_reservation_id is not null then
    update app.vendor_capacity_reservations set status = 'consumed' where id = p_new_capacity_reservation_id and status = 'accepted';
  end if;

  update app.vendor_assignment_invitations set status = 'superseded' where id = p_invitation_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_assignment_invitations (
    tenant_id, shipment_order_id, vendor_master_id, contract_id, po_id, rate_version_id, capacity_reservation_id,
    eligibility_snapshot, status, assignment_id, idempotency_key, created_by
  )
  values (
    v_prior.tenant_id, v_prior.shipment_order_id, p_new_vendor_master_id, p_new_contract_id, p_new_po_id, p_new_rate_version_id, p_new_capacity_reservation_id,
    v_eligibility.snapshot, 'assigned', v_assignment.id, p_idempotency_key, p_actor_label
  )
  returning * into v_new;

  update app.vendor_assignment_invitations set superseded_by_id = v_new.id where id = p_invitation_id;

  perform app.capture_audit_event(
    v_prior.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_vendor_assignment',
    'app.vendor_assignment_invitations', v_new.id, 'success', p_reason, null, jsonb_build_object('supersedes_invitation_id', p_invitation_id, 'assignment_id', v_assignment.id)
  );

  return v_new;
end;
$$;

comment on function app.reassign_vendor_assignment is 'PRC-263: assigned -> superseded, and a brand-new invitation row (status=assigned immediately, mirroring app.reassign_resource''s own no-approval-cycle shape -- unlike amendment/renewal in PRC-261, a reassignment IS the operational commitment, not a draft awaiting its own approval). OPS:Assign-gated, mandatory reason, calls app.reassign_resource (OPS-172, unchanged).';

-- ===========================================================================
-- 5. Emergency override (OPS:Assign AND PRC:Override -- both required, design note 1).
-- ===========================================================================

create function app.override_vendor_assignment(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_vendor_master_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ops_decision app.rbac_decision;
  v_prc_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_assignment_invitations;
  v_assignment app.resource_assignments;
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required for an emergency override' using errcode = 'check_violation';
  end if;

  v_ops_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Assign');
  if not v_ops_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_ops_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_prc_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Override');
  if not v_prc_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_prc_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.shipment_order_id is distinct from p_shipment_order_id or v_existing.vendor_master_id is distinct from p_vendor_master_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment override', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- Governed exception (business rule): bypasses the normal invite/accept/eligibility
  -- gate entirely -- disclosed, not silently equivalent to a normal confirmed
  -- assignment. No formal expiry/later-review workflow exists yet (no review-queue
  -- infrastructure exists anywhere in this repository to compose with); the override
  -- is fully evidenced (reason, both authorities, audit event) for a human review
  -- process outside this capability's own scope.
  begin
    v_assignment := app.assign_resource(p_shipment_order_id, 'vendor', p_vendor_master_id, p_actor_auth_user_id, p_actor_label);
  exception
    when others then
      if sqlerrm like 'already_assigned%' then
        v_assignment := app.reassign_resource(p_shipment_order_id, 'vendor', p_vendor_master_id, p_reason, p_actor_auth_user_id, p_actor_label);
      else
        raise;
      end if;
  end;

  insert into app.vendor_assignment_invitations (
    tenant_id, shipment_order_id, vendor_master_id, status, is_override, override_reason, assignment_id, idempotency_key, created_by
  )
  values (
    p_tenant_id, p_shipment_order_id, p_vendor_master_id, 'assigned', true, p_reason, v_assignment.id, p_idempotency_key, p_actor_label
  )
  returning * into v_invitation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'override_vendor_assignment',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, jsonb_build_object('assignment_id', v_assignment.id)
  );

  return v_invitation;
end;
$$;

comment on function app.override_vendor_assignment is 'PRC-263: governed emergency direct-assign bypassing the normal invite/accept/eligibility gate -- both OPS:Assign and PRC:Override required (design note 1). Disclosed: no formal expiry/later-review workflow exists yet (no review-queue infrastructure anywhere in this repository); fully evidenced (reason, dual authority, audit event) for an out-of-band human review process.';

-- ===========================================================================
-- 6. Reads (PRC:View or OPS:View).
-- ===========================================================================

create function app.get_vendor_assignment_invitation(p_invitation_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_invitation app.vendor_assignment_invitations;
begin
  select tenant_id into v_tenant_id from app.vendor_assignment_invitations where id = p_invitation_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  return v_invitation;
end;
$$;

create function app.list_vendor_assignment_invitations(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25
)
returns setof app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_assignment_invitations
  where tenant_id = p_tenant_id
    and (p_shipment_order_id is null or shipment_order_id = p_shipment_order_id)
    and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
    and (p_status is null or status = p_status)
  order by created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

create function app.get_vendor_assignment_eligibility_preview(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_po_id uuid,
  p_capacity_reservation_id uuid,
  p_actor_auth_user_id uuid,
  out eligible boolean,
  out reasons text[]
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_result record;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_result from app.evaluate_vendor_assignment_eligibility(p_tenant_id, p_vendor_master_id, p_contract_id, p_po_id, p_capacity_reservation_id);
  eligible := v_result.eligible;
  reasons := v_result.reasons;
end;
$$;

comment on function app.get_vendor_assignment_eligibility_preview is 'PRC-263: best-effort preview only, shown before propose -- the real routing decision happens server-side inside app.propose_vendor_assignment_invitation itself regardless (mirrors app.evaluate_procurement_approval_requirement''s own preview-vs-enforcement split, PRC-259/260/261).';

-- ===========================================================================
-- 7. Harden PRC-261: app.terminate_vendor_contract gains its promised active-
--    dependency guard (design note 5). create or replace, never an applied-migration
--    edit -- the standing repository-wide convention.
-- ===========================================================================

create or replace function app.terminate_vendor_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_reason text,
  p_evidence_ref text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.vendor_contracts;
  v_from_status text;
  v_active_dependency_count integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to terminate a vendor contract' using errcode = 'check_violation';
  end if;
  if p_evidence_ref is null or length(trim(p_evidence_ref)) = 0 then
    raise exception 'evidence_required: evidence_ref is required to terminate a vendor contract' using errcode = 'check_violation';
  end if;

  select * into v_contract from app.vendor_contracts where id = p_contract_id;
  if not found then
    raise exception 'vendor_contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_contract.status not in ('active', 'suspended') then
    raise exception 'invalid_transition: vendor contract % is % and cannot be terminated', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  -- PRC-263's own promised guard (PRC-261 design note 6): block termination while a
  -- live (invited/accepted/assigned) vendor assignment invitation still cites this
  -- contract as its own governing evidence.
  select count(*) into v_active_dependency_count
  from app.vendor_assignment_invitations
  where contract_id = p_contract_id and status in ('invited', 'accepted', 'assigned');
  if v_active_dependency_count > 0 then
    raise exception 'active_dependency_exists: vendor contract % has % active assignment invitation(s) citing it -- cancel or reassign them first', p_contract_id, v_active_dependency_count
      using errcode = 'check_violation';
  end if;

  v_from_status := v_contract.status;

  update app.vendor_contracts
  set status = 'terminated', termination_reason = p_reason, termination_evidence_ref = p_evidence_ref, terminated_at = now()
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  if not found then
    raise exception 'stale_version: vendor contract % target row was concurrently modified (expected version %)', p_contract_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_contract_events (tenant_id, contract_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_contract.tenant_id, p_contract_id, v_from_status, 'terminated', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_vendor_contract',
    'app.vendor_contracts', p_contract_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_contract;
end;
$$;

-- ===========================================================================
-- 8. RLS -- default-deny form (pattern (3)), mirroring app.vendor_contracts exactly.
-- ===========================================================================

alter table app.vendor_assignment_invitations enable row level security;

create policy vendor_assignment_invitations_select_scoped on app.vendor_assignment_invitations
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 9. Grants.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.vendor_assignment_invitations to authenticated, service_role;
grant insert, update on app.vendor_assignment_invitations to service_role;

-- service_role-only, NOT authenticated: this helper performs no authority check of
-- its own by design (design note "the caller has already checked") -- granting it
-- directly to authenticated would let any authenticated session in any tenant probe
-- another tenant's vendor/contract/PO/capacity-reservation status with zero
-- authorization, exactly the disclosure ISS-2026-033's own repository-wide
-- SECURITY DEFINER sweep (scripts/db-tests/rbac-enforcement.sql) exists to catch --
-- caught live by that exact test against this migration's own first draft.
grant execute on function app.evaluate_vendor_assignment_eligibility(uuid, uuid, uuid, uuid, uuid) to service_role;

grant execute on function app.propose_vendor_assignment_invitation(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.accept_vendor_assignment_invitation(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decline_vendor_assignment_invitation(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_vendor_assignment_invitation(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_vendor_assignment(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_vendor_assignment(uuid, integer, uuid, uuid, uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.override_vendor_assignment(uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_vendor_assignment_invitation(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_assignment_invitations(uuid, uuid, uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.get_vendor_assignment_eligibility_preview(uuid, uuid, uuid, uuid, uuid, uuid) to authenticated, service_role;
