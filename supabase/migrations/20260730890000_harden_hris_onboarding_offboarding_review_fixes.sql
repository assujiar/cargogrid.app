-- Tier C review-round fix pass for HRT-277 (Onboarding and Offboarding,
-- CG-S12-HRT-005). All findings independently re-derived against a live
-- disposable Postgres 16 database before fixing (BUILD_EXECUTION_PROTOCOL.md
-- section 5.3) -- see docs/build-log/phase-07/HRT-277.md's own "Tier C
-- review-round fix pass" section for the full disposition of every reported
-- finding, including the two NOT fixed here (a genuinely new-scope capability
-- filed as a KNOWN_ISSUE, and a C-20 no-UI-caller LOW finding left disclosed
-- per this repository's own established "build it or disclose it" precedent).
--
-- 20260730880000 (the Implement-stage migration this checkpoint fixes) is
-- already committed and is NEVER edited, per AGENTS.md -- this is a new,
-- additive migration, using this repository's own established
-- DROP FUNCTION + CREATE FUNCTION technique wherever a fix changes a
-- function's own parameter list (e.g. 20260730670000), and CREATE OR REPLACE
-- wherever the signature is unchanged.

-- ===========================================================================
-- Fix 1 (HIGH, spec-compliance): app.complete_onboarding_task accepted a
-- handoff task (asset/training/payroll/Operations -- section 21's own
-- "external acknowledgement with evidence, never assumed success", decision
-- 3.8) as completed with BOTH p_evidence_note and p_evidence_file_id null --
-- violating business rule 3 ("Task completion requiring external action needs
-- acknowledged evidence, not UI-only success") and section 19's "never mark
-- ... asset returned or payroll closed without verified acknowledgement".
-- Live-reproduced pre-fix: a mandatory asset-issue task completed with both
-- evidence fields NULL, silently satisfying the mandatory-checklist gate at
-- finalize. Fixed by requiring a non-null note OR file for every
-- task_type='handoff' completion (document/generic tasks are unaffected --
-- section 21's own "external acknowledgement" framing is specific to the
-- handoff category, decision 3.8).
-- ===========================================================================

create or replace function app.complete_onboarding_task(
  p_case_id uuid, p_task_id uuid, p_expected_version integer,
  p_evidence_note text, p_evidence_file_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_file app.files;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.task_type in ('access_provisioning', 'access_revocation') then
    raise exception 'wrong_completion_path: task % is % and must be completed via app.request_onboarding_access_provisioning/revocation', p_task_id, v_task.task_type
      using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot be completed', p_task_id, v_task.status using errcode = 'check_violation';
  end if;

  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from app.onboarding_case_task_dependencies d
    join app.onboarding_case_tasks dep on dep.id = d.depends_on_task_id
    where d.task_id = p_task_id and dep.status not in ('completed', 'waived')
  ) then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Review-round fix (HIGH, spec-compliance, business rule 3 / section 19): a
  -- handoff task (asset/training/payroll/Operations) models an external
  -- acknowledgement, never an assumed success -- a note or a file is now
  -- mandatory, checked against BOTH the value this call supplies and any
  -- already-recorded value (never regressed by a later no-evidence call
  -- either, since the terminal UPDATE below still uses coalesce()).
  if v_task.task_type = 'handoff'
     and coalesce(p_evidence_note, v_task.evidence_note) is null
     and coalesce(p_evidence_file_id, v_task.evidence_file_id) is null
  then
    raise exception 'evidence_required: task % is a handoff task and requires acknowledged evidence (a note or a file) to complete', p_task_id
      using errcode = 'check_violation';
  end if;

  -- Re-validate tenant, record scope, and scan status at THIS accepting RPC
  -- (taxonomy C-10) -- never trust a caller's prior upload success as still
  -- valid.
  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found or v_file.tenant_id <> v_task.tenant_id or v_file.record_type <> 'onboarding_case_task' or v_file.record_id <> p_task_id then
      raise exception 'evidence_file_not_found: file % is not a valid evidence file for task %', p_evidence_file_id, p_task_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status = 'infected' then
      raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.onboarding_case_tasks
  set status = 'completed', completed_at = now(), completed_by = p_actor_label,
      evidence_note = coalesce(p_evidence_note, evidence_note), evidence_file_id = coalesce(p_evidence_file_id, evidence_file_id)
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

comment on function app.complete_onboarding_task is 'HRT-277, hardened by the Tier C review-round fix pass (20260730890000): a task_type=''handoff'' completion now REQUIRES a non-null evidence note or file (business rule 3, section 19) -- document/generic tasks are unaffected. Access-provisioning/revocation are still rejected outright (their own dedicated RPCs).';

-- ===========================================================================
-- Fix 2 (HIGH, spec-compliance): app.request_onboarding_access_revocation had
-- NO reason parameter at all, unlike every sibling governed action in this
-- migration (waive/reopen/cancel/rehire all require p_reason/p_waive_reason).
-- Business rule 5: "Waive, reopen, cancel, rehire and emergency exit require
-- reason, permission and audit." Signature change -> DROP + CREATE (this
-- repository's own established technique, e.g. 20260730670000).
-- ===========================================================================

drop function app.request_onboarding_access_revocation(uuid, uuid, integer, uuid, text);

create function app.request_onboarding_access_revocation(
  p_case_id uuid, p_task_id uuid, p_expected_version integer, p_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_note text;
  v_revoked_user app.users;
  v_role_assignment app.role_assignments;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Override');

  if v_task.task_type <> 'access_revocation' then
    raise exception 'wrong_completion_path: task % is %, not access_revocation', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request revocation', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Review-round fix (HIGH, spec-compliance, business rule 5): a real reason
  -- is now required, mirroring waive/reopen/cancel/rehire's own established
  -- pattern exactly.
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request access revocation' using errcode = 'check_violation';
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'revoke_access', null, p_actor_label)
  returning * into v_request;

  if v_employee.user_id is not null then
    -- Real, governed revocation -- app.transition_user_status already cascades
    -- both the underlying PLT-107 identity linkage AND every active PLT-108
    -- principal membership (its own migration, 20260716102620:271-285).
    perform app.transition_user_status(v_employee.user_id, 'revoked', p_reason, p_actor_label);

    -- Review-round fix (CRITICAL, correctness-concurrency /
    -- revocation-cascade-incomplete): app.transition_user_status's own
    -- revoke branch (PLT-110) never touches app.role_assignments (PLT-111),
    -- and app.evaluate_permission (PLT-112) evaluates role_assignments
    -- directly, never re-checking app.users.status or tenant membership --
    -- live-reproduced pre-fix: a revoked identity with a still-'active'
    -- role_assignments row retained full permission-gated write authority
    -- (evaluate_permission still returned allowed=true, and the identity
    -- could still call app.start_onboarding_case successfully). This is a
    -- real gap in the SHARED PLT-110/112 primitives, used by every domain in
    -- the repository, not something this migration can fix at its root
    -- without a dedicated Platform/RBAC hardening prompt and ADR (AGENTS.md
    -- "Scope and refactoring") -- see docs/runtime/KNOWN_ISSUES.md for the
    -- filed, disclosed systemic gap. What IS fixed here, bounded to this
    -- capability's own real Platform-identity-authority write (the one this
    -- whole prompt is chartered around): every ACTIVE role_assignment this
    -- identity holds in this tenant is explicitly revoked as part of this
    -- same governed call, so THIS revocation path never again leaves
    -- effective authority behind.
    select * into v_revoked_user from app.users where id = v_employee.user_id;
    for v_role_assignment in
      select * from app.role_assignments
      where tenant_id = v_task.tenant_id and auth_user_id = v_revoked_user.auth_user_id and status = 'active'
    loop
      perform app.revoke_role_assignment(v_role_assignment.id, p_reason, p_actor_label);
    end loop;

    update app.onboarding_task_provisioning_requests set status = 'completed', result_user_id = v_employee.user_id, completed_at = now() where id = v_request.id;
    v_note := 'Platform access revoked for user ' || v_employee.user_id::text || ' -- reason: ' || p_reason;

    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_employee.user_id), 0, 'hrt277-revocation:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;
  else
    update app.onboarding_task_provisioning_requests set status = 'completed', completed_at = now() where id = v_request.id;
    v_note := 'No linked Platform user for this employee -- nothing to revoke. Reason: ' || p_reason;
  end if;

  update app.onboarding_case_tasks
  set status = 'completed', completed_at = now(), completed_by = p_actor_label, evidence_note = coalesce(evidence_note, v_note)
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_revocation',
    'app.onboarding_case_tasks', v_task.id, 'success', p_reason, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );

  return v_task;
end;
$$;

comment on function app.request_onboarding_access_revocation is 'HRT-277 section 16/24, hardened by the Tier C review-round fix pass (20260730890000): the real Platform-identity-authority revoke. Now requires a non-empty p_reason (business rule 5, matching waive/reopen/cancel/rehire), and explicitly revokes every active app.role_assignments row for the target identity in this tenant (app.transition_user_status alone does not, see the in-body comment and KNOWN_ISSUES). HRS:Override-gated (the same bar as app.terminate_employee).';

grant execute on function app.request_onboarding_access_revocation(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- Fix 3 (CRITICAL, privilege-escalation / authority-bar-mismatch, same root
-- cause reported by two independent review lenses):
-- app.request_onboarding_access_provisioning gated a REAL app.assign_role
-- (PLT-111) grant behind only HRS:Edit, with zero scoping on which role
-- version could be granted, to whom. app.assign_role's own only in-function
-- guard (self-escalation) fires solely on a SELF-target grant of a
-- protected=true (View-class field-masking) permission -- never a
-- third-party grant, and never an Approve/Override/Delete-class permission
-- either way. Live-exploited (both variants) pre-fix: an actor holding only
-- HRS Create/Edit/View granted an unrelated tenant member (and, separately,
-- themselves) a role carrying FIN:Approve/Override/Delete, PRC:Approve,
-- OPS:Override -- a full cross-domain RBAC authority-boundary bypass, through
-- the shipped UI's own free-text "Role version ids" box.
--
-- Fixed with two independent, defense-in-depth layers, both scoped to this
-- RPC's own consumption of app.assign_role (never touching app.assign_role
-- itself, a pre-existing shared PLT-111 primitive -- redesigning it is a
-- broader refactor requiring its own ADR per AGENTS.md):
--   1. HRS:Override required whenever an ACTUAL role grant is requested
--      (p_role_version_ids non-empty) -- matches the bar
--      app.request_onboarding_access_revocation already correctly uses for
--      the less-escalatory direction, closing the asymmetry the review
--      itself flagged.
--   2. The actor may never delegate a permission they do not themselves
--      already hold in this tenant (app.assert_actor_holds_role_version_
--      permissions, new helper below) -- closes the escalation regardless of
--      which HRS-level bar the actor clears, since HRS authority says nothing
--      about FIN/PRC/OPS authority.
-- The p_role_version_ids-empty path (recording/deferring a request with no
-- auth identity resolved, or resolving an identity with zero roles) is
-- UNCHANGED -- still HRS:Edit, section 22's own "preboarding without user
-- access" alternative flow, genuinely less sensitive since no authority is
-- actually granted.
--
-- Also folds in Fix 3b (MEDIUM, correctness-concurrency /
-- C-01-adjacent/stranded-state): a target identity that is truly
-- non-activatable (revoked/suspended, not merely a fresh invite) was silently
-- completing the task with a "re-run once active" promise that could never be
-- kept (nothing in this repository ever reactivates a revoked/suspended
-- user, and the task's own terminal 'completed' status makes it
-- unreachable again without a manual reopen nobody is prompted to perform).
-- Now raises a clear, typed error instead, leaving the task actionable.
-- Signature unchanged -> CREATE OR REPLACE.
-- ===========================================================================

create function app.assert_actor_holds_role_version_permissions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_role_version_id uuid
)
returns void
language plpgsql
as $$
declare
  v_missing record;
begin
  select perm.resource_module_code, perm.action
  into v_missing
  from app.role_version_permissions rvp
  join app.permissions perm on perm.id = rvp.permission_id
  where rvp.role_version_id = p_role_version_id
    and not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, perm.resource_module_code, perm.action)).allowed
  limit 1;

  if found then
    raise exception 'insufficient_authority_to_delegate: identity % may not grant role version % via onboarding provisioning -- it carries %:% and the granting actor does not hold that permission themselves in tenant %',
      p_actor_auth_user_id, p_role_version_id, v_missing.resource_module_code, v_missing.action, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_actor_holds_role_version_permissions is 'HRT-277 Tier C review-round fix pass (20260730890000): an actor may never delegate, through app.request_onboarding_access_provisioning, a permission they do not themselves already hold in the target tenant. Closes the cross-domain (FIN/PRC/OPS) privilege-escalation path app.assign_role''s own self-escalation guard never covered (protected/View-class permissions only, self-target only). Supreme Admin bypasses via app.evaluate_permission''s own existing exception, unchanged.';

grant execute on function app.assert_actor_holds_role_version_permissions(uuid, uuid, uuid) to service_role;

create or replace function app.request_onboarding_access_provisioning(
  p_case_id uuid, p_task_id uuid, p_expected_version integer,
  p_target_auth_user_id uuid, p_role_version_ids uuid[], p_org_unit_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_user app.users;
  v_role_version_id uuid;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_roles_granted integer := 0;
  v_roles_deferred integer := 0;
  v_completion_note text;
  v_grant_decision app.rbac_decision;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.task_type <> 'access_provisioning' then
    raise exception 'wrong_completion_path: task % is %, not access_provisioning', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request provisioning', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Review-round fix (CRITICAL, privilege-escalation) -- see the migration
  -- header comment above for the full rationale.
  if coalesce(array_length(p_role_version_ids, 1), 0) > 0 then
    v_grant_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'HRS', 'Override');
    if not v_grant_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant % -- granting a real role via onboarding provisioning requires the same bar as access revocation', p_actor_auth_user_id, v_grant_decision.reason, v_task.tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    foreach v_role_version_id in array p_role_version_ids loop
      perform app.assert_actor_holds_role_version_permissions(v_task.tenant_id, p_actor_auth_user_id, v_role_version_id);
    end loop;
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  if v_case.employee_master_record_id is null then
    raise exception 'case_has_no_employee: case % has no linked employee, cannot provision access', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_role_version_ids, org_unit_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'grant_access', p_target_auth_user_id, coalesce(p_role_version_ids, '{}'::uuid[]), p_org_unit_id, p_actor_label)
  returning * into v_request;

  if p_target_auth_user_id is not null then
    -- Real, synchronous, governed grant -- section 16 "Platform identity
    -- authority", never a direct app.users/app.role_assignments write.
    v_user := app.invite_user(v_task.tenant_id, p_target_auth_user_id, coalesce(v_employee.work_email, v_employee.personal_email, v_employee.full_name || '@pending.invite'), v_employee.full_name, p_org_unit_id, p_actor_label, now() + interval '14 days');

    if v_employee.user_id is null then
      perform app.link_employee_user(v_employee.master_record_id, v_employee.record_version, v_user.id, p_actor_auth_user_id, p_actor_label);
    elsif v_employee.user_id <> v_user.id then
      raise exception 'employee_already_linked: employee % is already linked to a different user', v_employee.master_record_id using errcode = 'check_violation';
    end if;

    -- app.assign_role (PLT-111) requires the target app.users row to already
    -- be status='active' -- a freshly-invited user is 'invited' until they
    -- accept the invite themselves. This RPC never force-activates an
    -- unconfirmed account (that would be a real, undisclosed authentication
    -- bypass) -- roles are granted immediately only when the target identity
    -- is ALREADY active; a merely-invited identity legitimately defers (the
    -- realistic "brand new hire, invite just sent" case, section 22's own
    -- "preboarding without user access"). Review-round fix (MEDIUM,
    -- stranded-state): any OTHER non-active status (revoked/suspended -- a
    -- genuinely non-activatable identity) is rejected outright instead of
    -- silently completing with an unkeepable "re-run once active" promise.
    if v_user.status = 'active' then
      foreach v_role_version_id in array coalesce(p_role_version_ids, '{}'::uuid[]) loop
        perform app.assign_role(v_task.tenant_id, v_role_version_id, p_target_auth_user_id, p_actor_auth_user_id, p_actor_label);
        v_roles_granted := v_roles_granted + 1;
      end loop;
    elsif v_user.status = 'invited' then
      v_roles_deferred := coalesce(array_length(p_role_version_ids, 1), 0);
    else
      raise exception 'target_identity_not_activatable: user % has status %, access cannot be granted or meaningfully deferred -- resolve a different target identity, or reactivate the user first', v_user.id, v_user.status
        using errcode = 'check_violation';
    end if;

    update app.onboarding_task_provisioning_requests
    set status = 'completed', result_user_id = v_user.id, completed_at = now()
    where id = v_request.id;

    v_completion_note := 'Platform access granted: user ' || v_user.id::text || ' (status ' || v_user.status || '), ' || v_roles_granted || ' role(s) granted';
    if v_roles_deferred > 0 then
      v_completion_note := v_completion_note || ', ' || v_roles_deferred || ' role(s) deferred until the user accepts their invite (re-run once active)';
    end if;

    -- Async reconciliation/dispatch record (section 17) -- e.g. a downstream
    -- welcome-email/credentials-handoff adapter would claim this job. Reuses
    -- job_type='integration_sync' (decision 8's own sibling reasoning: adding a
    -- domain-specific job_type would widen app.generic_job_types()' shared,
    -- cross-domain single source of truth, out of this single-prompt batch's
    -- own mandate).
    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_user.id), 0, 'hrt277-provisioning:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;

    update app.onboarding_case_tasks
    set status = 'completed', completed_at = now(), completed_by = p_actor_label,
        evidence_note = coalesce(evidence_note, v_completion_note)
    where id = p_task_id and record_version = p_expected_version
    returning * into v_task;
  else
    -- section 22 "preboarding without user access" -- no auth identity
    -- resolved yet. The request is recorded (an acknowledged handoff, never an
    -- assumed success, section 14) and the task moves to in_progress, awaiting
    -- a follow-up call with a resolved p_target_auth_user_id.
    update app.onboarding_case_tasks
    set status = 'in_progress'
    where id = p_task_id and record_version = p_expected_version
    returning * into v_task;
  end if;

  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_provisioning',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );

  return v_task;
end;
$$;

comment on function app.request_onboarding_access_provisioning is 'HRT-277 section 16, hardened by the Tier C review-round fix pass (20260730890000): the real Platform-identity-authority grant. An actual role grant (p_role_version_ids non-empty) now requires HRS:Override AND that the granting actor already holds every permission the requested role version carries (app.assert_actor_holds_role_version_permissions) -- closes a live-exploited cross-domain privilege-escalation path. A target identity in a genuinely non-activatable status (revoked/suspended) is now rejected outright rather than silently completing with an unkeepable deferred-grant promise.';

-- ===========================================================================
-- Fix 4 (CRITICAL, correctness-concurrency, C-01 follow-up): the direct_hire
-- source path's own idempotency replay guard (app.assert_onboarding_case_
-- start_idempotent_replay, added THIS checkpoint's own self-found C-01 fix)
-- compared only case_type/source_type -- never the actual employee identity
-- fields (full_name/employment_type/work_email/effective_date/org units/
-- position/manager). Live-reproduced pre-fix: a same-key replay with a
-- MATERIALLY DIFFERENT hire (different name, employment type, work email)
-- silently returned the FIRST case/employee with no error. Signature change
-- -> DROP + CREATE, plus app.start_onboarding_case's own body is updated
-- (signature unchanged -> CREATE OR REPLACE) to pass the full comparison
-- tuple at all 4 call sites.
-- ===========================================================================

drop function app.assert_onboarding_case_start_idempotent_replay(app.onboarding_offboarding_cases, text, text, uuid, text);

create function app.assert_onboarding_case_start_idempotent_replay(
  p_existing app.onboarding_offboarding_cases, p_case_type text, p_source_type text,
  p_employee_master_record_id uuid, p_effective_date date,
  p_full_name text, p_employment_type text, p_work_email text,
  p_company_org_unit_id uuid, p_branch_org_unit_id uuid, p_department_org_unit_id uuid,
  p_position_title text, p_manager_employee_id uuid,
  p_replay_key text
)
returns void
language plpgsql
as $$
declare
  v_employee app.employees;
begin
  if p_existing.case_type is distinct from p_case_type
     or p_existing.source_type is distinct from p_source_type
     or (p_source_type = 'existing_employee' and p_existing.employee_master_record_id is distinct from p_employee_master_record_id)
  then
    raise exception 'idempotency_key_conflict: idempotency key/source % was already used for a different case request', p_replay_key
      using errcode = 'unique_violation';
  end if;

  -- Review-round fix (CRITICAL, C-01 follow-up): the direct_hire path's own
  -- identity fields, never compared before. effective_date is compared
  -- directly against the case row itself (app.start_onboarding_case stores
  -- coalesce(p_effective_date, v_offer_version.effective_date), which for
  -- direct_hire is always exactly p_effective_date, since v_offer_version is
  -- never populated on that path); the remaining fields are compared against
  -- the linked app.employees row, the actual persisted values, never
  -- re-derived or guessed.
  if p_source_type = 'direct_hire' then
    if p_existing.effective_date is distinct from p_effective_date then
      raise exception 'idempotency_key_conflict: idempotency key % was already used with a different effective_date', p_replay_key
        using errcode = 'unique_violation';
    end if;

    select * into v_employee from app.employees where master_record_id = p_existing.employee_master_record_id;
    if found and (
      v_employee.full_name is distinct from p_full_name
      or v_employee.employment_type is distinct from p_employment_type
      or v_employee.work_email is distinct from p_work_email
      or v_employee.company_org_unit_id is distinct from p_company_org_unit_id
      or v_employee.branch_org_unit_id is distinct from p_branch_org_unit_id
      or v_employee.department_org_unit_id is distinct from p_department_org_unit_id
      or v_employee.position_title is distinct from p_position_title
      or v_employee.manager_employee_id is distinct from p_manager_employee_id
    ) then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different direct-hire request', p_replay_key
        using errcode = 'unique_violation';
    end if;
  end if;
end;
$$;

grant execute on function app.assert_onboarding_case_start_idempotent_replay(app.onboarding_offboarding_cases, text, text, uuid, date, text, text, text, uuid, uuid, uuid, text, uuid, text) to service_role;

create or replace function app.start_onboarding_case(
  p_tenant_id uuid, p_case_type text, p_source_type text,
  p_source_job_offer_id uuid, p_employee_master_record_id uuid,
  p_checklist_template_version_id uuid, p_effective_date date,
  p_full_name text, p_employment_type text, p_work_email text, p_personal_email text,
  p_personal_phone text, p_national_id_number text, p_date_of_birth date, p_gender text,
  p_company_org_unit_id uuid, p_branch_org_unit_id uuid, p_department_org_unit_id uuid,
  p_position_title text, p_manager_employee_id uuid,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.onboarding_offboarding_cases;
  v_offer app.job_offers;
  v_application app.job_applications;
  v_candidate app.candidates;
  v_offer_version app.job_offer_versions;
  v_employee app.employees;
  v_case app.onboarding_offboarding_cases;
  v_template_version app.onboarding_checklist_template_versions;
  v_template app.onboarding_checklist_templates;
  v_task app.onboarding_checklist_template_tasks;
  v_case_task_id uuid;
  v_key_to_case_task_id jsonb := '{}'::jsonb;
  v_dep record;
  v_source_candidate_id uuid;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_case_type not in ('onboarding', 'offboarding', 'transfer') then
    raise exception 'invalid_case_type: %', p_case_type using errcode = 'check_violation';
  end if;
  if p_source_type not in ('job_offer', 'direct_hire', 'existing_employee') then
    raise exception 'invalid_source_type: %', p_source_type using errcode = 'check_violation';
  end if;

  -- Idempotent replay by the case's own idempotency_key (a caller-supplied key,
  -- used for the direct_hire/existing_employee paths; the job_offer path ALSO
  -- gets a structural guarantee via onboarding_offboarding_cases_source_offer_
  -- unique, checked below). Full-tuple compared (taxonomy C-01, hardened
  -- further by the Tier C review-round fix pass for the direct_hire path's
  -- own identity fields) -- a same-key/different-request call raises
  -- idempotency_key_conflict instead of silently returning the first case.
  if p_idempotency_key is not null then
    select * into v_existing from app.onboarding_offboarding_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      perform app.assert_onboarding_case_start_idempotent_replay(
        v_existing, p_case_type, p_source_type, p_employee_master_record_id, p_effective_date,
        p_full_name, p_employment_type, p_work_email,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
        p_position_title, p_manager_employee_id, p_idempotency_key
      );
      return v_existing;
    end if;
  end if;

  if p_source_type = 'job_offer' then
    if p_source_job_offer_id is null then
      raise exception 'source_job_offer_id_required: source_type job_offer requires source_job_offer_id' using errcode = 'check_violation';
    end if;

    -- Structural idempotency for the job_offer path: onboarding_offboarding_
    -- cases_source_offer_unique means a second start against the SAME offer
    -- always returns the FIRST case, never a duplicate (acceptance criterion 1)
    -- -- checked explicitly here (not only relying on the exception handler
    -- below) so a caller who omits p_idempotency_key still gets the safe reuse.
    -- Full-tuple compared (taxonomy C-01): a caller who reuses the SAME
    -- accepted offer but supplies a mismatched case_type (e.g. 'offboarding'
    -- against a source_type that only ever creates 'onboarding' cases) is
    -- rejected, never silently handed back the pre-existing, differently-typed
    -- case.
    select * into v_existing from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id;
    if found then
      perform app.assert_onboarding_case_start_idempotent_replay(
        v_existing, p_case_type, p_source_type, null, p_effective_date,
        p_full_name, p_employment_type, p_work_email,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
        p_position_title, p_manager_employee_id, p_source_job_offer_id::text
      );
      return v_existing;
    end if;

    select * into v_offer from app.job_offers where id = p_source_job_offer_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'offer_not_found: %', p_source_job_offer_id using errcode = 'no_data_found';
    end if;
    if v_offer.status <> 'accepted' then
      raise exception 'offer_not_accepted: offer % is %, only an accepted offer can start an onboarding case', p_source_job_offer_id, v_offer.status
        using errcode = 'check_violation';
    end if;
    if p_case_type <> 'onboarding' then
      raise exception 'invalid_case_type_for_source: source_type job_offer requires case_type onboarding, got %', p_case_type using errcode = 'check_violation';
    end if;

    select * into v_application from app.job_applications where id = v_offer.application_id;
    select * into v_candidate from app.candidates where id = v_application.candidate_id;
    select * into v_offer_version from app.job_offer_versions where id = v_offer.current_version_id;
    v_source_candidate_id := v_candidate.id;

    v_employee := app.create_employee_draft(
      p_tenant_id,
      coalesce(nullif(trim(p_full_name), ''), v_candidate.full_name),
      coalesce(p_employment_type, app.map_offer_employment_type_to_employee(v_offer_version.employment_type)),
      p_work_email,
      coalesce(p_personal_email, v_candidate.email),
      coalesce(p_personal_phone, v_candidate.phone),
      coalesce(p_national_id_number, v_candidate.national_id_number),
      coalesce(p_date_of_birth, v_candidate.date_of_birth),
      p_gender,
      coalesce(p_effective_date, v_offer_version.effective_date),
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
      coalesce(nullif(trim(p_position_title), ''), v_offer_version.title),
      p_manager_employee_id,
      null,
      null,
      'hr_created',
      'hrt277-onboarding-conversion:' || p_source_job_offer_id::text,
      p_actor_auth_user_id, p_actor_label
    );
  elsif p_source_type = 'direct_hire' then
    if p_case_type <> 'onboarding' then
      raise exception 'invalid_case_type_for_source: source_type direct_hire requires case_type onboarding, got %', p_case_type using errcode = 'check_violation';
    end if;
    if p_full_name is null or length(trim(p_full_name)) = 0 then
      raise exception 'invalid_full_name: direct_hire requires full_name' using errcode = 'check_violation';
    end if;
    if p_employment_type is null then
      raise exception 'invalid_employment_type: direct_hire requires employment_type' using errcode = 'check_violation';
    end if;
    if p_idempotency_key is null then
      raise exception 'idempotency_key_required: direct_hire requires a caller-supplied idempotency_key' using errcode = 'check_violation';
    end if;

    v_employee := app.create_employee_draft(
      p_tenant_id, p_full_name, p_employment_type, p_work_email, p_personal_email, p_personal_phone,
      p_national_id_number, p_date_of_birth, p_gender, p_effective_date,
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
      null, null, 'hr_created', 'hrt277-direct-hire:' || p_idempotency_key,
      p_actor_auth_user_id, p_actor_label
    );
  else -- existing_employee (offboarding, transfer, or onboarding-rehire)
    if p_employee_master_record_id is null then
      raise exception 'employee_master_record_id_required: source_type existing_employee requires employee_master_record_id' using errcode = 'check_violation';
    end if;
    select * into v_employee from app.employees where master_record_id = p_employee_master_record_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'employee_not_found: %', p_employee_master_record_id using errcode = 'no_data_found';
    end if;
    if p_case_type = 'offboarding' and v_employee.lifecycle_status not in ('active', 'on_leave', 'suspended') then
      raise exception 'invalid_transition: employee % is %, cannot start an offboarding case', p_employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
    if p_case_type = 'transfer' and v_employee.lifecycle_status not in ('active', 'on_leave') then
      raise exception 'invalid_transition: employee % is %, cannot start a transfer case', p_employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Resolve checklist template version: caller-supplied (validated: published,
  -- correct tenant/case_type), or the tenant's current published default for
  -- this case_type. Locked in on the case (RPD-040).
  if p_checklist_template_version_id is not null then
    select * into v_template_version from app.onboarding_checklist_template_versions where id = p_checklist_template_version_id;
    if not found or v_template_version.tenant_id <> p_tenant_id or v_template_version.status <> 'published' then
      raise exception 'template_version_not_available: % is not a published template version for this tenant', p_checklist_template_version_id
        using errcode = 'check_violation';
    end if;
    select * into v_template from app.onboarding_checklist_templates where id = v_template_version.template_id;
    if v_template.case_type <> p_case_type then
      raise exception 'template_case_type_mismatch: template version % is for case_type %, not %', p_checklist_template_version_id, v_template.case_type, p_case_type
        using errcode = 'check_violation';
    end if;
  else
    select tv.* into v_template_version
    from app.onboarding_checklist_template_versions tv
    join app.onboarding_checklist_templates t on t.id = tv.template_id
    where t.tenant_id = p_tenant_id and t.case_type = p_case_type and tv.status = 'published'
    order by tv.published_at desc
    limit 1;
    if not found then
      raise exception 'no_published_checklist_template: tenant % has no published % checklist template', p_tenant_id, p_case_type
        using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.onboarding_offboarding_cases (
      tenant_id, case_type, source_type, source_job_offer_id, source_job_application_id, source_candidate_id,
      employee_master_record_id, checklist_template_version_id, status, effective_date, initiated_by,
      idempotency_key, created_by
    ) values (
      p_tenant_id, p_case_type, p_source_type, p_source_job_offer_id, v_application.id, v_source_candidate_id,
      v_employee.master_record_id, v_template_version.id, 'active', coalesce(p_effective_date, v_offer_version.effective_date), p_actor_label,
      p_idempotency_key, p_actor_label
    )
    returning * into v_case;
  exception
    when unique_violation then
      -- Concurrent-race recovery (taxonomy C-01: full-tuple compared, not
      -- merely key/offer-matched, mirroring the pre-insert checks above).
      if p_source_job_offer_id is not null then
        select * into v_case from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id;
        if found then
          perform app.assert_onboarding_case_start_idempotent_replay(
            v_case, p_case_type, p_source_type, null, p_effective_date,
            p_full_name, p_employment_type, p_work_email,
            p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
            p_position_title, p_manager_employee_id, p_source_job_offer_id::text
          );
          return v_case;
        end if;
      end if;
      if p_idempotency_key is not null then
        select * into v_case from app.onboarding_offboarding_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          perform app.assert_onboarding_case_start_idempotent_replay(
            v_case, p_case_type, p_source_type, p_employee_master_record_id, p_effective_date,
            p_full_name, p_employment_type, p_work_email,
            p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
            p_position_title, p_manager_employee_id, p_idempotency_key
          );
          return v_case;
        end if;
      end if;
      raise;
  end;

  -- Instantiate tasks (copied at instantiation -- a later template edit never
  -- retroactively changes this case, section 24's own versioning rule).
  for v_task in select * from app.onboarding_checklist_template_tasks where template_version_id = v_template_version.id order by sort_order loop
    insert into app.onboarding_case_tasks (
      case_id, tenant_id, template_task_key, title, description, task_type, handoff_category,
      owner_type, is_mandatory, due_at, sort_order
    ) values (
      v_case.id, p_tenant_id, v_task.task_key, v_task.title, v_task.description, v_task.task_type, v_task.handoff_category,
      v_task.owner_type, v_task.is_mandatory, now() + make_interval(days => v_task.sla_days), v_task.sort_order
    )
    returning id into v_case_task_id;
    v_key_to_case_task_id := v_key_to_case_task_id || jsonb_build_object(v_task.task_key, v_case_task_id::text);
  end loop;

  for v_dep in select * from app.onboarding_checklist_template_task_dependencies where template_version_id = v_template_version.id loop
    insert into app.onboarding_case_task_dependencies (case_id, tenant_id, task_id, depends_on_task_id)
    values (
      v_case.id, p_tenant_id,
      (v_key_to_case_task_id ->> v_dep.task_key)::uuid,
      (v_key_to_case_task_id ->> v_dep.depends_on_task_key)::uuid
    );
  end loop;

  -- A task with an incomplete dependency starts blocked (section 15 "due/
  -- blocked state"), computed once at instantiation from a real dependency
  -- edge, then re-evaluated at every completion (app.complete_onboarding_task/
  -- app.waive_onboarding_task both re-derive downstream blocked state).
  update app.onboarding_case_tasks t
  set status = 'blocked'
  where t.case_id = v_case.id and t.status = 'pending'
    and exists (select 1 from app.onboarding_case_task_dependencies d where d.task_id = t.id);

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_case.id, p_tenant_id, 'start', null, 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'start_onboarding_case',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

comment on function app.start_onboarding_case is 'HRT-277, hardened by the Tier C review-round fix pass (20260730890000): the ADR-0023 Part B conversion. Idempotency replay now compares the full request tuple for the direct_hire path too (previously only case_type/source_type), via the widened app.assert_onboarding_case_start_idempotent_replay. Never inserts into app.master_records/app.employees/app.users directly -- always through the existing governed RPC.';

-- ===========================================================================
-- Fix 5 (CRITICAL, correctness-concurrency, C-04 / dependent-in-flight-
-- process-not-cancelled): app.cancel_onboarding_case had no awareness of, and
-- never revoked, Platform access already granted by a completed (including
-- concurrently-completed) access-provisioning task on the same case --
-- live-reproduced (two real concurrent psql sessions) with a cancelled case
-- left holding a real, active app.role_assignments grant. Fixed by revoking
-- exactly the role grants THIS case's own completed provisioning requests
-- produced, at cancellation -- the underlying app.employees.user_id link and
-- app.users/app.tenant_user_identities rows are deliberately left untouched,
-- extending this function's own existing "cancelling never deletes the
-- employee row" design: only the delegated AUTHORITY is walked back, not the
-- identity/history. Race-safe because the case row itself serializes: any
-- provisioning call that has NOT yet committed by the time this function's
-- own terminal UPDATE succeeds is guaranteed to observe the case as no longer
-- active (app.resolve_onboarding_case_task_for_write's own `for update` lock
-- on the case row, taken before either call's own case-row write) and is
-- rejected outright; any provisioning call that already committed is visible
-- to this scan. Signature unchanged -> CREATE OR REPLACE.
-- ===========================================================================

create or replace function app.cancel_onboarding_case(
  p_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_case_plain app.onboarding_offboarding_cases;
  v_provisioning_request app.onboarding_task_provisioning_requests;
  v_revoke_role_version_id uuid;
  v_role_assignment app.role_assignments;
  v_revoked_count integer := 0;
begin
  -- Deliberately PLAIN (non-locking) read first, mirroring app.reject_
  -- application's own documented lock-order rationale exactly: app.decide_
  -- onboarding_case_finalize_approval's own call path locks app.approval_
  -- request_steps/app.approval_requests (inside app.decide_approval_step)
  -- BEFORE it ever touches app.onboarding_offboarding_cases (its own terminal
  -- update runs last). Taking a `for update` lock on the case here FIRST,
  -- before calling app.cancel_approval_request (which locks the SAME
  -- approval-engine tables), would lock case-then-approval_request_steps --
  -- the exact REVERSE order of that call path, a real lock-order cycle.
  select * into v_case_plain from app.onboarding_offboarding_cases where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case_plain.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case_plain.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case_plain.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case_plain.status not in ('draft', 'active', 'pending_finalize_approval') then
    raise exception 'invalid_transition: case % is %, cannot be cancelled', p_case_id, v_case_plain.status using errcode = 'check_violation';
  end if;

  if v_case_plain.status = 'pending_finalize_approval' and v_case_plain.finalize_approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_case_plain.finalize_approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.onboarding_offboarding_cases
  set status = 'cancelled', cancel_reason = p_reason, cancelled_at = now()
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Review-round fix (CRITICAL, C-04 / dependent-in-flight-process-not-
  -- cancelled): revoke exactly the role grants THIS case's own completed
  -- access-provisioning requests produced -- see the migration header comment
  -- above for the full race-safety argument.
  for v_provisioning_request in
    select r.* from app.onboarding_task_provisioning_requests r
    where r.case_id = p_case_id and r.request_type = 'grant_access' and r.status = 'completed'
      and r.result_user_id is not null and coalesce(array_length(r.requested_role_version_ids, 1), 0) > 0
  loop
    foreach v_revoke_role_version_id in array v_provisioning_request.requested_role_version_ids loop
      for v_role_assignment in
        select * from app.role_assignments
        where tenant_id = v_case.tenant_id and role_version_id = v_revoke_role_version_id
          and auth_user_id = (select auth_user_id from app.users where id = v_provisioning_request.result_user_id)
          and status = 'active'
      loop
        perform app.revoke_role_assignment(v_role_assignment.id, 'onboarding/offboarding case ' || p_case_id::text || ' cancelled: ' || coalesce(p_reason, 'no reason supplied'), p_actor_label);
        v_revoked_count := v_revoked_count + 1;
      end loop;
    end loop;
  end loop;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, to_status, notes, actor_auth_user_id, actor_label)
  values (p_case_id, v_case.tenant_id, 'cancel', 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_onboarding_case',
    'app.onboarding_offboarding_cases', v_case.id, 'success', p_reason, null,
    app.onboarding_case_audit_projection(v_case) || jsonb_build_object('access_grants_revoked', v_revoked_count)
  );

  return v_case;
end;
$$;

comment on function app.cancel_onboarding_case is 'HRT-277 section 23, hardened by the Tier C review-round fix pass (20260730890000): cancelling never deletes the employee row it may have created/linked (section 24 "never loses required business history") -- a cancelled onboarding leaves the employee at whatever lifecycle_status it already reached; HR separately archives it via app.archive_employee_profile (HRT-274) if desired. Cancelling NOW also revokes any Platform role_assignments this case''s own completed access-provisioning requests already granted (never the underlying identity link itself) -- closes a live-reproduced gap where a cancelled case left a real, live Platform access grant behind.';

-- ===========================================================================
-- Fix 6 (MEDIUM, least-privilege): app.onboarding_task_provisioning_requests
-- and app.onboarding_case_events both carried a blanket, non-column-scoped
-- SELECT grant to `authenticated` -- unlike the deliberate column-restricted
-- grants this same migration's own header claims for exit_reason/
-- evidence_note/waive_reason. Neither table is read by ANY read RPC today
-- (both are write-path-only ledgers), so restricting the raw table grant
-- cannot regress any existing read path.
-- ===========================================================================

revoke select on app.onboarding_task_provisioning_requests from authenticated;
grant select (
  id, case_id, task_id, tenant_id, request_type, status, job_id, requested_by, requested_at, completed_at
) on app.onboarding_task_provisioning_requests to authenticated;

revoke select on app.onboarding_case_events from authenticated;
grant select (
  id, case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label, occurred_at
) on app.onboarding_case_events to authenticated;

comment on table app.onboarding_task_provisioning_requests is
  'HRT-277: the real audit/reconciliation ledger for every Platform-identity-authority write this capability performs -- never a fabricated success. job_id (nullable) references app.jobs.job_id (PLT-132, no FK -- app.jobs has no unique constraint on job_id alone suitable for a cross-schema FK here; correctness is enforced by only ever writing a job_id this same transaction just obtained from app.enqueue_job). Hardened by the Tier C review-round fix pass (20260730890000): target_auth_user_id/requested_role_version_ids/org_unit_id/result_user_id/failure_reason are column-restricted from the plain authenticated grant (identity-linkage/authority disclosure), matching the exit_reason/evidence_note/waive_reason discipline this migration''s own header claims.';
