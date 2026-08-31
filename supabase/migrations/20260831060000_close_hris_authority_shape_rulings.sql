-- Closes three HRIS authority-shape findings that had each been deferred, three passes running,
-- for the same reason: "this needs a design ruling, and a bounded fix pass may not make one."
-- ADR-0027 Part A gives this pass that mandate. All three are the same defect in different
-- clothes -- the data model names an owner/approver, and the authorization layer never reads it.
--
--   ISS-2026-068  a hiring manager has no self-scoped read of their own vacancies, so the only
--                 way to see their own is a tenant-wide HRS:View that also shows every other
--                 vacancy, candidate, application and offer in the tenant.
--   ISS-2026-071  app.onboarding_case_tasks.owner_auth_user_id is written, displayed, and never
--                 checked -- completion authority is uniformly tenant-wide HRS:Edit.
--   ISS-2026-073  Prompt 277 SS21/SS25 name an "approved direct hire" precondition. No field, table,
--                 or approval call representing one exists anywhere.
--
-- ===========================================================================
-- ISS-2026-068 -- the hiring-manager half of Prompt 276 SS26, built to match the interviewer half
-- ===========================================================================
--
-- The interviewer half is real: app.get_my_assigned_interviews is self-scoped, identity-matched,
-- and requires zero HRS permission. This is that function's own shape, applied to the other role
-- the same sentence names. It is deliberately additive: no existing read RPC is narrowed, because
-- narrowing app.list_job_vacancies would break every genuine HRS:View recruiter, who is supposed
-- to see the whole pipeline. What was missing was the NARROW path, not a wide one that should not
-- exist.

create function app.list_my_hiring_manager_vacancies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.job_vacancies
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Explicit tenant-membership guard before anything else, and a silent empty return rather than
  -- a raise -- byte-for-byte the shape app.get_my_assigned_interviews established, so a caller
  -- with no employee profile learns nothing about whether the tenant has vacancies at all.
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_employee_id := app.resolve_actor_employee_id(p_tenant_id, p_actor_auth_user_id);
  if v_employee_id is null then
    return;
  end if;

  return query
  select v.*
  from app.job_vacancies v
  where v.tenant_id = p_tenant_id
    and v.hiring_manager_employee_id = v_employee_id
  order by v.created_at desc, v.id;
end;
$$;

comment on function app.list_my_hiring_manager_vacancies is
  'ISS-2026-068: the hiring-manager half of Prompt 276 SS26 ("hiring managers/interviewers see assigned slices"). Self-scoped and identity-matched, requiring zero HRS permission -- the same shape app.get_my_assigned_interviews already gives interviewers. Reads app.job_vacancies.hiring_manager_employee_id, which until this migration was written and validated at draft time but never read back by any read RPC. Deliberately additive: app.list_job_vacancies is NOT narrowed, because a genuine HRS:View recruiter is supposed to see the whole pipeline; what was missing was the narrow path, not the wide one.';

revoke execute on function app.list_my_hiring_manager_vacancies(uuid, uuid) from public;
grant execute on function app.list_my_hiring_manager_vacancies(uuid, uuid) to authenticated, service_role;

-- public.* wrapper, security mode matching the app.* function exactly (RGL-394 Option 2). app is
-- not exposed to PostgREST, so without this the function is unreachable from the application.
create function public.list_my_hiring_manager_vacancies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.job_vacancies
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_my_hiring_manager_vacancies(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_my_hiring_manager_vacancies(uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_my_hiring_manager_vacancies, never a reimplementation.';

revoke execute on function public.list_my_hiring_manager_vacancies(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_my_hiring_manager_vacancies(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- ISS-2026-071 -- the task's own named owner may complete the task
-- ===========================================================================
--
-- THE RULING, AND WHICH DIRECTION IT GOES
--
--   Two fixes were available and they point opposite ways. (a) TIGHTEN: require that an HRS:Edit
--   holder also match the task's owner_type/owner_auth_user_id. (b) WIDEN: let the named owner
--   complete their own task without holding HRS:Edit.
--
--   (a) was rejected on the evidence, not on effort. HRS:Edit is a genuine tenant-scoped HR
--   permission a tenant grants deliberately; an HR coordinator closing out an IT-owned task on
--   IT's behalf is ordinary, correct HR work, and every such act is already audited under the
--   acting identity. Tightening would break that with no security gain -- there is no
--   cross-tenant or unauthenticated exposure here to close.
--
--   (b) is what the finding actually describes as missing, and it is what Prompt 277's own
--   checklist model is built around: a Finance or IT task owner is named on the row precisely so
--   that person can act on it. Today they cannot, unless a tenant hands them blanket HRS:Edit --
--   which is strictly MORE access than this migration grants them.
--
-- SCOPE, KEPT DELIBERATELY NARROW
--
--   The owner path applies to app.complete_onboarding_task ONLY. Not assign (re-routing someone
--   else's work is a coordination act, not an ownership one), not reopen, not waive or cancel
--   (HRS:Override, unchanged), and not the access_provisioning/revocation RPCs, which mint and
--   destroy real platform authority and keep their existing HRS gate untouched. The shared
--   app.resolve_onboarding_case_task_for_write preamble is NOT modified -- every other caller
--   keeps the exact authority it had before this migration.
--
--   A path whose ONLY credential is "this row names you" has to prove the caller really is that
--   session identity, or the claim is just a parameter anyone could pass. That proof is already
--   in place and does not need adding here: app.evaluate_permission itself calls
--   app.assert_actor_is_session_identity (ATW-031 / ISS-2026-017), and this function calls
--   evaluate_permission unconditionally, BEFORE the owner branch is ever reached. So an
--   authenticated session whose auth.uid() does not match p_actor_auth_user_id is rejected on the
--   permission call, never reaching the owner comparison. Adding a second call here would be
--   redundant, and stating it that way is more useful than a duplicate guard.

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
  v_decision app.rbac_decision;
begin
  -- p_required_action => null: the preamble still resolves the case and task, still enforces
  -- tenant membership, still takes both locks in its own documented order, and still enforces
  -- the case-is-active gate. Only the permission decision moves here, because only here does a
  -- second, narrower authority path exist.
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, null);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    -- coalesce, not a bare comparison: owner_auth_user_id is nullable, and `null = x` is null,
    -- which would make `not (...)` null and let an UNASSIGNED task be completed by anyone.
    if not coalesce(v_task.owner_auth_user_id = p_actor_auth_user_id, false) then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant % and is not the named owner of task %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id, p_task_id
        using errcode = 'insufficient_privilege';
    end if;
    -- No app.assert_actor_is_session_identity call here on purpose: app.evaluate_permission above
    -- already made it, unconditionally, before this branch is reachable. See the header.
  end if;

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

comment on function app.complete_onboarding_task is
  'HRT-277, hardened by the Tier C review-round fix pass (20260730890000) and again by ISS-2026-071 (20260831060000). A task_type=''handoff'' completion REQUIRES a non-null evidence note or file; access-provisioning/revocation are rejected outright (their own dedicated RPCs). ISS-2026-071 ruling: completion authority is HRS:Edit for the tenant OR being the task''s own named owner_auth_user_id. The owner path is genuinely identity-bound without a second guard: app.evaluate_permission calls app.assert_actor_is_session_identity (ATW-031) and runs unconditionally before the owner comparison, so a session claiming another identity is rejected first. The owner path is scoped to completion alone: assign, reopen, waive, cancel and the two access RPCs keep their existing HRS gates, and the shared app.resolve_onboarding_case_task_for_write preamble is unmodified, so no other caller''s authority changed.';

-- ===========================================================================
-- ISS-2026-073 -- an approved direct hire, made real
-- ===========================================================================
--
-- WHERE THE GATE BELONGS, READ FROM THE SPEC RATHER THAN GUESSED
--
--   SS21 says "HR starts from an accepted offer or approved direct hire", which reads like a
--   start-time gate. SS25 is the operative one and is explicit about timing: "Validate source
--   candidate/direct-hire approval ... BEFORE completion/finalization." The gate belongs at
--   finalization. That also makes it a workable process: HR opens the case and runs the checklist
--   while the approval is being obtained, rather than being blocked at the first step.
--
--   The job_offer path already works this way implicitly -- HRT-276's own offer-approval routing
--   gates the offer reaching status='accepted' before start_onboarding_case will take it. Only
--   direct_hire was unguarded.
--
-- WHY A CHECK CONSTRAINT AND NOT A FUNCTION EDIT
--
--   The obvious fix is a branch inside app.submit_onboarding_case_for_finalize_approval. A
--   constraint is strictly stronger: it holds for every path into those two statuses, including
--   any future RPC, a service_role script, or a direct UPDATE. It also mirrors this table's own
--   established shape exactly -- onboarding_offboarding_cases_exit_reason_check is the identical
--   "for this case shape, in these statuses, this column must be present" pattern.
--
--   NOT VALID + VALIDATE, in that order, deliberately: adding the constraint takes only a brief
--   lock and cannot fail on live rows, and the separate VALIDATE then reports honestly whether
--   any already-finalized direct_hire case predates the rule. If one does, the migration fails
--   loudly here rather than silently grandfathering it.

alter table app.onboarding_offboarding_cases
  add column if not exists direct_hire_approved_by_auth_user_id uuid references auth.users (id),
  add column if not exists direct_hire_approved_at timestamptz,
  add column if not exists direct_hire_approval_note text;

comment on column app.onboarding_offboarding_cases.direct_hire_approved_by_auth_user_id is
  'ISS-2026-073: the identity that recorded the Prompt 277 SS21/SS25 "approved direct hire" precondition, via app.record_direct_hire_approval. Null on every non-direct_hire case.';
comment on column app.onboarding_offboarding_cases.direct_hire_approved_at is
  'ISS-2026-073: when the direct-hire approval was recorded. onboarding_offboarding_cases_direct_hire_approval_check makes this mandatory before a direct_hire case may reach pending_finalize_approval or finalized.';
comment on column app.onboarding_offboarding_cases.direct_hire_approval_note is
  'ISS-2026-073: the approver''s own free-text justification, required by app.record_direct_hire_approval. Free text, so it is never used as an authority input -- only as evidence.';

alter table app.onboarding_offboarding_cases
  add constraint onboarding_offboarding_cases_direct_hire_approval_check
  check (
    source_type <> 'direct_hire'
    or status not in ('pending_finalize_approval', 'finalized')
    or direct_hire_approved_at is not null
  ) not valid;

alter table app.onboarding_offboarding_cases
  validate constraint onboarding_offboarding_cases_direct_hire_approval_check;

create function app.record_direct_hire_approval(
  p_case_id uuid, p_expected_version integer, p_note text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_case app.onboarding_offboarding_cases;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  -- HRS:Approve, not HRS:Edit. The whole point of the finding is that starting a direct hire and
  -- approving one were the same permission; if this RPC took HRS:Edit it would change nothing.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case.source_type <> 'direct_hire' then
    raise exception 'not_a_direct_hire_case: case % has source_type %, a direct-hire approval does not apply', p_case_id, v_case.source_type
      using errcode = 'check_violation';
  end if;

  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_case.status not in ('draft', 'active') then
    raise exception 'invalid_transition: case % is %, a direct-hire approval can only be recorded before finalize submission', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  if v_case.direct_hire_approved_at is not null then
    raise exception 'already_approved: case % was already approved as a direct hire at %', p_case_id, v_case.direct_hire_approved_at
      using errcode = 'check_violation';
  end if;

  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'approval_note_required: recording a direct-hire approval requires a justification note' using errcode = 'check_violation';
  end if;

  update app.onboarding_offboarding_cases
  set direct_hire_approved_by_auth_user_id = p_actor_auth_user_id,
      direct_hire_approved_at = now(),
      direct_hire_approval_note = trim(p_note)
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label, notes)
  values (v_case.id, v_case.tenant_id, 'direct_hire_approved', v_case.status, v_case.status, p_actor_auth_user_id, p_actor_label, trim(p_note));

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_direct_hire_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null,
    jsonb_build_object('case_id', v_case.id, 'source_type', v_case.source_type, 'approved_at', v_case.direct_hire_approved_at)
  );

  return v_case;
end;
$$;

comment on function app.record_direct_hire_approval is
  'ISS-2026-073: makes Prompt 277 SS21/SS25''s "approved direct hire" precondition real. Requires HRS:Approve -- deliberately NOT HRS:Edit, since the finding is precisely that starting and approving a direct hire were the same permission. Recordable only while the case is draft or active, once per case, with a mandatory justification note, and it writes both an app.onboarding_case_events row and an audit event. Enforcement is not in this function: onboarding_offboarding_cases_direct_hire_approval_check makes the approval mandatory before ANY path can move a direct_hire case to pending_finalize_approval or finalized. Not enforced, and said plainly rather than implied: segregation of duties between the case initiator and the approver. app.onboarding_offboarding_cases records its initiator as a text label (initiated_by), not an identity, so "the approver must not be the initiator" cannot be checked reliably here; a tenant that needs it must enforce it by not granting one person both HRS:Create and HRS:Approve.';

revoke execute on function app.record_direct_hire_approval(uuid, integer, text, uuid, text) from public;
grant execute on function app.record_direct_hire_approval(uuid, integer, text, uuid, text) to authenticated, service_role;

create function public.record_direct_hire_approval(
  p_case_id uuid, p_expected_version integer, p_note text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.record_direct_hire_approval(p_case_id, p_expected_version, p_note, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.record_direct_hire_approval(uuid, integer, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.record_direct_hire_approval, never a reimplementation.';

revoke execute on function public.record_direct_hire_approval(uuid, integer, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.record_direct_hire_approval(uuid, integer, text, uuid, text) to authenticated, service_role;

comment on table app.onboarding_offboarding_cases is
  'HRT-277: the workflow case root. employee_master_record_id is set exactly once, at start, and is idempotent for source_type=''job_offer'' (source_job_offer_id is unique-when-set, so retrying app.start_onboarding_case against the same accepted offer can never create a second case OR a second employee -- acceptance criterion 1). checklist_template_version_id is locked in at start (RPD-040). exit_reason is column-restricted (decision 4). ISS-2026-073 (20260831060000): a source_type=''direct_hire'' case must carry a recorded direct_hire_approved_at before it may reach pending_finalize_approval or finalized -- enforced declaratively by onboarding_offboarding_cases_direct_hire_approval_check, so it holds for every path including future RPCs and direct service_role UPDATEs, not only for app.submit_onboarding_case_for_finalize_approval.';
