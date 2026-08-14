-- HRT-293 (Sensitive Personal and Payroll Data Controls, CG-S12-HRT-021) --
-- Employee Master (HRT-274) fix pass. Additive only -- zero lines of any
-- prior migration (<= 20260731170000) touched, per this repository's own
-- "never edit an already-applied migration" discipline. Every function this
-- migration `create or replace`s was read at its CURRENT live body (via
-- `pg_get_functiondef` against a fully-migrated database, not re-derived
-- from the file that originally created it) before being amended -- the
-- exact verification discipline `PRC-269` §2 already established for this
-- class of sweep.
--
-- Two findings from the Phase 7 audit (CG-S12-HRT-021, "Sensitive Personal
-- and Payroll Data Controls"), both CRITICAL, both fixed here:
--
-- Finding A -- app.employees' five HR-narrative reason columns
-- (revision_reason/suspend_reason/terminate_reason/archive_reason/
-- leave_reason) bypass the personal-data masking model entirely:
--   1. app.get_employee_profile returned all five UNCONDITIONALLY, never
--      wrapped in the `case when v_unmasked then ... else null end` guard
--      that already correctly protects national_id_number/personal_email/
--      date_of_birth/etc two lines above -- any caller holding plain
--      HRS:View (not HRS:View personal data) got them.
--   2. The column-restricted `grant select (...) on app.employees to
--      authenticated` (built specifically, per its own comment, to close a
--      PRIOR raw-SELECT PII leak the exact same way PLT-114 already
--      established for app.users) itself INCLUDED these five columns in
--      the "safe" list -- a real, live raw-SELECT bypass for any active
--      tenant member, zero HRS permission required at all (the
--      `employees_select_scoped` RLS policy admits any active tenant
--      member; RLS filters ROWS, never COLUMNS, so the column-level GRANT
--      is the only thing that can close this).
--   3. app.employee_lifecycle_events (the table the employee-detail UI's
--      History tab reads, via app.get_employee_lifecycle_history) carried a
--      FULL, unrestricted `grant select ... to authenticated` with the same
--      any-tenant-member RLS policy, and its own `reason` column carries the
--      identical raw narrative at every lifecycle transition.
--      app.get_employee_lifecycle_history was gated on plain HRS:View only
--      and did `select *`, returning that raw reason to any HRS:View
--      holder.
--
-- Impact: any employee at the company (via the raw-SELECT column grant) and
-- separately any plain HRS:View holder (via both read RPCs) could read why
-- any named colleague was suspended, terminated, put on leave, or archived
-- -- directly violating "manager/administrative hierarchy does not grant
-- unrestricted personal fields" and "UI masking alone is never sufficient"
-- at the database/service boundary.
--
-- Fix, mirroring the ALREADY-established pattern in this exact migration's
-- own header comment (the prior PII fix) and PLT-114/app.users_directory
-- before it: (1) `revoke select (<5 cols>) on app.employees from
-- authenticated` -- a database guarantee, not an RPC-side convention;
-- (2) the same revoke-and-column-restrict treatment for
-- app.employee_lifecycle_events (RLS itself stays broad -- any active
-- tenant member legitimately sees the STRUCTURAL transition timeline,
-- from_status/to_status/metadata/occurred_at, exactly like an org chart --
-- only the free-text `reason` column needs restricting, matching this
-- migration's own Finding B reasoning below); (3) `get_employee_profile`'s
-- five reason columns now wrapped in the same `v_unmasked` guard as every
-- other classified pii column; (4) `get_employee_lifecycle_history`'s own
-- authority gate is UNCHANGED (plain HRS:View still required to call it at
-- all -- this fix does not widen who may call it), but its `reason` column
-- is now masked to null unless the caller additionally holds HRS:View
-- personal data, via a row-constructor cast that preserves the function's
-- exact pre-existing `returns setof app.employee_lifecycle_events`
-- signature (a body-only `create or replace`, no DROP/re-GRANT dance
-- needed -- unlike PRC-269's own append-a-parameter case, the return type
-- here is unchanged).
--
-- Finding B (also CRITICAL, part of the same audit's C-24 finding, HR
-- Employee Master's own 9-site instance) -- every one of the 9
-- capture_audit_event calls in this capability passed the caller's raw
-- `p_reason`/`p_decided_reason` positional argument directly as the
-- app.audit_logs.reason column's own value. app.redact_audit_payload()
-- (PLT-116) only ever redacts the jsonb before_value/after_value payloads
-- (already correctly handled here via app.employee_audit_projection and
-- hand-built non-pii jsonb_build_object literals) -- it has never redacted
-- the separate scalar `reason` TEXT column at all, for any caller,
-- anywhere in this repository. app.query_audit_logs/app.export_audit_logs
-- are readable by ANY plain tenant_admin (app.is_support_grant_authority:
-- Supreme Admin OR tenant_admin, zero domain permission required) -- so a
-- tenant_admin with no HRS:View personal data grant of any kind could read
-- every employee's real suspend/terminate/leave/archive narrative, and
-- every self-service personal-contact-change reason, through the generic
-- audit-log query/export path alone. The exact shape
-- docs/standards/FINANCE_FIELD_POLICY_MATRIX.md §3 already treated as a
-- critical/high gap and fixed for Finance's own `tenant_admin`-via-
-- audit-log leak.
--
-- Fix: every one of the 9 calls below now passes `null` for the audit
-- reason argument instead of the raw text. This is not a loss of real
-- record-keeping -- the SAME reason value is, in every one of these 9
-- cases (plus a 10th, self-found site below: app._transition_employee_
-- leave_status, the shared engine app.start_employee_leave itself
-- delegates to since the Batch 278-280 Tier C refactor -- verified via
-- `pg_get_functiondef` against the CURRENT live body, not assumed from
-- the original 20260730830000 text, which this exact function no longer
-- matches), ALSO durably written to this capability's own domain table
-- (app.employees.<reason column> or app.employee_lifecycle_events.reason
-- or app.employee_change_requests.reason/decided_reason) in the SAME
-- transaction, one or two statements above the capture_audit_event call --
-- and THAT copy is exactly the one this same migration's Finding A fix
-- above now correctly masks to HRS:View-personal-data-or-self. Duplicating
-- the same free-text value into a SECOND, more broadly-readable channel
-- (app.audit_logs, readable by any tenant_admin) served no purpose the
-- domain table did not already serve, and only widened who could read it.
-- Mirrors the canonical C-24 shape this same batch already established for
-- Ticketing (app.ticket_escalation_audit_projection,
-- supabase/migrations/20260731160000, HRT-291) -- a sensitive free-text
-- value lives in exactly ONE properly-access-controlled place, never
-- duplicated into a less-controlled one.
--
-- Tier B taxonomy self-check for this file (docs/standards/
-- RECURRING_DEFECT_TAXONOMY.md §4): C-24 (this file's entire purpose);
-- C-08 -- re-verified this fix only NARROWS an over-broad leak and never
-- narrows any LEGITIMATE caller's access: self (v_is_self) and any
-- HRS:View-personal-data holder see every one of these fields completely
-- unchanged, before and after; C-11 (grants) -- both revokes target only
-- the specific leaking columns, never the whole table, and the additive
-- re-grant on app.employee_lifecycle_events is explicit, never blanket.

-- ===========================================================================
-- Finding A, part 1: app.employees -- close the raw-SELECT bypass on the
-- five HR-narrative reason columns. RLS (employees_select_scoped) is left
-- untouched -- correct and unchanged for every other column on this table,
-- which any active tenant member legitimately sees (an org directory).
-- ===========================================================================
revoke select (revision_reason, suspend_reason, terminate_reason, archive_reason, leave_reason) on app.employees from authenticated;

-- ===========================================================================
-- Finding A, part 2: app.employee_lifecycle_events -- same treatment. RLS
-- (employee_lifecycle_events_select_scoped) stays broad (any active tenant
-- member sees the structural transition timeline); only the free-text
-- `reason` column is withheld from the raw table grant.
-- ===========================================================================
revoke select on app.employee_lifecycle_events from authenticated;
grant select (id, tenant_id, master_record_id, from_status, to_status, metadata, actor_auth_user_id, actor_label, occurred_at) on app.employee_lifecycle_events to authenticated;

-- ===========================================================================
-- Finding A, part 3: app.get_employee_profile -- mask the five reason
-- columns identically to every other classified pii column two lines above.
-- Same signature, body-only change (plain create or replace).
-- ===========================================================================
create or replace function app.get_employee_profile(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  master_record_id uuid, employee_number text, tenant_id uuid, user_id uuid, full_name text, employment_type text, lifecycle_status text, intake_source text,
  work_email text, work_phone text, personal_email text, personal_phone text, national_id_number text, date_of_birth date, gender text,
  personal_address_street text, personal_address_city text, personal_address_province text, personal_address_postal_code text, personal_address_country text,
  hire_date date, probation_end_date date, employment_end_date date, company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid,
  position_title text, manager_employee_id uuid, revision_reason text, suspend_reason text, terminate_reason text, archive_reason text, leave_reason text,
  record_version integer, created_at timestamptz, updated_at timestamptz, personal_data_masked boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_master app.master_records;
  v_caller_user_id uuid;
  v_is_self boolean;
  v_unmasked boolean;
begin
  -- Table-aliased and explicitly qualified: this function's own RETURNS TABLE
  -- includes both master_record_id and tenant_id, so a bare reference to either
  -- name is genuinely ambiguous against those OUT columns (the identical class of
  -- bug app.get_my_employee_profile hit, found live running this checkpoint's own
  -- db-test suite).
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = v_employee.tenant_id;
  v_is_self := v_caller_user_id is not null and v_employee.user_id is not distinct from v_caller_user_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed and not v_is_self then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_unmasked := v_is_self or app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  select * into v_master from app.master_records where id = p_master_record_id;

  return query
  select
    v_employee.master_record_id, v_master.code, v_employee.tenant_id, v_employee.user_id, v_employee.full_name, v_employee.employment_type,
    v_employee.lifecycle_status, v_employee.intake_source, v_employee.work_email, v_employee.work_phone,
    case when v_unmasked then v_employee.personal_email else null end,
    case when v_unmasked then v_employee.personal_phone else null end,
    case when v_unmasked then v_employee.national_id_number else null end,
    case when v_unmasked then v_employee.date_of_birth else null end,
    case when v_unmasked then v_employee.gender else null end,
    case when v_unmasked then v_employee.personal_address_street else null end,
    case when v_unmasked then v_employee.personal_address_city else null end,
    case when v_unmasked then v_employee.personal_address_province else null end,
    case when v_unmasked then v_employee.personal_address_postal_code else null end,
    case when v_unmasked then v_employee.personal_address_country else null end,
    v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id,
    -- HRT-293 Finding A fix: these five HR-narrative reason columns can carry
    -- disciplinary/medical/performance narrative (e.g. a real terminate_reason
    -- or suspend_reason) and must be masked identically to every other
    -- classified personal field above -- previously returned unconditionally.
    case when v_unmasked then v_employee.revision_reason else null end,
    case when v_unmasked then v_employee.suspend_reason else null end,
    case when v_unmasked then v_employee.terminate_reason else null end,
    case when v_unmasked then v_employee.archive_reason else null end,
    case when v_unmasked then v_employee.leave_reason else null end,
    v_employee.record_version, v_employee.created_at, v_employee.updated_at, not v_unmasked;
end;
$$;

comment on function app.get_employee_profile is 'HRT-274: HR/self-service detail read. Sensitive personal columns (including HRT-293 Finding A''s five HR-narrative reason columns) are nulled (personal_data_masked=true) unless the caller holds HRS:View personal data OR is reading their own linked profile (v_is_self) -- own-profile access never requires the HR permission.';

-- ===========================================================================
-- Finding A, part 4: app.get_employee_lifecycle_history -- authority gate
-- UNCHANGED (plain HRS:View still required to call this function at all --
-- this fix does not widen who may reach it); `reason` is now masked to null
-- unless the caller additionally holds HRS:View personal data. Return type
-- is unchanged (`setof app.employee_lifecycle_events`), achieved via a row
-- constructor cast rather than a `returns table` rewrite, so this remains a
-- plain body-only `create or replace` (no DROP/re-GRANT needed).
-- ===========================================================================
create or replace function app.get_employee_lifecycle_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_lifecycle_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- HRT-293 Finding A fix: `reason` can carry the identical disciplinary/
  -- medical/performance narrative app.get_employee_profile's own reason
  -- columns carry -- previously returned unconditionally (`select *`) to
  -- any plain HRS:View holder. Masked here to HRS:View-personal-data only,
  -- matching app.get_employee_profile's own v_unmasked gate exactly (no
  -- self-branch: this function's own call-authority gate above never let
  -- a non-HRS:View self-caller reach this point in the first place, so
  -- there is no legitimate self-only caller whose access this could
  -- narrow).
  v_unmasked := app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  -- A plain flat column list, never a `(...)::app.employee_lifecycle_events`
  -- row-constructor cast -- self-found live bug during this checkpoint's own
  -- adversarial testing: `RETURN QUERY` against a `RETURNS SETOF <composite>`
  -- function requires the query's own OUTPUT COLUMNS to match the composite
  -- type's attributes one-for-one; a `select (a, b, c)::sometype from …`
  -- instead produces a single composite-typed output COLUMN, which Postgres
  -- correctly rejects ("Returned type employee_lifecycle_events does not
  -- match expected type uuid in column 1"). A flat column list achieves the
  -- identical masking with the identical unchanged return signature.
  return query
  select
    e.id, e.tenant_id, e.master_record_id, e.from_status, e.to_status,
    case when v_unmasked then e.reason else null end,
    e.metadata, e.actor_auth_user_id, e.actor_label, e.occurred_at
  from app.employee_lifecycle_events e
  where e.master_record_id = p_master_record_id
  order by e.occurred_at;
end;
$$;

comment on function app.get_employee_lifecycle_history is 'HRT-274, masked by the HRT-293 Finding A fix: `reason` is nulled unless the caller holds HRS:View personal data -- previously an unconditional `select *` leaking disciplinary/medical/performance narrative to any plain HRS:View holder.';

-- ===========================================================================
-- Finding B: the 9 Employee Master capture_audit_event call sites named by
-- the audit, plus a 10th self-found site (app._transition_employee_leave_
-- status, added after app.start_employee_leave below -- see its own header
-- comment). Each
-- function below is reproduced at its exact current live body (verified via
-- pg_get_functiondef against a fully-migrated database) with ONLY the
-- single audit-reason argument changed from the raw p_reason/p_decided_reason
-- to null, per this migration's own header rationale.
-- ===========================================================================

create or replace function app.decide_employee_approval(p_master_record_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_new_status text;
  v_action text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject an employee profile' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_action := case p_decision when 'approve' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'submitted' then
    raise exception 'invalid_transition: employee % is % and cannot be decided', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'draft' end;

  update app.employees
  set lifecycle_status = v_new_status,
      revision_reason = case when p_decision = 'reject' then p_reason else revision_reason end
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'submitted', v_new_status, p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.employees.revision_reason (masked by this same
  -- migration's Finding A fix) and app.employee_lifecycle_events.reason
  -- (column-restricted by this same migration) -- never also duplicated
  -- into app.audit_logs.reason, which any plain tenant_admin can read via
  -- app.query_audit_logs/app.export_audit_logs with zero HRS permission.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_approval',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('decision', p_decision, 'lifecycle_status', v_new_status)
  );

  return v_employee;
end;
$$;

create or replace function app.start_employee_leave(p_master_record_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.employees where master_record_id = p_master_record_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app._transition_employee_leave_status(p_master_record_id, p_expected_version, 'on_leave', p_reason, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.start_employee_leave is 'HRT-274: app._transition_employee_leave_status (fixed by this same migration, immediately below) is the single shared engine that both this HRS:Edit-gated wrapper and the PLT-123-approval-authority-gated app.decide_leave_request path (HRT-280) both call -- see 20260730970000''s own header for why the latter must never route through this wrapper''s own HRS:Edit gate.';

-- Self-found 10th Finding B site (not named in the original audit text,
-- which cited app.start_employee_leave's OWN pre-refactor 20260730830000
-- body -- superseded by 20260730970000's Batch 278-280 Tier C fix, which
-- refactored it into a thin wrapper around this shared engine, verified
-- live via pg_get_functiondef, not assumed): app._transition_employee_
-- leave_status is service_role-only (never directly reachable by
-- `authenticated`), but it is the ACTUAL current call site that receives a
-- real, HR-supplied leave reason from app.start_employee_leave -- every
-- other caller of this shared engine (app.end_employee_leave,
-- app.decide_leave_request's/app.cancel_leave_request's own internal
-- lifecycle-sync calls) passes either `null` or a synthetic non-sensitive
-- label ('leave_request:<id>'), never a raw human reason.
create or replace function app._transition_employee_leave_status(p_master_record_id uuid, p_expected_version integer, p_to_status text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_from_status text;
begin
  if p_to_status not in ('on_leave', 'active') then
    raise exception 'invalid_leave_transition_target: % is not a supported leave lifecycle target', p_to_status using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_employee.lifecycle_status;
  if p_to_status = 'on_leave' then
    if v_from_status <> 'active' then
      raise exception 'invalid_transition: employee % is % and cannot start leave', p_master_record_id, v_from_status using errcode = 'check_violation';
    end if;
    update app.employees set lifecycle_status = 'on_leave', leave_reason = p_reason
    where master_record_id = p_master_record_id and record_version = p_expected_version
    returning * into v_employee;
  else
    if v_from_status <> 'on_leave' then
      raise exception 'invalid_transition: employee % is % and cannot end leave', p_master_record_id, v_from_status using errcode = 'check_violation';
    end if;
    update app.employees set lifecycle_status = 'active', leave_reason = null
    where master_record_id = p_master_record_id and record_version = p_expected_version
    returning * into v_employee;
  end if;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, p_to_status, p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.employees.leave_reason (masked by this same
  -- migration's Finding A fix) and app.employee_lifecycle_events.reason
  -- (column-restricted by this same migration) -- never also duplicated
  -- into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label,
    case when p_to_status = 'on_leave' then 'start_employee_leave' else 'end_employee_leave' end,
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app._transition_employee_leave_status is 'HRT-274/HRT-280 (Batch 278-280 Tier C fix, 20260730970000): shared leave-status-transition engine with no authority check of its own -- callers (app.start_employee_leave/app.end_employee_leave, HRS:Edit-gated; app.decide_leave_request/app.cancel_leave_request, PLT-123-approval-authority-gated) each establish their own sufficient authority before calling this. HRT-293 Finding B fix: the audit-log reason argument is now null -- leave_reason lives only in app.employees (self-or-HRS:View-personal-data-masked) and app.employee_lifecycle_events (column-restricted).';

create or replace function app.suspend_employee(p_master_record_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to suspend an employee' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('active', 'on_leave') then
    raise exception 'invalid_transition: employee % is % and cannot be suspended', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  update app.employees
  set lifecycle_status = 'suspended', suspend_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'suspended', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

create or replace function app.terminate_employee(p_master_record_id uuid, p_expected_version integer, p_reason text, p_employment_end_date date, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to terminate an employee' using errcode = 'check_violation';
  end if;
  if p_employment_end_date is null then
    raise exception 'employment_end_date_required: an effective employment_end_date is required to terminate an employee' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('active', 'on_leave', 'suspended') then
    raise exception 'invalid_transition: employee % is % and cannot be terminated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  update app.employees
  set lifecycle_status = 'terminated', terminate_reason = p_reason, employment_end_date = p_employment_end_date,
      suspend_reason = null, leave_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'terminated', p_reason, jsonb_build_object('employment_end_date', p_employment_end_date), p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  -- The employment_end_date structural fact is still audited (never sensitive
  -- narrative on its own); only the free-text termination reason is dropped.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_employee',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('employment_end_date', p_employment_end_date)
  );

  return v_employee;
end;
$$;

create or replace function app.archive_employee_profile(p_master_record_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('draft', 'submitted', 'approved', 'terminated') then
    raise exception 'invalid_transition: employee % is % and cannot be archived', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  update app.employees
  set lifecycle_status = 'archived', archive_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_employee_profile',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

create or replace function app.transfer_employee(p_master_record_id uuid, p_expected_version integer, p_company_org_unit_id uuid, p_branch_org_unit_id uuid, p_department_org_unit_id uuid, p_position_title text, p_manager_employee_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_before jsonb;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'invalid_transition: employee % is % and cannot be transferred', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- HRT-275 review-round fix (HIGH): a governed position_id already exists for this
  -- employee -- position_title/manager_employee_id must be changed through
  -- app.propose_employee_position_assignment (the governed workflow), never silently
  -- overwritten here. See 20260730850000's own header for full reasoning.
  if v_employee.position_id is not null then
    raise exception 'governed_position_exists: employee % already has a governed position (%) -- transfer via app.propose_employee_position_assignment, not this free-text transfer', p_master_record_id, v_employee.position_id
      using errcode = 'check_violation';
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  v_before := jsonb_build_object(
    'company_org_unit_id', v_employee.company_org_unit_id, 'branch_org_unit_id', v_employee.branch_org_unit_id,
    'department_org_unit_id', v_employee.department_org_unit_id, 'position_title', v_employee.position_title,
    'manager_employee_id', v_employee.manager_employee_id
  );

  update app.employees
  set company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id,
      department_org_unit_id = p_department_org_unit_id, position_title = p_position_title,
      manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object(
      'event', 'transfer', 'before', v_before,
      'after', jsonb_build_object(
        'company_org_unit_id', p_company_org_unit_id, 'branch_org_unit_id', p_branch_org_unit_id,
        'department_org_unit_id', p_department_org_unit_id, 'position_title', p_position_title,
        'manager_employee_id', p_manager_employee_id
      )
    ),
    p_actor_auth_user_id, p_actor_label
  );

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- v_before (org/position fields
  -- only, never free text) is unaffected; only the raw transfer reason is
  -- dropped from the audit call -- see this migration's own header.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_employee',
    'app.employees', p_master_record_id, 'success', null, v_before, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.transfer_employee is 'HRT-274 (section 22): moves company/branch/department/position/manager while preserving full before/after history in app.employee_lifecycle_events.metadata -- lifecycle_status itself is unchanged by a transfer (from_status=to_status in the event row, a real, disclosed shape distinguishing a transfer event from a status transition). Callable from any non-terminal status.';

create or replace function app.decide_employee_duplicate_candidate(p_candidate_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employee_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.employee_duplicate_candidates;
  v_tenant_id uuid;
begin
  if p_decision not in ('linked', 'dismissed') then
    raise exception 'invalid_decision: % is not linked or dismissed', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a duplicate candidate' using errcode = 'check_violation';
  end if;

  select * into v_row from app.employee_duplicate_candidates where id = p_candidate_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'duplicate_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  v_tenant_id := v_row.tenant_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: duplicate candidate % expected version % but found %', p_candidate_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.decision <> 'pending' then
    raise exception 'duplicate_candidate_already_decided: candidate % is already %', p_candidate_id, v_row.decision using errcode = 'check_violation';
  end if;

  update app.employee_duplicate_candidates
  set decision = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason, record_version = record_version + 1
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: duplicate candidate % target row was concurrently modified (expected version %)', p_candidate_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_duplicate_candidate',
    'app.employee_duplicate_candidates', p_candidate_id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_row;
end;
$$;

create or replace function app.request_employee_change(p_master_record_id uuid, p_field_key text, p_requested_value text, p_reason text, p_actor_auth_user_id uuid)
returns app.employee_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_caller_user_id uuid;
  v_current_value text;
  v_request app.employee_change_requests;
begin
  -- Does not call app.evaluate_permission (identity-match-gated, not permission-gated)
  -- -- explicit session-identity assertion required, per decision 8.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_field_key not in ('personal_email', 'personal_phone', 'personal_address_street', 'personal_address_city', 'personal_address_province', 'personal_address_postal_code', 'personal_address_country') then
    raise exception 'invalid_field_key: % is not a self-editable field', p_field_key using errcode = 'check_violation';
  end if;
  if p_requested_value is null or length(trim(p_requested_value)) = 0 then
    raise exception 'invalid_requested_value: requested_value must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id;
  if not found then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  select id into v_caller_user_id from app.users where auth_user_id = p_actor_auth_user_id and tenant_id = v_employee.tenant_id;
  if v_caller_user_id is null or v_employee.user_id is distinct from v_caller_user_id then
    raise exception 'not_own_profile: identity % may not request a change against employee %', p_actor_auth_user_id, p_master_record_id
      using errcode = 'insufficient_privilege';
  end if;

  execute format('select ($1).%I::text', p_field_key) into v_current_value using v_employee;

  insert into app.employee_change_requests (tenant_id, master_record_id, requested_by_user_id, field_key, current_value_snapshot, requested_value, reason)
  values (v_employee.tenant_id, p_master_record_id, v_caller_user_id, p_field_key, v_current_value, p_requested_value, p_reason)
  returning * into v_request;

  -- app.audit_logs.actor_label is NOT NULL and this RPC carries no p_actor_label
  -- parameter (a genuinely self-service action, no separate human-readable label
  -- threaded through) -- p_actor_auth_user_id::text is the same fallback the
  -- calling Server Action layer already uses whenever no display name is
  -- available (mirrors app/(tenant)/[tenantSlug]/procurement/vendors/actions.ts's
  -- own `actorLabel: access.authUserId` convention), found live running this
  -- checkpoint's own db-test suite (a real NOT NULL violation, not a lint nit).
  -- Deliberately NOT to_jsonb(v_request): current_value_snapshot/requested_value are
  -- always a classified pii value for every legal field_key on this table (the
  -- employee_change_requests_field_key_check allow-list is entirely personal_email/
  -- personal_phone/personal_address_* -- there is no non-pii field_key), so the raw
  -- row must never reach app.audit_logs (this checkpoint's own review-round fix,
  -- same defect class as app.employee_audit_projection above).
  --
  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason (the employee's own stated
  -- reason for wanting the change -- can incidentally disclose personal
  -- circumstances) is already durably stored above in
  -- app.employee_change_requests.reason (RLS-scoped to the tenant, and never
  -- itself exported/broadcast) -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'request_employee_change',
    'app.employee_change_requests', v_request.id, 'success', null, null,
    jsonb_build_object('field_key', v_request.field_key, 'status', v_request.status, 'record_version', v_request.record_version)
  );

  return v_request;
end;
$$;

create or replace function app.decide_employee_change_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employee_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.employee_change_requests;
  v_employee app.employees;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a change request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.employee_change_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'change_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'change_request_already_decided: request % is already %', p_request_id, v_request.status using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    select * into v_employee from app.employees where master_record_id = v_request.master_record_id for update;
    -- Fixed column allow-list applied via a real CASE, never dynamic SQL against a
    -- caller-influenced identifier (unlike the read-only snapshot in
    -- app.request_employee_change, this WRITES, so no format()/EXECUTE is used at
    -- all here -- an explicit branch per legal field_key).
    case v_request.field_key
      when 'personal_email' then update app.employees set personal_email = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_phone' then update app.employees set personal_phone = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_street' then update app.employees set personal_address_street = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_city' then update app.employees set personal_address_city = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_province' then update app.employees set personal_address_province = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_postal_code' then update app.employees set personal_address_postal_code = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_country' then update app.employees set personal_address_country = v_request.requested_value where master_record_id = v_request.master_record_id;
      else raise exception 'invalid_field_key: % is not a recognized self-editable field', v_request.field_key using errcode = 'check_violation';
    end case;

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (v_request.tenant_id, v_request.master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_decided_reason, jsonb_build_object('event', 'change_request_applied', 'field_key', v_request.field_key), p_actor_auth_user_id, p_actor_label);
  end if;

  update app.employee_change_requests
  set status = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: change request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_change_request',
    'app.employee_change_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$$;
