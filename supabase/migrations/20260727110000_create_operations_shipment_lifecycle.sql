-- Operations capability OPS-170 (Shipment Lifecycle, CG-S8-OPS-004)
-- A canonical Shipment Order lifecycle (draft -> confirmed -> planned -> assigned ->
-- dispatched -> in_transit -> delivered -> epod -> closed, plus held/cancelled/reopen
-- alternative states) whose current-state projection (`app.shipment_orders.status`,
-- broadened by this migration's own additive constraint replacement) is driven
-- exclusively by one validated, idempotent, optimistic-concurrency-checked transition
-- function -- never a direct UPDATE.
--
-- Engine-reuse research (disclosed, not assumed): Platform Core's own generic Workflow
-- Engine (`app.start_workflow_instance`/`app.transition_workflow_instance`, PLT-122,
-- `20260717140000_create_workflow_engine.sql`) explicitly forbids exactly this --
-- its own §12 states "domain workflows beyond [its own isolated] example... broad
-- module adoption" are out of scope, and it remains disclosed as having zero real
-- consumers to this day. The Status Engine (PLT-124) is a label/presentation registry
-- only -- no transition matrix, no history, no concurrency, no entity binding at all.
-- Every real status transition already shipped in this repository (`COM-153`'s own
-- `approval_status`, `OPS-168`'s `job_orders.status`, `OPS-169`'s own
-- `shipment_orders.status`) is independently hand-rolled per capability -- this
-- migration follows that same established, consistent precedent rather than binding
-- to an engine whose own header disclaims this exact use.
--
-- `app.shipment_orders`' own `shipment_orders_status_check` constraint (added at
-- `OPS-169`) only ever covered `draft`/`confirmed`/`cancelled` -- broadened here via
-- `DROP CONSTRAINT` + `ADD CONSTRAINT` in this new migration (an additive change to an
-- existing table from a later migration, never an edit to `OPS-169`'s own file, per
-- the standing immutable-migrations convention). `app.confirm_shipment_order`/
-- `app.cancel_shipment_order` (`OPS-169`) remain unchanged and still valid -- they
-- cover exactly the `draft->confirmed`/`*->cancelled` edges of this migration's own
-- fuller matrix; this migration does not remove or redirect them.
--
-- "Held" is a suspension state reachable from any active non-terminal status; the
-- status it suspended from is preserved in `held_from_status` and is the only legal
-- resume target, so a held shipment can never "resume" into an arbitrary different
-- state. "Reopen" (`closed` -> `delivered`/`epod`) is the one correction path into an
-- already-closed shipment, restricted to Supreme Admin (`app.is_supreme_admin`, the
-- RPD-022 disclosed absolute-CRUD exception every other capability's own hardening
-- checkpoint already relies on) -- normal users cannot rewrite history (Prompt 170
-- §24), only append new evidence going forward.
--
-- `evidence_ref` (a bounded, disclosed placeholder text reference, mirroring
-- `app.job_orders.downstream_reference`'s own "structurally ready, not yet populated
-- by a real consumer" disclosure) is required entering `delivered`/`epod`/`closed`
-- (Prompt 170 §25's own "configured evidence" requirement) -- no real ePOD/document
-- capability exists yet (`OPS-176`/`OPS-177`, out of this session's authorized range),
-- so this is a bounded text reference only, never a file/attachment mechanism.
--
-- Milestone/exception/assignment/billing gates (Prompt 170 §20 task 3) are explicitly
-- NOT implemented by this migration -- `OPS-172`/`173`/`174` and Finance's own billing
-- readiness capability do not exist yet; this transition function is the one stable
-- entry point those future capabilities will call into, not a placeholder they must
-- rebuild.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

alter table app.shipment_orders drop constraint shipment_orders_status_check;
alter table app.shipment_orders add constraint shipment_orders_status_check check (
  status in ('draft', 'confirmed', 'planned', 'assigned', 'dispatched', 'in_transit', 'delivered', 'epod', 'closed', 'held', 'cancelled')
);

alter table app.shipment_orders add column held_from_status text;
alter table app.shipment_orders add constraint shipment_orders_held_from_status_check check (
  held_from_status is null or held_from_status in ('confirmed', 'planned', 'assigned', 'dispatched', 'in_transit')
);

comment on column app.shipment_orders.held_from_status is
  'OPS-170: set only while status = ''held'' -- the one legal resume target app.transition_shipment_order enforces, so a held shipment can never resume into an arbitrary different state. Null whenever status <> ''held''.';

-- Append-only canonical transition history (Prompt 170 §13/§18) -- one row per real
-- transition, never edited. Idempotent on (tenant_id, shipment_order_id,
-- idempotency_key), the same "unique_violation caught, current row re-selected"
-- pattern every prior Operations mutation (OPS-168/169) already established.
create table app.shipment_status_transitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  from_status text not null,
  to_status text not null,
  reason text,
  evidence_ref text,
  idempotency_key text not null,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now(),
  constraint shipment_status_transitions_tenant_shipment_idempotency_unique unique (tenant_id, shipment_order_id, idempotency_key)
);

comment on table app.shipment_status_transitions is
  'OPS-170: append-only canonical transition evidence -- prior/new state, actor, reason, evidence reference and idempotency key for every real Shipment Order state change. app.shipment_orders.status/held_from_status is the current-state projection this history exists to explain, never the other way around.';

create index shipment_status_transitions_shipment_idx on app.shipment_status_transitions (shipment_order_id, occurred_at);
create index shipment_status_transitions_tenant_idx on app.shipment_status_transitions (tenant_id);

-- The one atomic, idempotent, validated transition service (Prompt 170 §14/§20 task
-- 2) -- OPS:Edit-gated, optimistic-concurrency-checked, record-scope-checked. Every
-- legal edge of the canonical matrix lives here, hardcoded and named, never a
-- config-driven or client-supplied transition rule (Prompt 170 §24's own "canonical
-- state is stable; tenant labels do not alter lifecycle meaning").
create function app.transition_shipment_order(
  p_shipment_order_id uuid,
  p_to_status text,
  p_expected_version integer,
  p_reason text,
  p_evidence_ref text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_transition app.shipment_status_transitions;
  v_from_status text;
  v_next_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_transition from app.shipment_status_transitions
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_shipment;
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_shipment.status;

  -- The canonical matrix. 'held'/'cancelled' branch off most active states; 'held'
  -- resumes only into its own recorded held_from_status; 'closed' may only reopen
  -- into 'delivered'/'epod' (Supreme-only, checked below), never further back.
  if v_from_status = 'held' then
    if p_to_status <> v_shipment.held_from_status and p_to_status <> 'cancelled' then
      raise exception 'invalid_transition: a held shipment order % may only resume into % or cancel', p_shipment_order_id, v_shipment.held_from_status
        using errcode = 'check_violation';
    end if;
  elsif v_from_status = 'closed' then
    if p_to_status not in ('delivered', 'epod') then
      raise exception 'invalid_transition: shipment order % is closed and may only reopen into delivered or epod', p_shipment_order_id
        using errcode = 'check_violation';
    end if;
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: reopening a closed shipment order requires Supreme Admin authority (RPD-022)'
        using errcode = 'insufficient_privilege';
    end if;
  elsif v_from_status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled, a terminal state', p_shipment_order_id using errcode = 'check_violation';
  elsif v_from_status = 'draft' and p_to_status in ('confirmed', 'cancelled') then
    null;
  elsif v_from_status in ('confirmed', 'planned', 'assigned', 'dispatched', 'in_transit') and p_to_status in ('held', 'cancelled') then
    null;
  elsif v_from_status = 'confirmed' and p_to_status = 'planned' then
    null;
  elsif v_from_status = 'planned' and p_to_status = 'assigned' then
    null;
  elsif v_from_status = 'assigned' and p_to_status = 'dispatched' then
    null;
  elsif v_from_status = 'dispatched' and p_to_status = 'in_transit' then
    null;
  elsif v_from_status = 'in_transit' and p_to_status = 'delivered' then
    null;
  elsif v_from_status = 'delivered' and p_to_status in ('epod', 'cancelled') then
    null;
  elsif v_from_status = 'epod' and p_to_status = 'closed' then
    null;
  else
    raise exception 'invalid_transition: % -> % is not a legal Shipment Order transition', v_from_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if p_to_status in ('held', 'cancelled') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  if p_to_status in ('delivered', 'epod', 'closed') and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: a non-empty evidence reference is required to enter %', p_to_status using errcode = 'check_violation';
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

  v_next_status := p_to_status;

  begin
    insert into app.shipment_status_transitions (
      tenant_id, shipment_order_id, from_status, to_status, reason, evidence_ref, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, v_from_status, v_next_status, p_reason, p_evidence_ref, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
      return v_shipment;
  end;

  update app.shipment_orders
  set status = v_next_status,
      held_from_status = case when v_next_status = 'held' then v_from_status else null end
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null,
    jsonb_build_object('status', v_from_status),
    jsonb_build_object('status', v_next_status, 'reason', p_reason, 'evidence_ref', p_evidence_ref)
  );

  return v_shipment;
end;
$$;

comment on function app.transition_shipment_order is
  'OPS-170: the one atomic, idempotent, validated entry point for every Shipment Order state change -- never a direct UPDATE. Idempotent on (tenant_id, shipment_order_id, idempotency_key); optimistic-concurrency-checked (p_expected_version); reason mandatory entering held/cancelled; evidence_ref mandatory entering delivered/epod/closed; reopening a closed shipment (-> delivered/epod) requires Supreme Admin (RPD-022).';

-- Authority-gated read of the full transition history for one Shipment Order.
create function app.get_shipment_status_history(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns setof app.shipment_status_transitions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.shipment_status_transitions
    where shipment_order_id = p_shipment_order_id
    order by occurred_at asc;
end;
$$;

comment on function app.get_shipment_status_history is
  'OPS-170: the same record-scope check app.transition_shipment_order itself uses, ordered oldest-first, mirroring app.get_workflow_instance_history''s own (PLT-122) established shape.';

alter table app.shipment_status_transitions enable row level security;

create policy shipment_status_transitions_select_scoped on app.shipment_status_transitions
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_status_transitions.shipment_order_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.shipment_status_transitions to authenticated, service_role;
grant insert, update, delete on app.shipment_status_transitions to service_role;

grant execute on function app.transition_shipment_order(uuid, text, integer, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_status_history(uuid, uuid) to authenticated, service_role;
