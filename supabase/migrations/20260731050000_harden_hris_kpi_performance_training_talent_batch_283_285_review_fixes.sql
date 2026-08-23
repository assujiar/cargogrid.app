-- Tier C batch review-round fix pass for the combined 283-285 batch
-- (CG-S12-HRT-011/012/013 -- KPI/Performance, Training/Talent, ESS/MSS
-- Self-Service). Additive only: neither 20260731030000
-- (create_hris_kpi_performance) nor 20260731040000
-- (create_hris_training_talent) is edited in place, per AGENTS.md. Every
-- fix below was independently re-derived live against a disposable
-- Postgres 16 database (all 205 pre-existing migrations applied) before
-- being written here, per docs/standards/BUILD_EXECUTION_PROTOCOL.md
-- section 5.3 -- never fixed from a lens citation alone.
--
-- Fixes, by finding:
--
-- 1. (CRITICAL, correctness lens, confirmed) -- 7 read RPCs across
--    HRT-283/284 raise "column reference \"id\" is ambiguous" on EVERY
--    call, unconditionally: each has a preliminary, unqualified
--    `where id = p_...` lookup that collides with the OUT parameter `id`
--    implicitly created by its own `returns table (id uuid, ...)` clause.
--    A full, mechanical sweep of every RETURNS TABLE(id ...) function in
--    both migrations (134 functions total) confirms these are the ONLY 7
--    instances of the shape -- re-derived independently, not merely
--    accepted from the lens's own list. Fixed by aliasing the source
--    table in each offending SELECT, matching the alias-qualified style
--    every sibling list/get RPC in both migrations already uses.
--
-- 2. (HIGH, correctness lens, confirmed) -- app.enqueue_job's
--    check-then-insert on (tenant_id, idempotency_key) has no exception
--    handler around the INSERT; two genuinely concurrent callers with the
--    SAME idempotency key both pass the pre-insert "not found" check, one
--    wins the insert, the other gets a raw, unclassified Postgres 23505
--    instead of the promised idempotent replay. Live-reproduced with two
--    real concurrent OS psql processes calling
--    app.run_training_certificate_expiry_batch (HRT-284) with the same
--    period label. app.enqueue_job itself predates this batch (shared
--    generic-job infra, ATW-031/032 vintage) but HRT-284 is what newly
--    exercises it under real concurrency with a period-derived
--    idempotency key and a comment asserting an idempotency guarantee
--    that concurrency actually broke -- fixed here, at the shared
--    primitive, so every current and future caller of app.enqueue_job
--    (not just HRT-284's own two call sites) gets the fix in one place.
--
-- 3. (MEDIUM, security lens, confirmed) -- the RLS SELECT policies on
--    app.performance_reviewer_assignments and
--    app.performance_calibration_adjustments (HRT-283) call
--    app.evaluate_permission(...) directly inline inside USING(...).
--    app.evaluate_permission is granted EXECUTE to service_role only, not
--    authenticated, so any genuine authenticated actor gets a hard
--    "permission denied for function evaluate_permission" on a raw table
--    SELECT against either table -- fails closed (no data leaked;
--    confirmed no other authenticated actor can read past this either),
--    but breaks the raw-table read path these tables' own
--    `grant select ... to authenticated` provisions for, and matches this
--    migration's own header comment stating a bare invoker-side call
--    "fails inside an RLS policy expression". Every other policy in this
--    same migration (and the sibling HRT-284/HRT-282 migrations) instead
--    calls a SECURITY DEFINER wrapper; app.check_performance_authority
--    already IS that wrapper for exactly the 'View personal data' check
--    both broken policies need (`select
--    (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS',
--    p_action)).allowed`) -- reused here unchanged rather than
--    introducing a new wrapper, preserving each policy's exact original
--    predicate. A repository-wide grep confirms these were the only 2
--    remaining direct-call instances anywhere in supabase/migrations/ --
--    the 3 identically-shaped instances HRT-282's own Tier C review found
--    in the Payroll/Finance-handoff migration were already fixed there
--    (20260731020000) and are unaffected by this migration.
--
-- No HRT-285 fix here -- HRT-285 (Prompt 285, ESS/MSS) ships zero
-- migration (a pure TypeScript composition layer over already-VERIFIED/
-- COMPLETED RPCs); its own confirmed findings are fixed in
-- server/queries, server/contracts and the app/ route tree directly, not
-- here.

-- ============================================================
-- Finding 1: ambiguous bare `id` in 7 RETURNS TABLE(id ...) functions
-- ============================================================

-- --- HRT-283 (create_hris_kpi_performance.sql) ---
-- Every function body below is byte-for-byte identical to its original
-- (captured live via pg_get_functiondef against the applied migration)
-- except the single ambiguous `where id = p_...` line, now qualified with
-- the source table's own alias -- no column, return-type, business-logic,
-- or authority-check change of any kind.

create or replace function app.get_performance_cycle(p_cycle_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, tenant_id uuid, template_id uuid, code text, name text, cycle_type text, period_start date, period_end date, status text, weight_total_required numeric, record_version integer)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_row app.performance_cycles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_row from app.performance_cycles c where c.id = p_cycle_id;
  if v_row.id is null or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select v_row.id, v_row.tenant_id, v_row.template_id, v_row.code, v_row.name, v_row.cycle_type, v_row.period_start, v_row.period_end, v_row.status, v_row.weight_total_required, v_row.record_version;
end;
$$;

create or replace function app.list_performance_goal_progress_entries(p_goal_assignment_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, actual_value numeric, note text, evidence_file_id uuid, recorded_by text, recorded_at timestamptz)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_goal app.performance_goal_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_goal from app.performance_goal_assignments g where g.id = p_goal_assignment_id;
  if v_goal.id is null or not app.can_view_hris_performance_row(v_goal.tenant_id, v_goal.employee_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select p.id, p.actual_value, p.note, p.evidence_file_id, p.recorded_by, p.recorded_at
  from app.performance_goal_progress_entries p
  where p.goal_assignment_id = p_goal_assignment_id
  order by p.recorded_at desc;
end;
$$;

create or replace function app.list_performance_assessment_kpi_scores(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, goal_assignment_id uuid, kpi_code text, kpi_name text, actual_value numeric, manual_score numeric, raw_score numeric, score_rationale text, record_version integer)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_assessment app.performance_assessments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_assessment from app.performance_assessments a where a.id = p_assessment_id;
  if v_assessment.id is null then
    return;
  end if;
  if not app.can_view_performance_assessment_row(v_assessment.tenant_id, v_assessment.employee_id, v_assessment.assessment_type, v_assessment.assigned_to_employee_id, v_assessment.status, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select s.id, s.goal_assignment_id, k.code, k.name, s.actual_value, s.manual_score, s.raw_score, s.score_rationale, s.record_version
  from app.performance_assessment_kpi_scores s
  join app.performance_goal_assignments g on g.id = s.goal_assignment_id
  join app.performance_kpi_definitions k on k.id = g.kpi_definition_id
  where s.assessment_id = p_assessment_id
  order by k.code;
end;
$$;

create or replace function app.get_performance_outcome(p_outcome_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, tenant_id uuid, cycle_id uuid, employee_id uuid, baseline_score numeric, calibrated_score numeric, final_score numeric, score_breakdown jsonb, status text, published_at timestamptz, acknowledgement_agreement text, acknowledgement_comment text, record_version integer)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_row app.performance_outcomes;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_row from app.performance_outcomes o where o.id = p_outcome_id;
  if v_row.id is null or not app.can_view_performance_outcome_row(v_row.tenant_id, v_row.employee_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select v_row.id, v_row.tenant_id, v_row.cycle_id, v_row.employee_id, v_row.baseline_score, v_row.calibrated_score, v_row.final_score,
    v_row.score_breakdown, v_row.status, v_row.published_at, v_row.acknowledgement_agreement, v_row.acknowledgement_comment, v_row.record_version;
end;
$$;

create or replace function app.list_performance_calibration_adjustments(p_outcome_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, previous_score numeric, adjusted_score numeric, adjustment_reason text, calibrated_by text, calibrated_at timestamptz)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_outcome app.performance_outcomes;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_outcome from app.performance_outcomes o where o.id = p_outcome_id;
  if v_outcome.id is null then
    return;
  end if;
  -- HR-only (decision 4) -- never self/manager, even though they may see
  -- the outcome's own final_score via app.can_view_performance_outcome_row.
  if not app.check_performance_authority('View personal data', v_outcome.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select a.id, a.previous_score, a.adjusted_score, a.adjustment_reason, a.calibrated_by, a.calibrated_at
  from app.performance_calibration_adjustments a
  where a.outcome_id = p_outcome_id
  order by a.calibrated_at desc;
end;
$$;

-- --- HRT-284 (create_hris_training_talent.sql) ---

create or replace function app.get_training_session(p_session_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, course_version_id uuid, course_id uuid, course_code text, course_name text, provider_id uuid, provider_name text, session_code text, location text, start_at timestamptz, end_at timestamptz, capacity integer, enrolled_count integer, waitlisted_count integer, status text, record_version integer)
language plpgsql
stable security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_session app.training_sessions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_session from app.training_sessions s where s.id = p_session_id;
  if not found then
    raise exception 'training_session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select s.id, s.course_version_id, cv.course_id, c.code, c.name, s.provider_id, pr.name,
    s.session_code, s.location, s.start_at, s.end_at, s.capacity,
    (select count(*)::integer from app.training_enrollments e where e.session_id = s.id and e.status = 'enrolled'),
    (select count(*)::integer from app.training_enrollments e where e.session_id = s.id and e.status = 'waitlisted'),
    s.status, s.record_version
  from app.training_sessions s
  join app.training_course_versions cv on cv.id = s.course_version_id
  join app.training_courses c on c.id = cv.course_id
  left join app.training_providers pr on pr.id = s.provider_id
  where s.id = p_session_id;
end;
$$;

create or replace function app.list_talent_pool_members(p_pool_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, pool_id uuid, employee_id uuid, employee_full_name text, status text, added_reason text, added_at timestamptz, record_version integer)
language plpgsql
stable security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_pool app.talent_pools;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_pool from app.talent_pools p where p.id = p_pool_id;
  if not found then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_pool.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select m.id, m.pool_id, m.employee_id, e.full_name, m.status, m.added_reason, m.added_at, m.record_version
  from app.talent_pool_members m
  join app.employees e on e.master_record_id = m.employee_id
  where m.pool_id = p_pool_id
  order by m.added_at desc;
end;
$$;

-- ============================================================
-- Finding 2: app.enqueue_job check-then-insert race on idempotency_key
-- ============================================================

create or replace function app.enqueue_job(
  p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text,
  p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := app.generic_job_types();
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  -- Batch 283-285 Tier C fix (finding 2, correctness lens): the
  -- check-then-insert above is not atomic -- two genuinely concurrent
  -- callers with the SAME (tenant_id, idempotency_key) can both pass the
  -- "not found" check above and both reach this INSERT. Without this
  -- exception handler the losing caller received a raw, unclassified
  -- Postgres 23505 instead of the SAME idempotent-replay row the winner
  -- (or a slightly-earlier caller) already created -- live-reproduced
  -- with two genuinely concurrent OS processes calling
  -- app.run_training_certificate_expiry_batch (HRT-284) with the same
  -- period label. Mirrors this repository's own established
  -- check-then-insert-with-handler shape (e.g.
  -- app.create_performance_kpi_definition, app.create_payroll_run).
  begin
    insert into app.jobs (
      tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
      requested_by_auth_user_id, created_by
    ) values (
      p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise; -- not an idempotency-key race (e.g. a different constraint) -- surface unchanged.
      end if;
      select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise; -- constraint fired on something other than the key we expected -- surface unchanged rather than mask it.
      end if;
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$$;

-- ============================================================
-- Finding 3: RLS policies calling app.evaluate_permission directly
-- (service_role-only grant) instead of the SECURITY DEFINER wrapper
-- app.check_performance_authority every sibling policy already uses
-- ============================================================

drop policy if exists performance_reviewer_assignments_select_scoped on app.performance_reviewer_assignments;
create policy performance_reviewer_assignments_select_scoped on app.performance_reviewer_assignments
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_performance_authority('View personal data', tenant_id, (select auth.uid()))
    or (app.get_self_employee(tenant_id, (select auth.uid()))).master_record_id = employee_id
    or (app.get_self_employee(tenant_id, (select auth.uid()))).master_record_id = assigned_to_employee_id
  );

drop policy if exists performance_calibration_adjustments_select_scoped on app.performance_calibration_adjustments;
create policy performance_calibration_adjustments_select_scoped on app.performance_calibration_adjustments
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_performance_authority('View personal data', tenant_id, (select auth.uid()))
  );
