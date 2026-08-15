-- Tier C review of the ISS-2026-065 closure (HRT-ISS-065-CLOSURE, 20260731310000)
-- -- per docs/standards/BUILD_EXECUTION_PROTOCOL.md 3.2 trigger 3 (writes
-- through Platform identity/access authority / RLS tenant primitives, since
-- this mechanism composes with HRT-295's already-VERIFIED identity coupling).
-- All four review lenses (spec-compliance, security, correctness, integration)
-- independently live-reproduced the SAME root cause in the shared writer this
-- migration adds, plus one independent, complementary gap each in the
-- maintenance sweep and the "as of" read. Never edits 20260731310000 itself (an
-- already-shipped migration in this same checkpoint) -- CREATE OR REPLACE
-- FUNCTION again (same signatures, body-only), next free timestamp, mirroring
-- the established 20260731280000 precedent for this exact situation.
--
-- ===========================================================================
-- Independently re-derived before writing this fix (never fixed from a report
-- alone), on fresh fixtures distinct from 20260731310000's own db-test file:
-- ===========================================================================
--
-- 1. **The shared writer bug (SPEC-COMPLIANCE/SECURITY/CORRECTNESS lenses, one
--    root cause).** app.record_employee_lifecycle_version's supersede-before-
--    insert loop resolved every touched live row purely by date-range math,
--    with zero awareness of what a row's own change_reason actually means.
--    Live-reproduced, own fixture (tenant fixv1):
--      - An HRS:Override actor schedules a real future termination 10 days
--        out; an HRS:Edit-only actor's completely unrelated, ordinary,
--        TODAY-effective transfer (a title change) silently flips the
--        scheduled termination to status='superseded' -- no error, no
--        warning, no audit distinction from an intentional cancellation.
--      - An employee suspended at day-10, legitimately reactivated at day-8
--        (confirmed active with live Platform access) has that access
--        silently revoked TODAY by a narrow, properly-authorized
--        app.suspend_employee call whose only intent was to fix the recorded
--        START DATE of the already-closed original suspension
--        (p_effective_date = current_date - 15).
--      - A terminate scheduled +5d followed by an unrelated transfer
--        scheduled +10d: the sweep's SECOND activation (the transfer)
--        silently reverts app.employees.lifecycle_status from 'terminated'
--        back to 'active', while app.users.status stays 'revoked' forever
--        (the sweep never calls app.transition_user_status for a 'transfer'
--        change_reason) -- a live, self-contradictory HR/Platform state. Worse:
--        this writes a real 'terminated' -> 'active' app.employee_lifecycle_
--        events row, and app.reactivate_user_after_rehire (HRT-295/
--        ISS-2026-108, already-VERIFIED) only checks for the EXISTENCE of such
--        a row -- calling it live against this exact employee succeeds,
--        restoring app.users.status to 'active' with zero genuine rehire ever
--        having occurred. Live-confirmed against this migration's own fresh
--        fixture below.
--    Root cause: a stale row's OWN change_reason is a genuinely distinct,
--    independently-decided lifecycle event whenever it is still OPEN
--    (effective_end_date IS NULL -- the currently- or future-governing
--    segment for THAT decision specifically). The two ways the original
--    supersede-before-insert loop could touch such a row carry genuinely
--    different risk, so the fix is DIRECTION-aware, not a single blanket
--    rule (an earlier draft of this fix tried one blanket rule and broke the
--    ordinary suspend->reactivate sequence -- caught by this checkpoint's own
--    re-verification against the existing db-test suite before shipping,
--    not accepted on faith):
--      - SUPERSEDING an open row that has not yet even STARTED as of the new
--        write's own date (a still-pending plan) is the dangerous direction
--        -- app.record_employee_lifecycle_version now refuses (lifecycle_
--        conflict, check_violation) unless change_reason matches (a genuine
--        reschedule/correction of that exact decision -- e.g. two backdated
--        transfer corrections in a row), the stale row is 'hire'/
--        'correction' (the genesis/draft-editing lineage every employee has
--        exactly one open row of at a time, never an independent "decision"
--        a later write could wrongly cancel), or the new write itself is
--        terminal ('terminate'/'archive', which by established, disclosed
--        precedent -- 20260731310000's own decision 3 -- always may close
--        out or cancel a pending plan).
--      - TRUNCATING an open row that already BEGAN before the new write's
--        own date is ordinary, expected chronological succession (e.g.
--        reactivate truncating the suspend it ends, or an ordinary transfer
--        truncating whatever came before it) -- always allowed regardless of
--        change_reason, EXCEPT when the row being truncated is an open-ended
--        TERMINAL state (terminate/archive): a non-terminal write must never
--        be allowed to truncate it, which would silently "resurrect" a
--        terminated/archived employee.
--    Fails loud instead of silently guessing wrong; HR must explicitly
--    resolve the conflicting version first. This SUBSUMES 20260731310000's
--    own disclosed "backdated correction voids any future-dated transition,
--    HR must re-review" limitation with something strictly safer: it now
--    only voids a LATER version genuinely superseded by the same-reason
--    correction (or a terminal write), never an unrelated, independently-
--    scheduled one -- see that migration's own header, decision 3, superseded
--    by this comment.
--
-- 2. **The sweep's blanket full-snapshot overwrite (INTEGRATION finding 1).**
--    app.activate_due_employee_lifecycle_transitions unconditionally wrote
--    EVERY captured snapshot field (lifecycle_status, employment_type, every
--    org unit, position_title, manager_employee_id, hire_date,
--    probation_end_date, employment_end_date) onto app.employees for ANY
--    change_reason -- including a scheduled 'transfer', whose own snapshot's
--    lifecycle_status field is simply whatever was true when it was SCHEDULED,
--    stale by the time it activates if the employee genuinely progressed
--    (submit/decide/activate, or app.rehire_employee -- none of which route
--    through this table, 20260731310000's own decision 9/10 explicit scope
--    trim) in the interim. Live-reproduced: draft employee schedules a
--    transfer 5 days out, then legitimately completes submit -> decide ->
--    activate (genuinely active); the sweep, once the transfer comes due,
--    silently reverts lifecycle_status back to 'draft'. Fix: the sweep's own
--    UPDATE is now change_reason-scoped -- it only ever writes the fields that
--    specific transition type actually intends to change (lifecycle_status
--    +*_reason only for suspend/reactivate/terminate/archive;
--    org/position/manager only for transfer; employment_end_date only for
--    terminate), mirroring the discipline every one of the 7 RPCs' own
--    IMMEDIATE-path UPDATE statements already established (each already only
--    touches its own relevant columns -- decision 8's own "byte-identical"
--    immediate branches, unedited, confirm this is the established, correct
--    shape). employment_type/hire_date/probation_end_date are dropped from the
--    sweep's UPDATE entirely -- no schedulable change_reason ever touches them
--    (only 'hire'/'correction' do, and those never produce a 'scheduled' row --
--    decision 5's own "always materializes immediately" carve-out). The
--    activation's own app.employee_lifecycle_events insert is fixed to match
--    (to_status reflects what ACTUALLY changed, not a blindly-trusted stale
--    snapshot field -- 'transfer' logs from_status=to_status, mirroring
--    app.transfer_employee's own immediate-path event-logging convention
--    exactly).
--
-- 3. **get_employee_lifecycle_as_of wrong for the ordinary, default case
--    (INTEGRATION findings 2/3).** Live-reproduced: (a) hire -> submit ->
--    decide -> activate, no further lifecycle RPC (the single most common
--    real-world state) -- app.employees.lifecycle_status='active', but
--    get_employee_lifecycle_as_of(today) returned 'draft' (the original hire
--    snapshot, never updated since none of submit/decide/activate write a new
--    version row). (b) terminate -> app.rehire_employee (a real, chartered
--    HRT-277 workflow, completely bypassing this table -- it is not one of the
--    7 RPCs and was never disclosed as a scope trim anywhere in 20260731310000
--    or its build log) -- app.employees.lifecycle_status='active' but
--    get_employee_lifecycle_as_of(today) returned 'terminated'. Both directly
--    contradict that function's own comment ("always correct regardless of
--    whether the sweep has run"). Fix (INTEGRATION's own offered option (b),
--    chosen over widening app.record_employee_lifecycle_version's own callers
--    to submit/decide/activate/rehire_employee, which would be a materially
--    larger, unbounded-scope change to functions this checkpoint's own
--    predecessor explicitly, deliberately left untouched -- decision 9/10):
--    for p_as_of >= current_date (today or any future date), app.employees'
--    own current-state columns are now the base truth -- always correct for
--    "right now" regardless of which RPC last touched them, covered or not. A
--    genuinely SCHEDULED row explicitly covering p_as_of is still preferred,
--    field-by-field, scoped to exactly what that change_reason changes
--    (mirrors fix 2 above exactly, applied on the read side -- never a blind
--    full-row override, which would silently reintroduce the identical
--    staleness bug via the read path instead of the write path). A PAST
--    p_as_of (< current_date) is completely unaffected -- app.employees cannot
--    answer that; the version table remains the only, unchanged source of
--    historical truth.
--
-- Every fix below is CREATE OR REPLACE FUNCTION with the IDENTICAL signature
-- 20260731310000 already shipped -- a pure body change, no DROP FUNCTION
-- needed (unlike 20260731310000's own 7 RPCs, which genuinely added
-- parameters). Existing grants on all three functions are preserved
-- automatically (CREATE OR REPLACE keeps the function's OID/ACL). No table,
-- RLS policy, or grant statement changes. Re-verified against
-- scripts/db-tests/hris-employee-master-lifecycle-effective-dating.sql's own
-- full existing assertion set (every scenario it already covers) plus new
-- coverage for exactly the four gaps above -- full detail and gate results in
-- docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md.

-- ===========================================================================
-- Fix 1: app.record_employee_lifecycle_version -- conflict-aware supersede.
-- ===========================================================================

create or replace function app.record_employee_lifecycle_version(
  p_tenant_id uuid,
  p_master_record_id uuid,
  p_lifecycle_status text,
  p_employment_type text,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_hire_date date,
  p_probation_end_date date,
  p_employment_end_date date,
  p_effective_date date,
  p_change_reason text,
  p_decided_reason text,
  p_materialize boolean,
  p_actor_label text
)
returns app.employee_lifecycle_versions
language plpgsql
as $$
declare
  v_stale app.employee_lifecycle_versions;
  v_previous_id uuid;
  v_new app.employee_lifecycle_versions;
begin
  for v_stale in
    select * from app.employee_lifecycle_versions
    where master_record_id = p_master_record_id
      and status in ('scheduled', 'active')
      and (effective_end_date is null or effective_end_date >= p_effective_date)
    order by effective_start_date
    for update
  loop
    -- Tier C follow-up fix (this migration's own header, item 1): direction-
    -- aware protection for an OPEN (effective_end_date IS NULL) stale row --
    -- the currently- or future-governing segment for ITS OWN change_reason's
    -- decision. The two buckets below carry genuinely different risk:
    if v_stale.effective_start_date >= p_effective_date then
      -- Bucket (a): the stale row has not even STARTED yet as of the new
      -- write's own date (a still-pending, not-yet-materialized plan) --
      -- entirely displacing it is the dangerous direction (SECURITY/SPEC-
      -- COMPLIANCE lenses' own live reproductions: a scheduled future
      -- termination silently cancelled by an unrelated same-day transfer; a
      -- currently-active reactivation silently reverted by a backdated
      -- correction to an unrelated, already-closed suspend event). Only
      -- silently supersede it when reasons match (a genuine reschedule/
      -- correction of that exact decision), the stale row is 'hire'/
      -- 'correction' (the genesis/draft-editing lineage every employee has
      -- exactly one open row of at a time, never an independent "decision" a
      -- later write could wrongly cancel), the new write is itself terminal
      -- ('terminate'/'archive', which by established, disclosed precedent --
      -- 20260731310000's own decision 3 -- always may close out or cancel a
      -- pending plan), or the stale row's own effective_start_date EQUALS the
      -- new write's (same calendar day -- effective_date has date, not
      -- timestamp, granularity, so a genuinely later real-time call sharing
      -- today's date with an earlier one -- e.g. an ordinary immediate
      -- suspend followed by an ordinary immediate reactivate later the same
      -- day -- is a normal, expected same-day sequence, not a still-pending
      -- FUTURE plan; caught and fixed against this checkpoint's own full
      -- existing db-test suite before shipping, not accepted on faith).
      -- Anything else fails loud instead of silently guessing.
      if v_stale.effective_start_date > p_effective_date
         and v_stale.effective_end_date is null
         and v_stale.change_reason is distinct from p_change_reason
         and v_stale.change_reason not in ('hire', 'correction')
         and p_change_reason not in ('terminate', 'archive')
      then
        raise exception 'lifecycle_conflict: employee % already has a % lifecycle version (id %, effective from % with no end date) not yet in effect -- this % change (effective %) cannot silently supersede it; resolve that version explicitly first (e.g. via its own governing action) before retrying', p_master_record_id, v_stale.change_reason, v_stale.id, v_stale.effective_start_date, p_change_reason, p_effective_date
          using errcode = 'check_violation';
      end if;
      -- Entirely displaced -- void it, dates left untouched for audit.
      update app.employee_lifecycle_versions set status = 'superseded' where id = v_stale.id;
    else
      -- Bucket (b): the stale row already BEGAN before the new write's own
      -- date -- ordinary chronological succession (the new write picks up
      -- where the old one left off), always safe and expected regardless of
      -- change_reason (this is exactly how a normal status timeline
      -- advances -- e.g. reactivate truncating the suspend it ends) UNLESS
      -- the stale row is an open-ended TERMINAL state (terminate/archive): a
      -- non-terminal write must never be allowed to truncate it, which would
      -- silently "resurrect" a terminated/archived employee (CORRECTNESS
      -- lens's own live reproduction: a later-scheduled, unrelated transfer
      -- truncating an already-scheduled termination, reverting lifecycle_
      -- status back to active once both activate).
      if v_stale.effective_end_date is null
         and v_stale.change_reason in ('terminate', 'archive')
         and p_change_reason not in ('terminate', 'archive')
      then
        raise exception 'lifecycle_conflict: employee % has an open-ended % lifecycle version (id %, effective from %) -- a non-terminal % change (effective %) cannot silently truncate a terminal state; resolve that version explicitly first (e.g. via app.rehire_employee) before retrying', p_master_record_id, v_stale.change_reason, v_stale.id, v_stale.effective_start_date, p_change_reason, p_effective_date
          using errcode = 'check_violation';
      end if;
      -- Straddles the new effective date -- truncate its own trailing edge;
      -- it remains a genuinely correct historical fact for the sub-range it
      -- still covers, status unchanged.
      update app.employee_lifecycle_versions set effective_end_date = p_effective_date - 1 where id = v_stale.id;
      v_previous_id := v_stale.id;
    end if;
  end loop;

  insert into app.employee_lifecycle_versions (
    tenant_id, master_record_id, lifecycle_status, employment_type,
    company_org_unit_id, branch_org_unit_id, department_org_unit_id, position_title, manager_employee_id,
    hire_date, probation_end_date, employment_end_date, effective_start_date, status, change_reason,
    decided_by, decided_reason, previous_version_id, materialized_at, created_by
  ) values (
    p_tenant_id, p_master_record_id, p_lifecycle_status, p_employment_type,
    p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
    p_hire_date, p_probation_end_date, p_employment_end_date, p_effective_date,
    case when p_materialize then 'active' else 'scheduled' end, p_change_reason,
    p_actor_label, p_decided_reason, v_previous_id, case when p_materialize then now() else null end, p_actor_label
  )
  returning * into v_new;

  return v_new;
end;
$$;

comment on function app.record_employee_lifecycle_version is
  'ISS-2026-065 closure (20260731310000), Tier C follow-up fix (20260731320000): the single supersede-then-insert writer for app.employee_lifecycle_versions, called from every one of the 7 lifecycle-transition RPCs. Direction-aware protection for an OPEN stale row (this migration''s own header, item 1): refuses (lifecycle_conflict) to silently SUPERSEDE a not-yet-started, differently-reasoned open row unless it is hire/correction or the new write is terminal (terminate/archive); refuses to silently TRUNCATE an open-ended TERMINAL (terminate/archive) row via any non-terminal write. Ordinary chronological succession (truncating a non-terminal open row that already began) remains unrestricted, regardless of change_reason. service_role only -- never a public entry point.';

-- ===========================================================================
-- Fix 2: app.activate_due_employee_lifecycle_transitions -- change_reason-
-- scoped materialization (never a blanket full-snapshot overwrite).
-- ===========================================================================

create or replace function app.activate_due_employee_lifecycle_transitions(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate record;
  v_employee app.employees;
  v_version app.employee_lifecycle_versions;
  v_apply_failed boolean;
  v_count integer := 0;
  v_skipped integer := 0;
  v_skipped_ids uuid[] := '{}';
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_candidate in
    select id, master_record_id from app.employee_lifecycle_versions
    where tenant_id = p_tenant_id and status = 'scheduled' and effective_start_date <= current_date
    order by effective_start_date
  loop
    -- C-21 lock order: app.employees FIRST, then the specific version row --
    -- the SAME order every write RPC above uses (it locks app.employees before
    -- ever calling app.record_employee_lifecycle_version, the only other place
    -- that locks version rows). See 20260731310000's own header, decision 7.
    select * into v_employee from app.employees where master_record_id = v_candidate.master_record_id for update;
    select * into v_version from app.employee_lifecycle_versions where id = v_candidate.id for update;

    -- Idempotent / defensive re-check under lock -- a concurrent sweep call, or an
    -- earlier iteration of THIS SAME sweep touching this employee via a
    -- since-superseding row, may have already resolved this one.
    if v_version.status <> 'scheduled' or v_version.effective_start_date > current_date then
      continue;
    end if;

    v_apply_failed := false;
    begin
      -- Re-validates cycle-freedom immediately before writing manager_employee_id
      -- -- the same defect class, and the same fix shape, app.sync_employee_
      -- current_assignment_cache's own "CRITICAL review-round fix" (HRT-275)
      -- already established.
      if v_version.manager_employee_id is not null then
        perform app.assert_no_employee_manager_cycle(v_version.master_record_id, v_version.manager_employee_id);
      end if;

      -- Tier C follow-up fix (this migration's own header, item 2): scoped to
      -- exactly the fields each change_reason actually intends to change --
      -- mirrors every one of the 7 RPCs' own IMMEDIATE-path UPDATE statements
      -- (each already scoped this way, unedited by this migration). Never a
      -- blanket full-snapshot overwrite -- that silently reverted a genuinely
      -- active employee back to a stale 'draft'/whatever-else snapshot when an
      -- unrelated, uncovered RPC (submit/decide/activate/rehire_employee) had
      -- legitimately progressed lifecycle_status in the interim.
      -- employment_type/hire_date/probation_end_date are never written here --
      -- no schedulable change_reason (suspend/reactivate/terminate/archive/
      -- transfer) ever touches them (only hire/correction do, and those never
      -- produce a 'scheduled' row -- decision 5's own always-immediate carve-out).
      update app.employees
      set lifecycle_status = case
            when v_version.change_reason in ('suspend', 'reactivate', 'terminate', 'archive') then v_version.lifecycle_status
            else lifecycle_status
          end,
          company_org_unit_id = case when v_version.change_reason = 'transfer' then v_version.company_org_unit_id else company_org_unit_id end,
          branch_org_unit_id = case when v_version.change_reason = 'transfer' then v_version.branch_org_unit_id else branch_org_unit_id end,
          department_org_unit_id = case when v_version.change_reason = 'transfer' then v_version.department_org_unit_id else department_org_unit_id end,
          position_title = case when v_version.change_reason = 'transfer' then v_version.position_title else position_title end,
          manager_employee_id = case when v_version.change_reason = 'transfer' then v_version.manager_employee_id else manager_employee_id end,
          employment_end_date = case when v_version.change_reason = 'terminate' then v_version.employment_end_date else employment_end_date end,
          suspend_reason = case
            when v_version.change_reason = 'suspend' then v_version.decided_reason
            when v_version.change_reason in ('reactivate', 'terminate') then null
            else suspend_reason
          end,
          terminate_reason = case when v_version.change_reason = 'terminate' then v_version.decided_reason else terminate_reason end,
          archive_reason = case when v_version.change_reason = 'archive' then v_version.decided_reason else archive_reason end,
          leave_reason = case when v_version.change_reason = 'terminate' then null else leave_reason end
      where master_record_id = v_version.master_record_id;
    exception
      when check_violation or no_data_found then
        v_apply_failed := true;
        v_skipped := v_skipped + 1;
        v_skipped_ids := array_append(v_skipped_ids, v_version.id);
    end;

    if v_apply_failed then
      continue;
    end if;

    update app.employee_lifecycle_versions set status = 'active', materialized_at = now() where id = v_version.id;

    -- HRT-295 identity-coupling composition (20260731310000's own header,
    -- decision 8): the deferred Platform-identity transition fires NOW, at
    -- activation, never earlier. Unchanged by this migration -- already
    -- correctly scoped to change_reason (never fires for 'transfer'/'archive').
    if v_version.change_reason = 'suspend' and v_employee.user_id is not null then
      perform app.transition_user_status(v_employee.user_id, 'suspended', v_version.decided_reason, p_actor_label);
    elsif v_version.change_reason = 'terminate' and v_employee.user_id is not null then
      perform app.transition_user_status(v_employee.user_id, 'revoked', v_version.decided_reason, p_actor_label);
    elsif v_version.change_reason = 'reactivate' and v_employee.user_id is not null then
      if (select status from app.users where id = v_employee.user_id) = 'suspended' then
        perform app.transition_user_status(v_employee.user_id, 'active', 'employee reactivated: scheduled end of suspension', p_actor_label);
      end if;
    end if;

    -- Tier C follow-up fix (this migration's own header, item 2): to_status now
    -- reflects what ACTUALLY changed on app.employees, not a blindly-trusted
    -- stale snapshot field -- 'transfer' (and any other reason that does not
    -- itself change lifecycle_status) logs from_status = to_status, mirroring
    -- app.transfer_employee's own immediate-path event-logging convention
    -- exactly (20260731310000, unedited).
    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (
      v_version.tenant_id, v_version.master_record_id, v_employee.lifecycle_status,
      case when v_version.change_reason in ('suspend', 'reactivate', 'terminate', 'archive') then v_version.lifecycle_status else v_employee.lifecycle_status end,
      v_version.decided_reason,
      jsonb_build_object('event', 'scheduled_activation', 'version_id', v_version.id, 'change_reason', v_version.change_reason),
      p_actor_auth_user_id, p_actor_label
    );

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_due_employee_lifecycle_transitions',
      'app.employees', p_tenant_id, 'success', null, null, jsonb_build_object('activated_count', v_count)
    );
  end if;

  if v_skipped > 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_due_employee_lifecycle_transitions',
      'app.employees', p_tenant_id, 'failure',
      'cyclic_reporting_line or invalid org unit detected during maintenance sweep -- transition(s) left unactivated; app.employees remains at its prior value for the affected employee(s) until the conflict is resolved and the sweep is retried',
      null, jsonb_build_object('skipped_count', v_skipped, 'skipped_version_ids', to_jsonb(v_skipped_ids))
    );
  end if;

  return v_count;
end;
$$;

comment on function app.activate_due_employee_lifecycle_transitions is
  'ISS-2026-065 closure (20260731310000), Tier C follow-up fix (20260731320000): sweeps app.employee_lifecycle_versions rows whose effective_start_date has arrived but which are still status=''scheduled'', and activates them -- mirrors app.activate_due_employee_position_assignments (HRT-275) exactly, including its own "skip a cyclic row, disclose via a failure audit event, never abort the whole sweep" discipline. The UPDATE onto app.employees is change_reason-scoped (this migration''s own header, item 2) -- never a blanket full-snapshot overwrite, which could silently revert fields an unrelated, uncovered RPC (app.submit_employee_for_approval/app.decide_employee_approval/app.activate_employee/app.rehire_employee) had legitimately changed in the interim. HRS:Override-gated, idempotent, NOT wired to any live scheduler (no pg_cron or equivalent exists anywhere in this repository -- ISS-2026-015''s own standing, disclosed gap) -- disclosed as NOT_RUN in docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md, callable on demand today. Returns the count of rows genuinely activated.';

-- ===========================================================================
-- Fix 3: app.get_employee_lifecycle_as_of -- app.employees is the base truth
-- for "today or later"; a genuinely scheduled row is still preferred,
-- change_reason-scoped, exactly like fix 2 above.
-- ===========================================================================

create or replace function app.get_employee_lifecycle_as_of(p_master_record_id uuid, p_actor_auth_user_id uuid, p_as_of date default current_date)
returns table (
  id uuid, master_record_id uuid, lifecycle_status text, employment_type text,
  company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid,
  position_title text, manager_employee_id uuid, hire_date date, probation_end_date date, employment_end_date date,
  effective_start_date date, effective_end_date date, status text, change_reason text,
  decided_by text, decided_at timestamptz, decided_reason text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_caller_user_id uuid;
  v_is_self boolean;
  v_unmasked boolean;
begin
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

  if p_as_of >= current_date then
    -- Tier C follow-up fix (this migration's own header, item 3):
    -- app.employee_lifecycle_versions is only ever written by the 7 RPCs
    -- 20260731310000 named -- app.submit_employee_for_approval/app.decide_
    -- employee_approval/app.activate_employee/app.rehire_employee (and app.
    -- start_employee_leave/app.end_employee_leave) mutate app.employees.
    -- lifecycle_status directly and were never routed through it (explicitly
    -- out of scope, 20260731310000's own decision 9/10). Trusting the version
    -- table alone for "today or later" was provably wrong for the ordinary
    -- hire->active flow (no version row ever covers 'today' once submit/
    -- decide/activate run) and for the terminate->rehire cycle (a stale,
    -- never-closed 'terminated' row outliving a real rehire). app.employees'
    -- own current-state columns are the single reliably-correct source for
    -- "right now" -- kept correct by EVERY mutating RPC, not merely the 7
    -- wired into this table. A genuinely SCHEDULED row explicitly covering
    -- p_as_of (today, if overdue and not yet swept, or a real future date) is
    -- still preferred, field-by-field, scoped to exactly what that
    -- change_reason actually changes -- mirrors app.activate_due_employee_
    -- lifecycle_transitions' own change_reason-scoped write (fix 2 above)
    -- applied on the read side; never a blind full-row override, which would
    -- reintroduce the identical staleness bug via the read path instead of
    -- the write path. A PAST p_as_of (< current_date) is completely
    -- unaffected -- app.employees cannot answer that, so the version table
    -- (the only source of historical truth) is used exactly as before, below.
    return query
    select
      v.id, e.master_record_id,
      case when v.change_reason in ('suspend', 'reactivate', 'terminate', 'archive') then v.lifecycle_status else e.lifecycle_status end,
      e.employment_type,
      case when v.change_reason = 'transfer' then v.company_org_unit_id else e.company_org_unit_id end,
      case when v.change_reason = 'transfer' then v.branch_org_unit_id else e.branch_org_unit_id end,
      case when v.change_reason = 'transfer' then v.department_org_unit_id else e.department_org_unit_id end,
      case when v.change_reason = 'transfer' then v.position_title else e.position_title end,
      case when v.change_reason = 'transfer' then v.manager_employee_id else e.manager_employee_id end,
      e.hire_date, e.probation_end_date,
      case when v.change_reason = 'terminate' then v.employment_end_date else e.employment_end_date end,
      v.effective_start_date, v.effective_end_date, v.status, v.change_reason,
      v.decided_by, v.decided_at, case when v_unmasked then v.decided_reason else null end, v.record_version
    from app.employees e
    left join app.employee_lifecycle_versions v
      on v.master_record_id = e.master_record_id and v.status = 'scheduled' and v.validity_range @> p_as_of
    where e.master_record_id = p_master_record_id;
    return;
  end if;

  return query
  select
    v.id, v.master_record_id, v.lifecycle_status, v.employment_type,
    v.company_org_unit_id, v.branch_org_unit_id, v.department_org_unit_id,
    v.position_title, v.manager_employee_id, v.hire_date, v.probation_end_date, v.employment_end_date,
    v.effective_start_date, v.effective_end_date, v.status, v.change_reason,
    v.decided_by, v.decided_at, case when v_unmasked then v.decided_reason else null end, v.record_version
  from app.employee_lifecycle_versions v
  where v.master_record_id = p_master_record_id and v.status in ('scheduled', 'active') and v.validity_range @> p_as_of;
end;
$$;

comment on function app.get_employee_lifecycle_as_of is
  'ISS-2026-065 closure (20260731310000), Tier C follow-up fix (20260731320000): reconstructs what an employee''s lifecycle state genuinely was/is/will be on any given date. For a PAST p_as_of (< current_date), reads app.employee_lifecycle_versions'' own validity_range directly, unchanged. For p_as_of >= current_date (today or later), app.employees'' own current-state columns are the base truth (always correct, regardless of which RPC last touched them -- covered by this table or not), field-by-field overridden by a genuinely SCHEDULED version row when one explicitly covers that date, scoped to exactly what that change_reason changes (this migration''s own header, item 3). decided_reason masked to null unless self or HRS:View personal data, mirroring app.get_employee_profile. Distinct from the pre-existing app.get_employee_lifecycle_history (an append-only event log requiring a manual linear scan) -- left unmodified.';
