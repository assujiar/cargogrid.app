-- Operations capability OPS-175 (Basic Dispatch, CG-S8-OPS-009)
-- A permission-safe, deterministic readiness queue plus a validated dispatch command
-- for assigned Shipment Orders -- "list/queue dispatch, not a dispatch board, not
-- route/load/capacity optimization or telematics" (Prompt 175 §24).
--
-- Dispatch is a thin, readiness-gated wrapper over the already-shipped canonical
-- lifecycle, never a second parallel state machine or a direct status edit (§24: "not
-- direct status edit"). `assigned -> dispatched` has been a legal edge of `OPS-170`'s
-- own `app.transition_shipment_order` matrix since that capability shipped; this
-- migration does not duplicate that matrix -- `app.dispatch_shipment_order` calls
-- `app.transition_shipment_order` internally for the actual state change, adding
-- exactly one new thing: a real, re-checked-at-commit-time readiness gate in front of
-- it (§25: "recheck authorization/readiness at commit time"). Hold/release/reassign
-- for an already-planned-or-later shipment already have their own real, validated
-- commands (`app.transition_shipment_order` for hold/release, `OPS-172`'s own
-- `app.reassign_resource` for resource reassignment) -- neither is rebuilt or
-- duplicated here; the existing Shipment Order detail UI already exposes both.
--
-- Readiness checklist, disclosed as a real, bounded "basic" MVP set (§20 task 1: "Phase
-- 5 boundary"): (1) the shipment is currently `assigned` (the one legal pre-dispatch
-- state); (2) at least one current, active resource assignment exists (`OPS-172`'s own
-- `app.resource_assignments`) -- a per-mode required-role matrix (e.g. land requires
-- vehicle+driver, sea requires a vendor) is explicit Phase 5 (Advanced TMS) scope, not
-- built here; (3) no blocking operational exception (`OPS-174`'s own
-- `app.operational_exceptions` in `open`/`acknowledged`/`reopened` status) is linked to
-- the shipment; (4) `planned_pickup_at` is set (the basic "schedule" requirement).
-- Required-document readiness (§13/§20 task 1's "doc... controls") is explicitly
-- `NOT_RUN` -- no Document Requirement capability (`OPS-176`, out of this session's own
-- "lanjut sd prompt 175" authorized range) exists anywhere in this repository yet to
-- check against; this is the same "mechanism proven, live wiring deferred once the
-- real dependency ships" posture already disclosed at `PLT-107`/`PLT-120`.
--
-- Bulk dispatch (§20 task 3/§24: "per-record atomic/idempotent... explicit partial
-- result") is bounded to 50 records per call and every record is independently
-- permission/record-scope/readiness-rechecked and independently idempotent -- one
-- record's failure never aborts another's, and the caller always receives a full,
-- explicit per-record result row, never a silent partial success.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

-- Pure, side-effect-free readiness computation -- shared by app.get_dispatch_readiness,
-- app.dispatch_shipment_order's own commit-time recheck, and the app.dispatch_ready_queue
-- view (via a lateral join), so the checklist is defined exactly once.
create function app.evaluate_dispatch_readiness(p_shipment_order_id uuid)
returns table (is_ready boolean, blockers jsonb)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.status <> 'assigned' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'wrong_status', 'detail', v_shipment.status));
  end if;

  if not exists (
    select 1 from app.resource_assignments ra
    where ra.shipment_order_id = p_shipment_order_id and ra.is_current and ra.status = 'active'
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_active_assignment', 'detail', null));
  end if;

  if exists (
    select 1 from app.operational_exceptions oe
    where oe.shipment_order_id = p_shipment_order_id and oe.status in ('open', 'acknowledged', 'reopened')
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'blocking_exception', 'detail', null));
  end if;

  if v_shipment.planned_pickup_at is null then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'missing_schedule', 'detail', null));
  end if;

  return query select (jsonb_array_length(v_blockers) = 0), v_blockers;
end;
$$;

comment on function app.evaluate_dispatch_readiness is
  'OPS-175: the one bounded, basic-MVP readiness checklist (status=assigned, an active resource assignment, no blocking exception, a planned pickup time) -- required-document readiness is explicitly NOT_RUN (no Document Requirement capability exists yet); a per-mode required-role assignment matrix is explicit Phase 5 scope. Shared by every other function/view in this migration, defined exactly once.';

create function app.get_dispatch_readiness(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (is_ready boolean, blockers jsonb)
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

  return query select * from app.evaluate_dispatch_readiness(p_shipment_order_id);
end;
$$;

comment on function app.get_dispatch_readiness is
  'OPS-175: authority-gated (OPS:View + record scope) single-shipment readiness check, for the dispatch panel''s own "why not ready" display.';

create table app.dispatch_commands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  command text not null default 'dispatch',
  readiness_snapshot jsonb not null,
  idempotency_key text not null,
  actor_auth_user_id uuid,
  actor_label text,
  dispatched_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint dispatch_commands_command_check check (command in ('dispatch')),
  constraint dispatch_commands_tenant_shipment_idempotency_unique unique (tenant_id, shipment_order_id, idempotency_key)
);

comment on table app.dispatch_commands is
  'OPS-175: append-only dispatch command history, distinct from OPS-170''s own generic app.shipment_status_transitions -- this table exists specifically to preserve the real readiness_snapshot (the exact app.evaluate_dispatch_readiness result) as of the moment dispatch was committed (Prompt 175 §13/§18), evidence the generic transition-history table does not carry. The command column is deliberately real (not omitted) even though only ''dispatch'' is possible today -- hold/release/reassign remain OPS-170/OPS-172''s own existing commands, not duplicated here.';

create index dispatch_commands_tenant_shipment_idx on app.dispatch_commands (tenant_id, shipment_order_id);

-- The one validated dispatch command (Prompt 175 §24: "a validated lifecycle command,
-- not direct status edit"). Idempotent on (tenant_id, shipment_order_id,
-- idempotency_key) -- checked FIRST, before any readiness recheck, so a genuine retry
-- of an already-succeeded dispatch always returns the prior result rather than
-- incorrectly re-evaluating readiness against a shipment that has since moved past
-- 'assigned'.
create function app.dispatch_shipment_order(
  p_shipment_order_id uuid,
  p_expected_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.dispatch_commands
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.dispatch_commands;
  v_readiness record;
  v_command app.dispatch_commands;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.dispatch_commands
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
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

  select * into v_readiness from app.evaluate_dispatch_readiness(p_shipment_order_id);
  if not v_readiness.is_ready then
    -- Deliberately not captured via app.capture_audit_event here: a raise exception
    -- unwinds to the nearest enclosing exception block (this function's own caller,
    -- or app.bulk_dispatch_shipment_orders' per-record catch), which rolls back to an
    -- implicit savepoint and would silently discard any insert made before the raise.
    -- The blockers are carried in the exception message itself instead.
    raise exception 'dispatch_not_ready: shipment order % is not ready to dispatch (%)', p_shipment_order_id, v_readiness.blockers
      using errcode = 'check_violation';
  end if;

  perform app.transition_shipment_order(p_shipment_order_id, 'dispatched', p_expected_version, null, null, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  begin
    insert into app.dispatch_commands (tenant_id, shipment_order_id, readiness_snapshot, idempotency_key, actor_auth_user_id, actor_label)
    values (v_shipment.tenant_id, p_shipment_order_id, to_jsonb(v_readiness), p_idempotency_key, p_actor_auth_user_id, p_actor_label)
    returning * into v_command;
  exception
    when unique_violation then
      select * into v_command from app.dispatch_commands
      where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_command;
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'dispatch_shipment_order',
    'app.dispatch_commands', v_command.id, 'success', null, null, jsonb_build_object('shipment_order_id', p_shipment_order_id)
  );

  return v_command;
end;
$$;

comment on function app.dispatch_shipment_order is
  'OPS-175: the one validated dispatch command -- idempotent-check first (a genuine retry short-circuits before any readiness recheck), then OPS:Edit + record-scope, then a real commit-time readiness recheck (dispatch_not_ready if blocked, with the exact blockers embedded in the raised exception message -- not a captured audit row, since any caller-side exception handler rolls that insert back with the raise), then the real app.transition_shipment_order(assigned -> dispatched) call, then this migration''s own readiness-snapshot history row.';

-- Bounded (50), per-record atomic/idempotent bulk dispatch (Prompt 175 §20 task 3/§24).
-- Every record is independently permission/record-scope/readiness-rechecked inside
-- app.dispatch_shipment_order itself -- one record's failure never aborts another's,
-- and the caller always receives a full, explicit per-record result row.
create function app.bulk_dispatch_shipment_orders(
  p_shipment_order_ids uuid[],
  p_idempotency_key_prefix text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (shipment_order_id uuid, success boolean, error_code text, error_message text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_id uuid;
  v_shipment app.shipment_orders;
  v_per_record_key text;
begin
  if p_shipment_order_ids is null or array_length(p_shipment_order_ids, 1) = 0 then
    raise exception 'bulk_empty: at least one shipment order id is required' using errcode = 'check_violation';
  end if;
  if array_length(p_shipment_order_ids, 1) > 50 then
    raise exception 'bulk_too_large: at most 50 shipment orders may be dispatched in one bulk call, got %', array_length(p_shipment_order_ids, 1)
      using errcode = 'check_violation';
  end if;
  if p_idempotency_key_prefix is null or length(trim(p_idempotency_key_prefix)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key prefix is required' using errcode = 'check_violation';
  end if;

  foreach v_id in array p_shipment_order_ids loop
    begin
      select * into v_shipment from app.shipment_orders where id = v_id;
      if not found then
        shipment_order_id := v_id;
        success := false;
        error_code := 'shipment_order_not_found';
        error_message := format('shipment_order_not_found: %s', v_id);
        return next;
        continue;
      end if;

      v_per_record_key := p_idempotency_key_prefix || ':' || v_id::text;
      perform app.dispatch_shipment_order(v_id, v_shipment.record_version, v_per_record_key, p_actor_auth_user_id, p_actor_label);

      shipment_order_id := v_id;
      success := true;
      error_code := null;
      error_message := null;
      return next;
    exception
      when others then
        shipment_order_id := v_id;
        success := false;
        error_code := split_part(sqlerrm, ':', 1);
        error_message := sqlerrm;
        return next;
    end;
  end loop;

  return;
end;
$$;

comment on function app.bulk_dispatch_shipment_orders is
  'OPS-175: bounded (<=50) bulk dispatch -- each id is independently re-fetched, re-versioned, and dispatched through the exact same app.dispatch_shipment_order path (no shortcut, no batch-level permission bypass); one record''s exception is caught and reported as its own row, never aborting the remaining records in the batch. Per-record idempotency key is deterministically derived from the caller''s own prefix plus the shipment order id.';

alter table app.dispatch_commands enable row level security;

create policy dispatch_commands_select_scoped on app.dispatch_commands
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = dispatch_commands.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

-- The basic ready queue (Prompt 175 §15/§20 task 2) -- status='assigned' only,
-- RLS-scoped, with is_ready/blockers computed inline via the one shared readiness
-- function so the queue and the single-shipment check can never disagree.
create view app.dispatch_ready_queue
as
select so.*, r.is_ready, r.blockers
from app.shipment_orders so
cross join lateral app.evaluate_dispatch_readiness(so.id) as r
where so.status = 'assigned'
  and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null);

comment on view app.dispatch_ready_queue is
  'OPS-175: the basic ready queue -- every assigned Shipment Order the caller can access, with is_ready/blockers computed by the same app.evaluate_dispatch_readiness() app.dispatch_shipment_order itself rechecks at commit time. List/queue only -- no dispatch board, no route/load/capacity optimization (Prompt 175 §24).';

revoke execute on all functions in schema app from public;

grant select on app.dispatch_commands to authenticated, service_role;
grant insert, update, delete on app.dispatch_commands to service_role;
grant select on app.dispatch_ready_queue to authenticated, service_role;

grant execute on function app.evaluate_dispatch_readiness(uuid) to authenticated, service_role;
grant execute on function app.get_dispatch_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.dispatch_shipment_order(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.bulk_dispatch_shipment_orders(uuid[], text, uuid, text) to authenticated, service_role;
