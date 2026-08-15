-- HRT-295 (CG-S12-HRT-023, "HRIS and Ticketing Privacy, Integrity and Service
-- Hardening") -- repairs two HRT-294 findings the task charter names together
-- (docs/runtime/KNOWN_ISSUES.md ISS-2026-104 and ISS-2026-108), plus the shared
-- primitive both explicitly point back to (ISS-2026-072's role_assignments-cascade
-- half). One coherent identity-lifecycle coupling, not two unrelated patches.
--
-- ===========================================================================
-- ISS-2026-104 (High): terminate/suspend never revoked Platform authority
-- ===========================================================================
--
-- app.terminate_employee/app.suspend_employee (HRT-274) flipped app.employees.
-- lifecycle_status and wrote an audit/lifecycle-event row -- neither called
-- app.transition_user_status, neither touched app.tenant_user_identities, neither
-- touched app.role_assignments. The only RPC that performed a real Platform-
-- authority revocation was app.request_onboarding_access_revocation, a single
-- task-completion action inside an OPTIONAL Onboarding/Offboarding case, never
-- automatically created or required. Live-proven (ISS-2026-104): a terminated
-- worker with zero offboarding case ever created kept full role-granted authority
-- and could still successfully self-service-create a ticket.
--
-- Fix, option (a) of the three the finding named as viable: app.terminate_employee/
-- app.suspend_employee now call app.transition_user_status directly for their own
-- linked app.users row, in the SAME transaction as the HR-side status flip --
-- atomic, so a Platform-side block (e.g. this identity being the tenant's last
-- active tenant_admin, ISS-2026-072's own pre-existing 'last_critical_admin' guard,
-- now reachable from HRIS for the first time) rolls back the WHOLE termination/
-- suspension rather than leaving a "changed in HR, still fully empowered in
-- Platform" half-state -- the exact gap this fix closes. suspend couples to
-- 'suspended' (temporary authority freeze); terminate couples to 'revoked'
-- (permanent, until a genuine rehire reactivates via the new RPC below).
--
-- app.reactivate_employee (the suspend path's OWN existing un-suspend/reactivate
-- RPC -- checked per this task's own instruction to look for one) is extended to
-- mirror it: undoes JUST the Platform-side suspension, restoring app.users.status
-- to 'active' (suspended -> active was already a valid, unblocked transition --
-- no trigger amendment needed for this edge, unlike the rehire edge below).
--
-- ===========================================================================
-- ISS-2026-072 (High, partial -- the role_assignments half): fixed centrally
-- ===========================================================================
--
-- app.transition_user_status's own 'revoked' branch never touched
-- app.role_assignments at all (only app.revoke_auth_identity + a
-- app.revoke_principal_membership loop). The one present-day caller,
-- app.request_onboarding_access_revocation, worked around this LOCALLY with its
-- own duplicate inline loop (supabase/migrations/20260731190000:2038-2044) --
-- correct for that one call site, but leaving the SHARED primitive itself
-- incomplete for every other caller, including the two new call sites this
-- migration adds. Fixed here, once, centrally, per this task's own explicit
-- instruction ("FIRST fix app.transition_user_status's own revoke branch..."):
-- every ACTIVE app.role_assignments row for the target identity in this tenant is
-- now revoked whenever the identity moves to EITHER 'suspended' (temporary) or
-- 'revoked' (permanent) -- not merely 'revoked' -- because a suspended employee
-- retaining every role-granted write authority is the identical live-proven gap
-- ISS-2026-104 names for termination, just temporary rather than permanent. The
-- pre-existing inline loop inside app.request_onboarding_access_revocation
-- (an already-applied migration, not edited here) becomes a harmless, idempotent
-- duplicate -- app.revoke_role_assignment no-ops cleanly on an already-revoked
-- assignment.
--
-- The OTHER half of ISS-2026-072 -- app.evaluate_permission never re-checking
-- app.users.status/tenant membership as defense in depth -- remains explicitly
-- OPEN. That is a distinct, systemic, shared-RBAC-evaluator change (touching
-- every domain in the Platform, not an HRIS-scoped repair) the finding's own text
-- names as a SEPARATE viable option (c), not required once option (a) closes the
-- live-proven authority-retention path through the concrete coupling below.
-- Broadening evaluate_permission itself here would be exactly the kind of
-- "new capability / speculative redesign" this checkpoint's charter forbids.
--
-- ===========================================================================
-- ISS-2026-108 (High): a rehired employee's Platform access could never return
-- ===========================================================================
--
-- app.rehire_employee (HRT-277) correctly reactivates the HR employee record
-- without duplicating it -- but the linked app.users row stayed permanently
-- 'revoked' with no RPC anywhere able to reverse it: app.transition_user_status
-- only ever passed 'revoked' (its sole caller, the offboarding revocation path);
-- app.request_onboarding_access_provisioning explicitly rejects a revoked target
-- identity with an error naming the missing remediation step by name. Both
-- app.users and the underlying app.tenant_user_identities table declare 'revoked'
-- UNCONDITIONALLY terminal at the trigger level, and app.tenant_user_identities'
-- own unique (auth_user_id, tenant_id) constraint makes "re-invite as a new row"
-- (that table's own stated original design intent) structurally impossible for a
-- real rehire -- there is no second row to create.
--
-- Fix: app.enforce_user_status_transition and app.enforce_identity_link_transition
-- are amended to permit exactly ONE new outbound edge from 'revoked' --
-- revoked -> active -- and nothing else; every other transition away from
-- 'revoked' remains hard-blocked, unconditionally, at the trigger level, for every
-- caller, exactly as before. This is a NECESSARY, structural amendment (there is
-- no way to honor a genuine rehire without it, given the unique-constraint
-- reality above) -- but per the finding's own explicit warning ("versus loosening
-- app.transition_user_status generically, which risks reopening unrelated
-- revocation-permanence guarantees elsewhere"), the AUTHORIZATION boundary is
-- deliberately NOT placed in the trigger (a trigger cannot ask "was there a real,
-- approved rehire event?"). It is placed entirely in a new, narrowly-gated RPC,
-- app.reactivate_user_after_rehire -- gated at least as strictly as
-- app.request_onboarding_access_revocation (HRS:Override + a non-empty reason),
-- and additionally requires the target employee's CURRENT lifecycle_status to be
-- 'active' with a real, on-file terminated -> active (rehire)
-- app.employee_lifecycle_events row not since superseded by a later revoke. This
-- is the ONLY call site anywhere in the repository that ever passes
-- p_new_status='active' for a currently-'revoked' app.users row -- every existing
-- caller of app.transition_user_status is unaffected and continues to reach
-- exactly the transitions it already reached.
--
-- Design decision (stated explicitly, per this task's own instruction):
-- app.rehire_employee (HRT-277, an already-applied migration) is left UNEDITED
-- and is NOT made to call the new reactivation RPC automatically. The two stay
-- distinct, separately-callable governed steps -- "the HR record says this person
-- is back" (app.rehire_employee, HRS:Override, no Platform effect) versus "their
-- Platform/ESS/MSS access is restored" (app.reactivate_user_after_rehire,
-- HRS:Override, requires the rehire to already be on file). This mirrors this
-- SAME capability area's own established separation everywhere else: Onboarding/
-- Offboarding already separates "the employee master record exists" from "access
-- is provisioned" (a distinct access_provisioning/access_revocation task, never
-- silently bundled into a case-status flip), and app.reactivate_employee's own
-- role-assignments-are-never-auto-restored choice above follows the identical
-- principle. Bundling the two here would also mean editing an already-applied
-- migration's function for no correctness reason, or duplicating rehire_employee's
-- whole precondition surface for no benefit.
--
-- Role_assignments are DELIBERATELY not auto-restored by the new RPC (see its own
-- comment) -- a real role grant is always a separate, explicit, governed act
-- (app.request_onboarding_access_provisioning, unedited, already works correctly
-- the moment the target identity is active/invited again).
--
-- ===========================================================================
-- Regression evidence
-- ===========================================================================
-- scripts/db-tests/user-lifecycle.sql (structural: the new revoked -> active edge
-- exists and is the ONLY new edge -- every other outbound edge from revoked is
-- still rejected); scripts/db-tests/hris-employee-master.sql (end-to-end:
-- terminate_employee/suspend_employee/reactivate_employee coupling, role_assignments
-- cascade proven via app.evaluate_permission before/after, a forged-session
-- app.get_my_employee_profile read blocked post-termination, last_critical_admin
-- now reachable from terminate_employee); scripts/db-tests/hris-onboarding-
-- offboarding.sql (end-to-end: the SAME real terminate -> rehire -> reactivate
-- cycle this file's own existing "Existing Employee Two" fixture already drives,
-- extended with the new RPC's gating, success, and a forged-session
-- app.create_ticket call proving ESS access genuinely restored; a negative case
-- using this file's own "Existing Employee One" fixture, revoked but never
-- terminated, proving no_rehire_event fires and is not merely "any revoked
-- identity").
--
-- Per ERR-2026-004: this migration carries its own explicit
-- `revoke execute on all functions in schema app from public` before its final
-- grants.

-- ===========================================================================
-- 1. Trigger amendments -- the one new revoked -> active edge, nothing else.
-- ===========================================================================

create or replace function app.enforce_user_status_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  -- HRT-295 / ISS-2026-108 amendment: 'revoked' remains terminal for every
  -- transition EXCEPT one narrow, deliberately-added edge -- revoked -> active.
  -- The ONLY caller anywhere in this repository that ever reaches this edge is
  -- app.reactivate_user_after_rehire (HRS:Override-gated, requires a real,
  -- on-file, not-since-superseded rehire_employee event) -- see this migration's
  -- own header for the full rationale and docs/runtime/KNOWN_ISSUES.md
  -- ISS-2026-108 for the evidence trail. Every OTHER outbound edge from revoked
  -- is still hard-blocked here, unconditionally, exactly as before.
  if old.status = 'revoked' and new.status <> 'active' then
    raise exception 'invalid_user_transition: user % is revoked, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'invited' and new.status in ('active', 'revoked'))
    or (old.status = 'active' and new.status in ('suspended', 'revoked'))
    or (old.status = 'suspended' and new.status in ('active', 'revoked'))
    or (old.status = 'revoked' and new.status = 'active')
  ) then
    raise exception 'invalid_user_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create or replace function app.enforce_identity_link_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  -- HRT-295 / ISS-2026-108 amendment -- identical rationale to
  -- app.enforce_user_status_transition's own amendment immediately above (this
  -- table has no 'suspended' state, only invited/active/revoked): revoked remains
  -- terminal for every transition except revoked -> active, reachable only
  -- through app.transition_user_status's own revoked-source sync branch, itself
  -- reachable only through app.reactivate_user_after_rehire.
  if old.status = 'revoked' and new.status <> 'active' then
    raise exception 'invalid_identity_transition: identity link % is revoked, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'invited' and new.status in ('active', 'revoked'))
    or (old.status = 'active' and new.status = 'revoked')
    or (old.status = 'revoked' and new.status = 'active')
  ) then
    raise exception 'invalid_identity_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- New history event_type -- additive widen of an existing CHECK constraint (the
-- table itself, an already-applied migration, is not edited).
alter table app.user_lifecycle_history drop constraint user_lifecycle_history_event_type_check;
alter table app.user_lifecycle_history add constraint user_lifecycle_history_event_type_check
  check (event_type in ('invite', 'resend_invite', 'activate', 'suspend', 'reactivate', 'revoke', 'cancel_invite', 'org_reassign', 'rehire_reactivate'));

-- ===========================================================================
-- 2. app.transition_user_status -- role_assignments cascade (ISS-2026-072) +
--    the revoked -> active edge's own mechanics (ISS-2026-108).
-- ===========================================================================

create or replace function app.transition_user_status(
  p_id uuid,
  p_new_status text,
  p_reason text,
  p_requested_by text
)
returns app.users
language plpgsql
as $$
declare
  v_current app.users;
  v_updated app.users;
  v_other_active_admins integer;
  v_event_type text;
  v_membership record;
  v_role_assignment record;
begin
  select * into v_current from app.users where id = p_id;
  if not found then
    raise exception 'user_not_found: no user %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.status = 'active' and p_new_status in ('suspended', 'revoked') then
    if exists (
      select 1 from app.principal_memberships
      where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id
        and layer = 'tenant_admin' and status = 'active'
    ) then
      select count(*) into v_other_active_admins
      from app.principal_memberships pm
      join app.users u on u.auth_user_id = pm.auth_user_id and u.tenant_id = pm.tenant_id
      where pm.tenant_id = v_current.tenant_id and pm.layer = 'tenant_admin' and pm.status = 'active'
        and u.status = 'active' and u.id <> p_id;

      if v_other_active_admins = 0 then
        raise exception 'last_critical_admin: cannot % the tenant''s only active tenant admin', p_new_status
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  v_event_type := case
    when v_current.status = 'invited' and p_new_status = 'revoked' then 'cancel_invite'
    when v_current.status = 'invited' and p_new_status = 'active' then 'activate'
    when v_current.status = 'active' and p_new_status = 'suspended' then 'suspend'
    when v_current.status = 'suspended' and p_new_status = 'active' then 'reactivate'
    when v_current.status = 'revoked' and p_new_status = 'active' then 'rehire_reactivate'
    when p_new_status = 'revoked' then 'revoke'
    else p_new_status
  end;

  update app.users
  set status = p_new_status,
      activated_at = case when p_new_status = 'active' and v_current.activated_at is null then now() else v_current.activated_at end,
      suspended_at = case when p_new_status = 'suspended' then now() else v_current.suspended_at end,
      suspended_reason = case when p_new_status = 'suspended' then p_reason else v_current.suspended_reason end,
      revoked_at = case when p_new_status = 'revoked' then now() else v_current.revoked_at end,
      revoked_reason = case when p_new_status = 'revoked' then p_reason else v_current.revoked_reason end
  where id = p_id
  returning * into v_updated;

  insert into app.user_lifecycle_history (user_id, tenant_id, event_type, from_status, to_status, reason, requested_by)
  values (p_id, v_current.tenant_id, v_event_type, v_current.status, p_new_status, p_reason, p_requested_by);

  -- HRT-295 / ISS-2026-108 amendment: also syncs the underlying
  -- app.tenant_user_identities linkage back to 'active' -- and records a real
  -- history row for it -- when THIS transition is the one deliberately-added
  -- revoked -> active edge. The pre-existing invited -> active sync is unchanged
  -- in shape (still no history row for that pre-existing branch, matching its
  -- own established, unmodified behavior).
  if p_new_status = 'active' and v_current.status in ('invited', 'revoked') then
    update app.tenant_user_identities
    set status = 'active'
    where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status = v_current.status;

    if v_current.status = 'revoked' then
      insert into app.tenant_user_identity_history (auth_user_id, tenant_id, from_status, to_status, reason, requested_by)
      values (v_current.auth_user_id, v_current.tenant_id, 'revoked', 'active', p_reason, p_requested_by);
    end if;
  end if;

  if p_new_status = 'revoked' then
    if exists (
      select 1 from app.tenant_user_identities
      where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status <> 'revoked'
    ) then
      perform app.revoke_auth_identity(v_current.auth_user_id, v_current.tenant_id, 'user offboarded: ' || p_reason, p_requested_by);
    end if;

    for v_membership in
      select id from app.principal_memberships
      where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status = 'active'
    loop
      perform app.revoke_principal_membership(v_membership.id, 'user offboarded: ' || p_reason, p_requested_by);
    end loop;
  end if;

  -- HRT-295 / ISS-2026-072 fix (the role_assignments half, previously OPEN, High)
  -- -- see this migration's own header. Fixed here, centrally, for EVERY current
  -- and future caller: both 'suspended' (a temporary authority freeze) and
  -- 'revoked' (permanent, until a genuine rehire reactivates) now strip every
  -- ACTIVE app.role_assignments row this identity holds in this tenant. Re-grant
  -- is always a separate, explicit, governed act
  -- (app.request_onboarding_access_provisioning) -- never an automatic side
  -- effect of this status flip.
  if p_new_status in ('suspended', 'revoked') then
    for v_role_assignment in
      select id from app.role_assignments
      where tenant_id = v_current.tenant_id and auth_user_id = v_current.auth_user_id and status = 'active'
    loop
      perform app.revoke_role_assignment(v_role_assignment.id, p_reason, p_requested_by);
    end loop;
  end if;

  return v_updated;
end;
$$;

-- ===========================================================================
-- 3. app.suspend_employee / app.terminate_employee / app.reactivate_employee --
--    couple to app.transition_user_status in the SAME transaction (ISS-2026-104).
-- ===========================================================================

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

  -- HRT-295 / ISS-2026-104 fix (previously OPEN, High): a suspended employee's
  -- linked Platform identity is now coupled to the SAME transaction --
  -- app.transition_user_status (with this migration's own role_assignments
  -- cascade fix) strips every active role_assignment and flips app.users.status
  -- to 'suspended', so a suspended employee can no longer exercise ANY
  -- permission-gated write authority system-wide. Atomic: if the Platform-side
  -- transition is blocked (e.g. this identity is the tenant's last active
  -- tenant_admin -- ISS-2026-072's own pre-existing 'last_critical_admin' guard,
  -- now reachable here for the first time), the WHOLE suspension rolls back
  -- rather than leaving a "suspended in HR, still fully empowered in Platform"
  -- half-state. No-op when the employee has no linked Platform user.
  if v_employee.user_id is not null then
    perform app.transition_user_status(v_employee.user_id, 'suspended', p_reason, p_actor_label);
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see 20260731180000's own header.
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

  -- HRT-295 / ISS-2026-104 fix (previously OPEN, High -- see this migration's own
  -- header and docs/runtime/KNOWN_ISSUES.md ISS-2026-104): termination now ALWAYS
  -- couples to the real Platform-authority revoke, in the SAME transaction,
  -- rather than depending on a wholly separate, optional Onboarding/Offboarding
  -- case ever being created and its access_revocation task ever being completed.
  -- Idempotent against a linked identity ALREADY revoked via that offboarding-case
  -- path (a same-status transition is a harmless no-op re-confirmation, not an
  -- error -- see app.enforce_user_status_transition's own early `new.status =
  -- old.status` return). No-op when the employee has no linked Platform user.
  if v_employee.user_id is not null then
    perform app.transition_user_status(v_employee.user_id, 'revoked', p_reason, p_actor_label);
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see 20260731180000's own header.
  -- The employment_end_date structural fact is still audited (never sensitive
  -- narrative on its own); only the free-text termination reason is dropped.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_employee',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('employment_end_date', p_employment_end_date)
  );

  return v_employee;
end;
$$;

comment on function app.terminate_employee is 'HRT-274 (section 24: "never erases required payroll, attendance, Operations or audit history"): terminal, but the row and every child/history row is preserved unchanged -- no delete anywhere. HRT-295 / ISS-2026-104 fix: user_id remains linked, but Platform authentication/authority IS now revoked in the same transaction via app.transition_user_status (previously a separate, optional PLT-107/108 action never performed here -- the exact gap ISS-2026-104 proved live). See docs/runtime/KNOWN_ISSUES.md ISS-2026-104.';

create or replace function app.reactivate_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_restore_status text;
  v_platform_status text;
begin
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

  if v_employee.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: employee % is % and cannot be reactivated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- Restore the status the employee was suspended FROM (active or on_leave) --
  -- unmodified from this function's own pre-existing review-round fix.
  select from_status into v_restore_status
  from app.employee_lifecycle_events
  where master_record_id = p_master_record_id and to_status = 'suspended'
  order by occurred_at desc
  limit 1;
  if v_restore_status is null or v_restore_status not in ('active', 'on_leave') then
    v_restore_status := 'active';
  end if;

  update app.employees
  set lifecycle_status = v_restore_status, suspend_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'suspended', v_restore_status, p_actor_auth_user_id, p_actor_label);

  -- HRT-295 / ISS-2026-104 fix: the mirror image of app.suspend_employee's own
  -- new coupling above -- undoes JUST the Platform-side suspension THIS
  -- repository's own app.suspend_employee now performs, restoring
  -- app.users.status to 'active' (a pre-existing, valid, unblocked
  -- suspended -> active transition -- no trigger amendment needed for this
  -- edge). Deliberately does NOT re-grant any role_assignments
  -- app.transition_user_status revoked during the suspension -- matching this
  -- same migration's own app.reactivate_user_after_rehire precedent below: a
  -- real role grant is always a separate, explicit, governed act
  -- (app.request_onboarding_access_provisioning), never an automatic side effect
  -- of a status flip. Guarded on the Platform user's OWN current status (not
  -- merely "linked"), so this is a safe no-op for an employee whose linked
  -- identity was, for any reason (including every pre-this-migration suspend),
  -- never actually suspended at the Platform layer.
  if v_employee.user_id is not null then
    select status into v_platform_status from app.users where id = v_employee.user_id;
    if v_platform_status = 'suspended' then
      perform app.transition_user_status(v_employee.user_id, 'active', 'employee reactivated: end of suspension', p_actor_label);
    end if;
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

-- ===========================================================================
-- 4. app.reactivate_user_after_rehire -- the new, governed reactivation RPC
--    ISS-2026-108 needs, gated at least as strictly as
--    app.request_onboarding_access_revocation.
-- ===========================================================================

create function app.reactivate_user_after_rehire(
  p_master_record_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.users
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_user app.users;
  v_rehire_event app.employee_lifecycle_events;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reactivate Platform access after a rehire' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  -- Gated at least as strictly as app.request_onboarding_access_revocation itself
  -- (ISS-2026-108's own explicit requirement) -- the same HRS:Override bar
  -- app.terminate_employee/app.suspend_employee use.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.user_id is null then
    raise exception 'no_linked_identity: employee % has no linked Platform user, nothing to reactivate', p_master_record_id
      using errcode = 'check_violation';
  end if;

  -- "Callable only for a linked employee with a genuine approved rehire event"
  -- (ISS-2026-108's own required shape): the employee's CURRENT lifecycle_status
  -- must be 'active' (app.rehire_employee's own, and only, terminated -> active
  -- effect) -- not merely "was rehired at some point in the past."
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'invalid_transition: employee % is %, only a currently active (post-rehire) employee is eligible for Platform reactivation via this path', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  select * into v_rehire_event
  from app.employee_lifecycle_events
  where master_record_id = p_master_record_id and from_status = 'terminated' and to_status = 'active'
  order by occurred_at desc
  limit 1;
  if not found then
    raise exception 'no_rehire_event: employee % has no recorded terminated -> active (rehire) transition on file, cannot reactivate Platform access via this path', p_master_record_id
      using errcode = 'check_violation';
  end if;

  select * into v_user from app.users where id = v_employee.user_id for update;
  if not found then
    raise exception 'user_not_found: no user %', v_employee.user_id using errcode = 'no_data_found';
  end if;

  if v_user.status <> 'revoked' then
    raise exception 'invalid_transition: user % is %, only a revoked identity can be reactivated via this rehire path', v_user.id, v_user.status
      using errcode = 'check_violation';
  end if;

  -- Defense in depth against a stale rehire record: reject if this identity was
  -- revoked AGAIN after the rehire event found above (rehired, then separately
  -- re-offboarded, without this reactivation step ever running in between) -- a
  -- fresh rehire is required before Platform access can be reactivated again.
  if exists (
    select 1 from app.user_lifecycle_history
    where user_id = v_user.id and to_status = 'revoked' and occurred_at > v_rehire_event.occurred_at
  ) then
    raise exception 'stale_rehire_event: user % was revoked again after its most recent rehire event, a fresh rehire is required before Platform access can be reactivated', v_user.id
      using errcode = 'check_violation';
  end if;

  v_user := app.transition_user_status(v_user.id, 'active', p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_user_after_rehire',
    'app.users', v_user.id, 'success', null, null,
    jsonb_build_object('master_record_id', p_master_record_id, 'rehire_event_id', v_rehire_event.id)
  );

  return v_user;
end;
$$;

comment on function app.reactivate_user_after_rehire is 'HRT-295 (CG-S12-HRT-023) / ISS-2026-108 fix: the governed reactivation RPC a genuine rehire needs -- gated at least as strictly as app.request_onboarding_access_revocation (HRS:Override + a non-empty reason), callable only for a linked employee whose CURRENT lifecycle_status is active with a real, on-file terminated -> active (rehire) app.employee_lifecycle_events row not since superseded by a later revoke. Restores app.users.status/app.tenant_user_identities.status to active via app.transition_user_status''s own new revoked -> active edge -- never duplicates app.employees/app.users, never writes app.employees at all. Deliberately does NOT re-grant app.role_assignments -- a real role grant is always a separate, explicit, governed act (app.request_onboarding_access_provisioning), matching app.reactivate_employee''s own identical choice. app.rehire_employee (HRT-277, unedited by this migration) is intentionally left a distinct, separately-callable first step -- see this migration''s own header for the full design decision.';

revoke execute on all functions in schema app from public;

grant execute on function app.reactivate_user_after_rehire(uuid, text, uuid, text) to authenticated, service_role;
