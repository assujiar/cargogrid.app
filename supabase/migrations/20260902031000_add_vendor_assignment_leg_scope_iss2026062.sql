-- ISS-2026-062 closure: additive shipment-leg granularity for vendor assignment
-- (PRC-263, app.vendor_assignment_invitations,
-- supabase/migrations/20260730720000_create_procurement_vendor_assignment.sql).
-- 263_VENDOR_ASSIGNMENT_PROMPT.md (lines 24, 60, 76, 96, 125) repeatedly names
-- "shipment/leg/task" as the assignment capability's own extension target and
-- requires a multi-leg test scenario -- confirmed absent by grep against the
-- applied migration and its own db-test file.
--
-- Live-drift check performed before writing this file: app.evaluate_vendor_
-- assignment_eligibility, app.propose_vendor_assignment_invitation, app.confirm_
-- vendor_assignment, and app.reassign_vendor_assignment were all read live via
-- pg_get_functiondef, not from the applied migration file text. All four have
-- drifted since 20260730720000 -- a later "Tier C batch-3" fix pass added a
-- resolved_contract_id OUT parameter to the eligibility function, a C-05
-- has_active_tenant_membership fold-to-not-found guard to confirm/reassign, a
-- contract effective-date/auto-resolution check, and a full idempotency-tuple
-- pre-check/race-recovery handler to reassign that the applied migration's own
-- text does not have. This migration's own widened function bodies below
-- reproduce the CURRENT LIVE bodies verbatim, with only the leg-scoping logic
-- added (never re-deriving from the stale migration file text).
--
-- Data model read live before designing (per this checkpoint's own mandate):
-- app.shipment_legs (ATW-221, 20260729290000_create_advanced_tms_multi_leg_
-- shipment.sql) already carries carrier_master_id uuid references app.master_
-- records(id), accepting a vendor OR fleet master record -- exactly the "per-leg
-- carrier reference" ISS-2026-062's own discovery text names ("never composes
-- with app.shipment_legs.carrier_master_id"). No generic "job task" table exists
-- for a shipment (the only *_task* tables in this repository are WMS-scoped --
-- wms_pick_tasks/wms_packing_tasks/wms_putaway_tasks -- and onboarding-case-scoped,
-- structurally unrelated to a shipment's own execution units) -- so "leg/task
-- granularity" resolves to leg granularity via the real app.shipment_legs table,
-- the compatible concept the task instructions direct reuse toward instead of
-- inventing a parallel one.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Nullable FK, backward compatible (the task's own required shape).**
--    app.vendor_assignment_invitations gains shipment_leg_id uuid references
--    app.shipment_legs(id), nullable. shipment_leg_id is null means exactly
--    today's behavior: a whole-shipment vendor assignment. Structurally enforced
--    (trigger, mirrors PRC-255's own app.enforce_vendor_rate_version_vendor_
--    identity pattern) to reference a leg belonging to the SAME shipment_order_id
--    and tenant_id as the invitation itself.
-- 2. **The canonical OPS-172 tables (app.resource_assignments, app.assign_
--    resource, app.reassign_resource) are NOT touched at all -- zero risk to the
--    fleet/vehicle/driver roles those functions also serve.** app.resource_
--    assignments' own uniqueness is shipment-order-scoped only (one current
--    'vendor' role assignment per shipment order); widening that foundation to
--    understand legs would be a materially larger, riskier change serving three
--    roles this issue was never about. Instead, a LEG-SCOPED confirm/reassign
--    commits directly to app.shipment_legs.carrier_master_id (design note above)
--    -- an already-existing, already-vendor/fleet-typed column ATW-221 built for
--    exactly this purpose but that nothing had ever written to after leg
--    creation until now. A WHOLE-SHIPMENT confirm/reassign (shipment_leg_id is
--    null) is byte-identical to today: it still calls app.assign_resource/app.
--    reassign_resource, unmodified. This is how "a whole-shipment assignment
--    (no leg reference) behaves exactly as before" is guaranteed -- the exact
--    same code path runs, untouched, when there is no leg to scope to.
-- 3. **Uniqueness, widened without weakening the existing invariant.** The old
--    partial unique index (tenant_id, shipment_order_id) where status in
--    ('invited','accepted') allowed at most one live invitation on a shipment
--    order, period -- naive per-leg partitioning
--    (tenant_id, shipment_order_id, shipment_leg_id) would silently break that
--    invariant for the null case: Postgres treats NULL <> NULL in a unique
--    index, so multiple concurrent whole-shipment (leg=null) rows would no
--    longer collide. Fixed with a coalesce-to-sentinel index, the same technique
--    PRC-255's own scope_key generated column already established in this
--    repository (20260730620000, design note 4) for an identical
--    "null must still mean one slot" problem: `coalesce(shipment_leg_id,
--    '00000000-0000-0000-0000-000000000000'::uuid)`. Result: at most one live
--    whole-shipment invitation (unchanged), and independently, at most one live
--    invitation per distinct leg.
-- 4. **Documented, not silently wrong: a leg-scoped query never returns
--    whole-shipment rows, and vice versa.** app.list_vendor_assignment_
--    invitations' new p_shipment_leg_id filter matches shipment_leg_id EXACTLY
--    -- a query for "assignments on this leg" (p_shipment_leg_id supplied) never
--    returns a whole-shipment invitation (shipment_leg_id is null), and the
--    unfiltered/default case (p_shipment_leg_id omitted, every existing caller)
--    is completely unaffected. Resolving "the effective vendor for a leg,
--    falling back to the whole-shipment assignment if the leg itself has none"
--    is a read-composition decision left to the caller -- disclosed here as an
--    explicit, deliberate scope boundary, not an oversight.
-- 5. **app.override_vendor_assignment (the emergency bypass path) is
--    deliberately NOT widened with leg scoping in this migration** -- it
--    remains whole-shipment only, a disclosed, bounded scope trim (the primary
--    governed invite/accept/confirm/reassign flow is the one this issue's own
--    text and acceptance criteria are about; the override path already carries
--    its own documented residual-gap disclosure in the applied migration).
-- 6. Authority is UNCHANGED: propose/accept/decline/cancel keep PRC:Edit;
--    confirm/reassign keep OPS:Assign (re-checked, never weakened, for the
--    leg-scoped branch exactly as for the whole-shipment branch). No new
--    permission is seeded.
-- 7. Per ERR-2026-004: explicit `revoke execute on all functions in schema app
--    from public` before final grants.

-- ===========================================================================
-- 1. Schema: nullable leg FK, structural scope trigger, widened uniqueness,
--    widened assigned-shape constraint (design notes 1, 2, 3).
-- ===========================================================================

alter table app.vendor_assignment_invitations add column shipment_leg_id uuid references app.shipment_legs (id);

comment on column app.vendor_assignment_invitations.shipment_leg_id is 'ISS-2026-062: optional leg-granularity scope. Null (the default, and every pre-existing row) means whole-shipment -- exactly PRC-263''s original behavior. When set, the referenced leg must belong to the same shipment_order_id and tenant_id as this invitation (app.enforce_vendor_assignment_invitation_leg_scope, structural trigger).';

create index vendor_assignment_invitations_leg_idx on app.vendor_assignment_invitations (shipment_leg_id) where shipment_leg_id is not null;

create function app.enforce_vendor_assignment_invitation_leg_scope()
returns trigger
language plpgsql
as $$
declare
  v_leg app.shipment_legs;
begin
  if new.shipment_leg_id is null then
    return new;
  end if;
  select * into v_leg from app.shipment_legs where id = new.shipment_leg_id;
  if not found then
    raise exception 'shipment_leg_not_found: %', new.shipment_leg_id using errcode = 'foreign_key_violation';
  end if;
  if v_leg.shipment_order_id is distinct from new.shipment_order_id then
    raise exception 'invalid_leg_reference: shipment leg % belongs to shipment order %, not %', new.shipment_leg_id, v_leg.shipment_order_id, new.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if v_leg.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_leg_reference: shipment leg % belongs to tenant %, not %', new.shipment_leg_id, v_leg.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger vendor_assignment_invitations_enforce_leg_scope
  before insert or update of shipment_leg_id, shipment_order_id, tenant_id on app.vendor_assignment_invitations
  for each row
  execute function app.enforce_vendor_assignment_invitation_leg_scope();

comment on trigger vendor_assignment_invitations_enforce_leg_scope on app.vendor_assignment_invitations is 'ISS-2026-062: structural defense-in-depth (mirrors PRC-255''s app.enforce_vendor_rate_version_vendor_identity pattern) -- app.propose_vendor_assignment_invitation also performs the identical check explicitly, ahead of insert, for a clearer error; this trigger is the guarantee that holds even if a future write path forgets to.';

-- Design note 3: coalesce-to-sentinel widening -- preserves "at most one live
-- whole-shipment invitation" (unchanged) and adds "at most one live invitation
-- per distinct leg", without the NULL<>NULL unique-index pitfall a naive
-- (tenant_id, shipment_order_id, shipment_leg_id) index would introduce.
drop index app.vendor_assignment_invitations_one_live_per_shipment_unique;

create unique index vendor_assignment_invitations_one_live_per_scope_unique
  on app.vendor_assignment_invitations (tenant_id, shipment_order_id, coalesce(shipment_leg_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status in ('invited', 'accepted');

comment on index app.vendor_assignment_invitations_one_live_per_scope_unique is 'ISS-2026-062: supersedes vendor_assignment_invitations_one_live_per_shipment_unique. coalesce(...,''00000000-...''::uuid) makes the whole-shipment (leg=null) case a single shared sentinel slot -- still at most one live whole-shipment invitation, unchanged from before this migration -- while each distinct real leg id gets its own independent slot.';

-- Design note 2: a leg-scoped confirmed invitation commits to app.shipment_legs.
-- carrier_master_id directly, never to app.resource_assignments -- so
-- assignment_id stays null for that row. The shape constraint below is widened
-- to accept EITHER evidence of commitment, never both required and never
-- neither.
alter table app.vendor_assignment_invitations drop constraint vendor_assignment_invitations_assigned_shape_check;
alter table app.vendor_assignment_invitations add constraint vendor_assignment_invitations_assigned_shape_check
  check (status <> 'assigned' or assignment_id is not null or shipment_leg_id is not null);

-- ===========================================================================
-- 2. app.propose_vendor_assignment_invitation widened -- one new trailing
--    optional parameter, p_shipment_leg_id. The current live signature (11
--    positional arguments, confirmed via pg_get_functiondef immediately before
--    writing this file) gains a 12th; DROP + CREATE (not a bare `create or
--    replace`) so exactly one function exists afterward, matching this
--    repository's own established convention (20260730620000, section 4's own
--    header note) -- a bare CREATE OR REPLACE with an added parameter creates a
--    coexisting overload instead of truly replacing the original.
-- ===========================================================================

drop function if exists app.propose_vendor_assignment_invitation(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text, uuid, text);

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
  p_actor_label text,
  p_shipment_leg_id uuid default null
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_leg app.shipment_legs;
  v_rate app.vendor_rate_versions;
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

  -- ISS-2026-062 addition (design note 1): explicit, clearer-message check ahead
  -- of the structural trigger (this repository's own standing defense-in-depth
  -- convention). p_shipment_leg_id is left null on every pre-existing caller --
  -- this whole block is skipped for the whole-shipment case, completely
  -- unaffected.
  if p_shipment_leg_id is not null then
    select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
    if not found then
      raise exception 'shipment_leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
    end if;
    if v_leg.shipment_order_id <> p_shipment_order_id then
      raise exception 'invalid_leg_reference: shipment leg % belongs to shipment order %, not %', p_shipment_leg_id, v_leg.shipment_order_id, p_shipment_order_id
        using errcode = 'check_violation';
    end if;
    if v_leg.tenant_id <> p_tenant_id then
      raise exception 'invalid_leg_reference: shipment leg % belongs to tenant %, not %', p_shipment_leg_id, v_leg.tenant_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
    if v_leg.leg_status = 'cancelled' then
      raise exception 'invalid_transition: shipment leg % is cancelled and can no longer receive vendor invitations', p_shipment_leg_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> p_tenant_id or v_rate.vendor_master_id is distinct from p_vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to vendor % in tenant %', p_rate_version_id, p_vendor_master_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.shipment_order_id is distinct from p_shipment_order_id
         or v_existing.vendor_master_id is distinct from p_vendor_master_id
         or v_existing.shipment_leg_id is distinct from p_shipment_leg_id
         or (p_contract_id is not null and v_existing.contract_id is distinct from p_contract_id)
         or v_existing.po_id is distinct from p_po_id
         or v_existing.rate_version_id is distinct from p_rate_version_id
         or v_existing.capacity_reservation_id is distinct from p_capacity_reservation_id
         or v_existing.response_deadline is distinct from p_response_deadline then
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
      tenant_id, shipment_order_id, shipment_leg_id, vendor_master_id, contract_id, po_id, rate_version_id, capacity_reservation_id,
      eligibility_snapshot, response_deadline, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_vendor_master_id, v_eligibility.resolved_contract_id, p_po_id, p_rate_version_id, p_capacity_reservation_id,
      v_eligibility.snapshot, p_response_deadline, p_idempotency_key, p_actor_label
    )
    returning * into v_invitation;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_assignment_invitations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_existing.shipment_order_id is distinct from p_shipment_order_id
           or v_existing.vendor_master_id is distinct from p_vendor_master_id
           or v_existing.shipment_leg_id is distinct from p_shipment_leg_id
           or (p_contract_id is not null and v_existing.contract_id is distinct from p_contract_id)
           or v_existing.po_id is distinct from p_po_id
           or v_existing.rate_version_id is distinct from p_rate_version_id
           or v_existing.capacity_reservation_id is distinct from p_capacity_reservation_id
           or v_existing.response_deadline is distinct from p_response_deadline then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment invitation', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise exception 'invitation_conflict: shipment order % already has a live (invited or accepted) vendor invitation at this leg scope', p_shipment_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null,
    jsonb_build_object('vendor_master_id', p_vendor_master_id, 'shipment_order_id', p_shipment_order_id, 'shipment_leg_id', p_shipment_leg_id)
  );

  return v_invitation;
end;
$$;

comment on function app.propose_vendor_assignment_invitation is 'PRC-263, widened ISS-2026-062: one new trailing optional parameter, p_shipment_leg_id (default null = whole-shipment, exactly the pre-existing behavior). When supplied, the leg must belong to the same shipment order and tenant (explicit check here, defense-in-depth trigger backs it structurally too). PRC:Edit-gated, unchanged.';

-- ===========================================================================
-- 3. app.confirm_vendor_assignment widened -- unchanged 4-argument signature,
--    so `create or replace function` (not DROP+CREATE). Reproduces the CURRENT
--    LIVE body (Tier C batch-3's C-05 fold-to-not-found guard and C-20
--    resolved-contract persistence, both absent from the applied migration
--    file's own text) plus the leg-scoped commit branch (design note 2).
-- ===========================================================================

create or replace function app.confirm_vendor_assignment(
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
  v_leg app.shipment_legs;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, preserved from the live body): fold cross-tenant
  -- to the identical not-found a genuinely nonexistent id would produce.
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
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

  -- Design note 3 (PRC-263, preserved): re-verify eligibility fresh, never trust
  -- the propose-time snapshot.
  select * into v_eligibility from app.evaluate_vendor_assignment_eligibility(
    v_invitation.tenant_id, v_invitation.vendor_master_id, v_invitation.contract_id, v_invitation.po_id, v_invitation.capacity_reservation_id
  );
  if not v_eligibility.eligible then
    raise exception 'vendor_no_longer_eligible: vendor % is no longer eligible for assignment (%)', v_invitation.vendor_master_id, array_to_string(v_eligibility.reasons, ', ')
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-062 (design note 2): the canonical commitment branches on
  -- shipment_leg_id. Null (every pre-existing invitation, and every new
  -- whole-shipment one) is BYTE-IDENTICAL to before -- the same, unmodified
  -- app.assign_resource call. Non-null commits directly to app.shipment_legs.
  -- carrier_master_id instead, since app.assign_resource/app.resource_
  -- assignments are shipment-order-scoped only and would incorrectly collide
  -- across legs of the same shipment.
  if v_invitation.shipment_leg_id is null then
    v_assignment := app.assign_resource(v_invitation.shipment_order_id, 'vendor', v_invitation.vendor_master_id, p_actor_auth_user_id, p_actor_label);
  else
    select * into v_leg from app.shipment_legs where id = v_invitation.shipment_leg_id for update;
    if not found then
      raise exception 'shipment_leg_not_found: %', v_invitation.shipment_leg_id using errcode = 'no_data_found';
    end if;
    if v_leg.carrier_master_id is not null and v_leg.carrier_master_id is distinct from v_invitation.vendor_master_id then
      raise exception 'leg_already_assigned: shipment leg % already has an active carrier assignment -- use app.reassign_vendor_assignment instead', v_invitation.shipment_leg_id
        using errcode = 'check_violation';
    end if;
    update app.shipment_legs set carrier_master_id = v_invitation.vendor_master_id where id = v_invitation.shipment_leg_id;
  end if;

  -- Design note 2 (PRC-263, preserved): inline, not a second call to the
  -- PRC:Edit-gated public RPC.
  if v_invitation.capacity_reservation_id is not null then
    update app.vendor_capacity_reservations set status = 'consumed' where id = v_invitation.capacity_reservation_id and status = 'accepted';
  end if;

  -- C-20 (Tier C batch-3 fix, preserved from the live body): persist a
  -- freshly-resolved contract_id onto the canonical row, never silently dropped.
  update app.vendor_assignment_invitations
  set status = 'assigned', assignment_id = v_assignment.id, eligibility_snapshot = v_eligibility.snapshot, contract_id = v_eligibility.resolved_contract_id
  where id = p_invitation_id and record_version = p_expected_version
  returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_vendor_assignment',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null,
    jsonb_build_object('assignment_id', v_assignment.id, 'shipment_leg_id', v_invitation.shipment_leg_id)
  );

  return v_invitation;
end;
$$;

comment on function app.confirm_vendor_assignment is 'PRC-263, widened ISS-2026-062: OPS:Assign-gated, unchanged. A whole-shipment invitation (shipment_leg_id is null) calls app.assign_resource exactly as before -- byte-identical. A leg-scoped invitation commits to app.shipment_legs.carrier_master_id directly instead (design note 2), refusing with leg_already_assigned if the leg already carries a different carrier.';

-- ===========================================================================
-- 4. app.reassign_vendor_assignment widened -- unchanged 11-argument signature,
--    so `create or replace function`. Reproduces the CURRENT LIVE body (Tier C
--    batch-3's C-05 fold, C-15 rate scope-mismatch check, and the full
--    C-01/C-02 idempotency pre-check/race-recovery handler, all absent from the
--    applied migration file's own text) plus the leg-scoped commit branch,
--    carrying the prior invitation's own shipment_leg_id forward unchanged (a
--    reassignment changes the VENDOR on a given scope, never the scope itself).
-- ===========================================================================

create or replace function app.reassign_vendor_assignment(
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
  v_rate app.vendor_rate_versions;
  v_existing app.vendor_assignment_invitations;
  v_eligibility record;
  v_assignment app.resource_assignments;
  v_leg app.shipment_legs;
  v_new app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reassign a vendor assignment' using errcode = 'check_violation';
  end if;

  select * into v_prior from app.vendor_assignment_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (Tier C batch-3 fix, preserved from the live body).
  if not app.has_active_tenant_membership(v_prior.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prior.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prior.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-15 (Tier C batch-3 fix, preserved from the live body).
  if p_new_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_new_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_new_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_prior.tenant_id or v_rate.vendor_master_id is distinct from p_new_vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to vendor % in tenant %', p_new_rate_version_id, p_new_vendor_master_id, v_prior.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- C-01/C-02 (Tier C batch-3 fix, preserved from the live body): checked BEFORE
  -- the version/status checks -- a genuine replay must short-circuit past state a
  -- successful prior call already advanced (v_prior is already 'superseded' by
  -- the time of a replay).
  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assignment_invitations where tenant_id = v_prior.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_prior.superseded_by_id is distinct from v_existing.id
         or v_existing.vendor_master_id is distinct from p_new_vendor_master_id
         or (p_new_contract_id is not null and v_existing.contract_id is distinct from p_new_contract_id)
         or v_existing.po_id is distinct from p_new_po_id
         or v_existing.rate_version_id is distinct from p_new_rate_version_id
         or v_existing.capacity_reservation_id is distinct from p_new_capacity_reservation_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment reassignment', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
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

  -- ISS-2026-062 (design note 2): same branch as app.confirm_vendor_assignment.
  -- The prior invitation's own shipment_leg_id carries forward unchanged onto
  -- the new row below -- a reassignment changes the vendor on a scope, never
  -- the scope itself.
  if v_prior.shipment_leg_id is null then
    v_assignment := app.reassign_resource(v_prior.shipment_order_id, 'vendor', p_new_vendor_master_id, p_reason, p_actor_auth_user_id, p_actor_label);
  else
    select * into v_leg from app.shipment_legs where id = v_prior.shipment_leg_id for update;
    if not found then
      raise exception 'shipment_leg_not_found: %', v_prior.shipment_leg_id using errcode = 'no_data_found';
    end if;
    update app.shipment_legs set carrier_master_id = p_new_vendor_master_id where id = v_prior.shipment_leg_id;
  end if;

  if p_new_capacity_reservation_id is not null then
    update app.vendor_capacity_reservations set status = 'consumed' where id = p_new_capacity_reservation_id and status = 'accepted';
  end if;

  update app.vendor_assignment_invitations set status = 'superseded' where id = p_invitation_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  begin
    insert into app.vendor_assignment_invitations (
      tenant_id, shipment_order_id, shipment_leg_id, vendor_master_id, contract_id, po_id, rate_version_id, capacity_reservation_id,
      eligibility_snapshot, status, assignment_id, idempotency_key, created_by
    )
    values (
      v_prior.tenant_id, v_prior.shipment_order_id, v_prior.shipment_leg_id, p_new_vendor_master_id, v_eligibility.resolved_contract_id, p_new_po_id, p_new_rate_version_id, p_new_capacity_reservation_id,
      v_eligibility.snapshot, 'assigned', v_assignment.id, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_assignment_invitations where tenant_id = v_prior.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_id is distinct from p_new_vendor_master_id
         or (p_new_contract_id is not null and v_existing.contract_id is distinct from p_new_contract_id)
         or v_existing.po_id is distinct from p_new_po_id
         or v_existing.rate_version_id is distinct from p_new_rate_version_id
         or v_existing.capacity_reservation_id is distinct from p_new_capacity_reservation_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assignment reassignment', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  update app.vendor_assignment_invitations set superseded_by_id = v_new.id where id = p_invitation_id;

  perform app.capture_audit_event(
    v_prior.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_vendor_assignment',
    'app.vendor_assignment_invitations', v_new.id, 'success', p_reason, null,
    jsonb_build_object('supersedes_invitation_id', p_invitation_id, 'assignment_id', v_assignment.id, 'shipment_leg_id', v_prior.shipment_leg_id)
  );

  return v_new;
end;
$$;

comment on function app.reassign_vendor_assignment is 'PRC-263, widened ISS-2026-062: OPS:Assign-gated, unchanged. shipment_leg_id carries forward from the prior invitation unchanged. A whole-shipment invitation calls app.reassign_resource exactly as before -- byte-identical. A leg-scoped invitation updates app.shipment_legs.carrier_master_id directly instead (design note 2).';

-- ===========================================================================
-- 5. app.list_vendor_assignment_invitations widened -- one new trailing
--    optional parameter, p_shipment_leg_id. DROP + CREATE (adds a parameter),
--    same reasoning as section 2.
-- ===========================================================================

drop function if exists app.list_vendor_assignment_invitations(uuid, uuid, uuid, text, uuid, integer);

create function app.list_vendor_assignment_invitations(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25,
  p_shipment_leg_id uuid default null
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
    -- ISS-2026-062 (design note 4): an EXACT leg match, never a fallback to
    -- whole-shipment rows -- "assignments on this leg" and "whole-shipment
    -- assignments" are two distinct, disclosed query scopes, never conflated.
    and (p_shipment_leg_id is null or shipment_leg_id = p_shipment_leg_id)
  order by created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_vendor_assignment_invitations is 'PRC-263, widened ISS-2026-062: one new trailing optional parameter, p_shipment_leg_id (default null = no leg filter, every pre-existing caller unaffected). When supplied, matches shipment_leg_id EXACTLY -- rows with shipment_leg_id is null (whole-shipment invitations) are never returned by a leg-filtered query, and a leg-scoped invitation is never returned by an unfiltered or shipment-only query filtered on a DIFFERENT leg. PRC:View-gated, unchanged.';

-- ===========================================================================
-- 6. Grants (design note 7).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.propose_vendor_assignment_invitation(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.confirm_vendor_assignment(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_vendor_assignment(uuid, integer, uuid, uuid, uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_vendor_assignment_invitations(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;
