-- ISS-2026-066 item 1 (docs/runtime/KNOWN_ISSUES.md): "No bulk/multi-employee
-- reorganization wizard." HRT-275's own migration disclosed this as a deliberate scope
-- trim, not a defect: every RPC in that migration (app.propose_employee_position_
-- assignment / app.decide_employee_position_assignment / app.cancel_employee_position_
-- assignment) operates one employee at a time. This migration is the "move a whole
-- department's employees to a new org unit/position in one transaction" tool the entry
-- names, built the SAME way ISS-2026-066 item 3's crosswalk-import adapter
-- (20260902040000) was: a thin batch wrapper that reuses app.propose_employee_position_
-- assignment's own validation verbatim, never a reimplementation of it.
--
-- ===========================================================================
-- Live schema/function re-verified before writing this file (per this checkpoint's own
-- instruction -- nothing below is assumed from an on-disk migration that may be stale)
-- ===========================================================================
--
-- `pg_get_functiondef` against the live hosted project confirmed app.propose_employee_
-- position_assignment is still the original 13-argument HRT-275 shape (no p_client_ip)
-- and app.employee_position_assignments carries the source_import_staging_row_id
-- lineage column ISS-2026-066 item 3 added -- both used unchanged below.
--
-- ===========================================================================
-- The one real design decision, and it is the SAME one item 3 already made: PROPOSE
-- only, never DECIDE.
-- ===========================================================================
--
-- HRT-275's own section 21 main flow is a deliberate two-step propose-then-decide
-- workflow: a pending_approval proposal, reviewed and approved/rejected as a separate,
-- later HRS:Approve act. A bulk reorganization is not exempt from that review just
-- because many employees move at once -- if anything, a batch of simultaneous position
-- changes is exactly the case human review exists for. So this RPC calls ONLY
-- app.propose_employee_position_assignment per item, never app.decide_employee_
-- position_assignment. Every bulk-created row lands in the SAME pending_approval queue
-- a single HR-entered proposal would, reviewed through the SAME existing
-- /hris/employees/[masterRecordId]/positions wizard -- no new approval UI is needed or
-- built. This also means the batch RPC only needs HRS:Edit (what propose itself already
-- demands of its caller), never HRS:Approve or an administrative gate.
--
-- ===========================================================================
-- Atomicity ("in one transaction", the entry's own words): free, not engineered.
-- ===========================================================================
--
-- Unlike a staged-import commit job (which tolerates per-row failure against untrusted
-- bulk file data, catching each row's exception so one bad row never sinks a thousand
-- good ones), a bulk reorganization wizard is a small, deliberate act by an HR admin
-- naming a specific set of employees by hand. All-or-nothing is the right contract: if
-- one employee's move fails validation, the operator needs to see and fix it, not
-- partially move a department while silently skipping the rest. This function does
-- nothing to engineer that -- it is the default. No exception anywhere in the loop
-- below is caught, so any item's failure propagates out of the function call and
-- Postgres rolls back every insert this invocation made, exactly as it would for any
-- other single, uncaught exception.
--
-- Per-item shape: {master_record_id, expected_version, position_id, grade_id?,
-- manager_employee_id?, assignment_type?} -- the "employee/position pairs" the entry
-- names. change_reason/reason_note/effective_start_date/effective_end_date are shared
-- across the whole batch (one reorganization event, one reason, one effective date) --
-- matching how the single-employee wizard's own form already groups these fields.

create function app.propose_bulk_employee_position_assignment(
  p_tenant_id uuid,
  p_items jsonb,
  p_change_reason text,
  p_reason_note text,
  p_effective_start_date date,
  p_effective_end_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_item jsonb;
  v_item_count integer;
  v_master_record_id uuid;
  v_expected_version integer;
  v_position_id uuid;
  v_grade_id uuid;
  v_manager_employee_id uuid;
  v_assignment_type text;
  v_seen uuid[] := array[]::uuid[];
  v_result app.employee_position_assignments;
  v_created_count integer := 0;
begin
  if p_tenant_id is null or not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: actor % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  -- Batch-wide authority gate up front (fails fast with ONE clear reason instead of
  -- failing on whichever item happens to come first) -- app.propose_employee_position_
  -- assignment re-checks the identical HRS:Edit permission per employee below anyway,
  -- so this adds no new authority surface, only an earlier, cheaper failure.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_change_reason not in ('hire', 'transfer', 'promotion', 'demotion', 'lateral_move', 'reorganization', 'secondary_assignment', 'correction') then
    raise exception 'invalid_change_reason: %', p_change_reason using errcode = 'check_violation';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid_items: p_items must be a JSON array of employee/position pairs' using errcode = 'invalid_parameter_value';
  end if;

  v_item_count := jsonb_array_length(p_items);
  if v_item_count = 0 then
    raise exception 'invalid_items: at least one employee/position pair is required' using errcode = 'invalid_parameter_value';
  end if;
  -- A safety bound, not a business rule -- disclosed here rather than left implicit.
  -- Large enough for a genuine department move, small enough that one wizard submission
  -- can never become an unbounded, un-reviewable transaction.
  if v_item_count > 200 then
    raise exception 'too_many_items: a single bulk reorganization batch is limited to 200 employees (got %)', v_item_count using errcode = 'invalid_parameter_value';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_master_record_id := nullif(v_item ->> 'master_record_id', '')::uuid;
    v_expected_version := nullif(v_item ->> 'expected_version', '')::integer;
    v_position_id := nullif(v_item ->> 'position_id', '')::uuid;
    v_grade_id := nullif(v_item ->> 'grade_id', '')::uuid;
    v_manager_employee_id := nullif(v_item ->> 'manager_employee_id', '')::uuid;
    v_assignment_type := coalesce(nullif(v_item ->> 'assignment_type', ''), 'primary');

    if v_master_record_id is null or v_expected_version is null or v_position_id is null then
      raise exception 'invalid_item: master_record_id, expected_version, and position_id are all required for every item (got %)', v_item::text
        using errcode = 'invalid_parameter_value';
    end if;

    if v_master_record_id = any(v_seen) then
      raise exception 'duplicate_employee: employee % appears more than once in this batch', v_master_record_id using errcode = 'invalid_parameter_value';
    end if;
    v_seen := v_seen || v_master_record_id;

    -- Tenant-boundary defense in depth: app.propose_employee_position_assignment
    -- derives tenant from the employee row itself, not from an argument -- so a caller
    -- with active membership in more than one tenant could otherwise smuggle another
    -- tenant's employee into a batch a UI scoped to ONE tenant. Failing not-found here
    -- (never confirming the employee exists elsewhere) matches this repository's own
    -- established cross-tenant-disclosure posture.
    if not exists (select 1 from app.employees e where e.master_record_id = v_master_record_id and e.tenant_id = p_tenant_id) then
      raise exception 'employee_not_found: % is not a valid employee for tenant %', v_master_record_id, p_tenant_id using errcode = 'no_data_found';
    end if;

    v_result := app.propose_employee_position_assignment(
      v_master_record_id, v_expected_version, v_position_id, v_grade_id, v_manager_employee_id,
      v_assignment_type, null, p_effective_start_date, p_effective_end_date,
      p_change_reason, p_reason_note, p_actor_auth_user_id, p_actor_label
    );
    v_created_count := v_created_count + 1;
    return next v_result;
  end loop;

  -- A batch-level summary event, additional to (never a replacement for) the per-row
  -- audit event app.propose_employee_position_assignment already captures for each
  -- created proposal -- resource_id is null because this event describes the WHOLE
  -- batch, not any one row.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_bulk_employee_position_assignment',
    'app.employee_position_assignments', null, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'change_reason', p_change_reason, 'effective_start_date', p_effective_start_date)
  );

  return;
end;
$function$;

comment on function app.propose_bulk_employee_position_assignment is
  'ISS-2026-066 item 1: the bulk/multi-employee reorganization RPC the entry names. p_items is a JSON array of {master_record_id, expected_version, position_id, grade_id?, manager_employee_id?, assignment_type?} pairs -- change_reason/reason_note/effective_start_date/effective_end_date are shared across the whole batch. Calls ONLY app.propose_employee_position_assignment per item (never app.decide_employee_position_assignment) -- every bulk-created row lands as a real pending_approval proposal in the SAME queue a single HR-entered proposal would, reviewed through the existing /hris/employees/[masterRecordId]/positions wizard. Requires HRS:Edit (what propose itself already demands of its caller), never HRS:Approve or an administrative gate. Atomic: no exception in the per-item loop is caught, so any one item''s failure rolls back every insert this call made -- "one transaction", exactly as the entry''s own filing text names it. Limited to 200 items per batch.';

-- New functions in schema app get PostgreSQL's vanilla default (EXECUTE granted to
-- PUBLIC on creation) since no ALTER DEFAULT PRIVILEGES override exists for this
-- schema -- the earlier blanket `revoke execute on all functions in schema app from
-- public` (20260902040000) only reached functions that already existed at the time it
-- ran. Revoked explicitly here so this one is never an exception.
revoke execute on function app.propose_bulk_employee_position_assignment(uuid, jsonb, text, text, date, date, uuid, text) from public;
grant execute on function app.propose_bulk_employee_position_assignment(uuid, jsonb, text, text, date, date, uuid, text) to authenticated, service_role;

create function public.propose_bulk_employee_position_assignment(
  p_tenant_id uuid,
  p_items jsonb,
  p_change_reason text,
  p_reason_note text,
  p_effective_start_date date,
  p_effective_end_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.employee_position_assignments
language sql
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $wrap$
  select * from app.propose_bulk_employee_position_assignment(p_tenant_id, p_items, p_change_reason, p_reason_note, p_effective_start_date, p_effective_end_date, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.propose_bulk_employee_position_assignment is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through, never a reimplementation -- app.propose_bulk_employee_position_assignment above is already security definer, so this wrapper matches it (the wrapper-parity gate requires identical security mode on both sides).';

revoke execute on function public.propose_bulk_employee_position_assignment(uuid, jsonb, text, text, date, date, uuid, text) from public;
grant execute on function public.propose_bulk_employee_position_assignment(uuid, jsonb, text, text, date, date, uuid, text) to authenticated, service_role;
