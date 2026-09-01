-- Self-found regression, caught live by `pnpm run db:test` immediately after
-- 20260902040000_create_position_crosswalk_import_adapter.sql applied -- not assumed, not
-- theoretical. That migration's STEP 1 does `alter table app.employee_position_assignments add
-- column source_import_staging_row_id uuid`, widening the table to 24 columns. Two read RPCs
-- declare `returns setof app.employee_position_assignments` (which auto-tracks the table's own
-- row type, now 24 columns) but their bodies project an EXPLICIT, hand-written 23-column list
-- (the masking fix from 20260731210000_harden_ticketing_escalation_linked_records_hris_batch_
-- 291_293_review_fixes.sql, which nulls reason_note/decided_reason for a caller lacking HRS view-
-- personal-data). The mismatch is a genuine `structure of query does not match function result
-- type` error, live-reproduced:
--
--   ERROR: structure of query does not match function result type
--   DETAIL: Number of returned columns (23) does not match expected column count (24).
--
-- affecting BOTH app.get_employee_current_assignment and
-- app.get_employee_position_assignment_history (live-confirmed via pg_get_functiondef against the
-- hosted project before writing this file -- app.get_my_employee_position_assignment_history, the
-- THIRD `setof app.employee_position_assignments` reader, is unaffected: its own body is a plain
-- `select *`, which auto-widens with the table and never hand-lists columns).
--
-- Fix: CREATE OR REPLACE both functions, live pg_get_functiondef output as the base, with
-- `a.source_import_staging_row_id` appended to the explicit column list. Never masked -- it is
-- import lineage metadata (a staging-row uuid), not personal data, so it carries no `case when
-- v_unmasked` guard, unlike reason_note/decided_reason immediately beside it. Every other line is
-- byte-identical to the live definition -- no other behavior changes.

create or replace function app.get_employee_current_assignment(p_master_record_id uuid, p_actor_auth_user_id uuid, p_as_of date default current_date)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_unmasked := app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    a.id, a.tenant_id, a.master_record_id, a.position_id, a.grade_id, a.manager_employee_id, a.assignment_type, a.allocation_pct,
    a.effective_start_date, a.effective_end_date, a.validity_range, a.status, a.change_reason,
    case when v_unmasked then a.reason_note else null end,
    a.previous_assignment_id, a.source_config_version_id, a.decided_by, a.decided_at,
    case when v_unmasked then a.decided_reason else null end,
    a.record_version, a.created_by, a.created_at, a.updated_at, a.source_import_staging_row_id
  from app.employee_position_assignments a
  where a.master_record_id = p_master_record_id and a.status = 'active' and a.validity_range @> p_as_of
  order by a.assignment_type;
end;
$function$;

comment on function app.get_employee_current_assignment is
  'HRT-275: the genuinely point-in-time-correct read (section 20 "test ... historical queries") -- reads directly from app.employee_position_assignments'' own validity_range, never from app.employees'' convenience cache. Masked by the batch 291-293 Tier C fix (20260731210000): reason_note/decided_reason nulled unless the caller holds HRS:View personal data. Widened (20260902041000) to project source_import_staging_row_id (ISS-2026-066 item 3''s new lineage column) -- unmasked, since it is not personal data.';

create or replace function app.get_employee_position_assignment_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 2 HIGH): reason_note/
  -- decided_reason bypassed 20260731200000's own raw-table column
  -- restriction via this function's unconditional select *.
  v_unmasked := app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    a.id, a.tenant_id, a.master_record_id, a.position_id, a.grade_id, a.manager_employee_id, a.assignment_type, a.allocation_pct,
    a.effective_start_date, a.effective_end_date, a.validity_range, a.status, a.change_reason,
    case when v_unmasked then a.reason_note else null end,
    a.previous_assignment_id, a.source_config_version_id, a.decided_by, a.decided_at,
    case when v_unmasked then a.decided_reason else null end,
    a.record_version, a.created_by, a.created_at, a.updated_at, a.source_import_staging_row_id
  from app.employee_position_assignments a
  where a.master_record_id = p_master_record_id
  order by a.effective_start_date desc, a.created_at desc;
end;
$function$;

comment on function app.get_employee_position_assignment_history is 'HRT-275, masked by the batch 291-293 Tier C fix (20260731210000): reason_note/decided_reason are nulled unless the caller holds HRS:View personal data. Widened (20260902041000) to project source_import_staging_row_id (ISS-2026-066 item 3''s new lineage column) -- unmasked, since it is not personal data.';

-- No grant/wrapper changes: both functions' signatures, security context and grant sets are
-- byte-identical to before this migration -- only the internal projected column list widened to
-- track the table's own new column, exactly as `select *`-bodied siblings already did for free.
