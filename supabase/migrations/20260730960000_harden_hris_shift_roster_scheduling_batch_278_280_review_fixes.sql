-- Tier C batch review-round fix pass, CG-S12-HRT-007 (Prompt 279, Shift,
-- Roster and Scheduling), part of the combined 278-280 batch close.
-- AGENTS.md "never edit an applied migration; add a new migration" --
-- 20260730910000/20260730920000 are already applied and committed, so every
-- fix below is additive (CREATE OR REPLACE FUNCTION with an identical
-- signature/return shape, or DROP POLICY + CREATE POLICY for RLS).
--
-- Fixes three CONFIRMED, live-reproduced findings from the batch's Tier C
-- review, independently re-derived against a fresh disposable Postgres 16
-- database before this migration was written, per
-- BUILD_EXECUTION_PROTOCOL.md section 5.3:
--
-- 1. HIGH (self-scoping-raw-table-overexposure, the SAME shape as HRT-278's
--    own finding this batch's Tier C fixed in 20260730950000): app.schedule_
--    assignments had a tenant-membership-only RLS SELECT policy -- a tenant
--    member with zero HRS permission and no linked employee row could read
--    the entire tenant's roster (who works which shift, which day) via a raw
--    SELECT, live-reproduced. This fix pass's own mandatory section 5.4
--    propagation sweep across the whole batch found the identical shape on
--    app.schedule_swap_requests too (not independently reported, but the
--    same tenant-membership-only policy over the same class of per-employee
--    data -- who is swapping shifts with whom, and why). Fixed by reusing
--    app.can_view_hris_person_scoped_row (new in 20260730950000, this same
--    batch's HRT-278 fix) on both tables -- for schedule_swap_requests,
--    OR'd across BOTH its own employee columns (requesting_employee_id,
--    target_employee_id), since either party to a swap is a legitimate
--    self-viewer.
--
-- 2. MEDIUM (concurrency-error-handling): app.assign_employee_schedule's
--    genuine supersede-race (two concurrent callers replacing the SAME
--    existing scheduled assignment) correctly serializes to exactly one
--    winner, but the terminal INSERT had no exception handler -- the loser
--    received a raw, untranslated Postgres unique_violation (real internal
--    constraint name leaked), unlike app.submit_leave_request (HRT-280, same
--    batch) which explicitly catches and translates its own equivalent race.
--    Live-reproduced with two genuinely concurrent backend connections.
--    Fixed by wrapping the terminal INSERT in the same catch-and-translate
--    shape app.submit_leave_request already established.
--
-- 3. MEDIUM (idempotency): app.generate_roster_schedule_assignments passed a
--    literal null idempotency key to both app.enqueue_job and every internal
--    app.assign_employee_schedule call, so an identical retry of a bulk
--    generation request was never a no-op -- it silently superseded and
--    recreated every draft assignment in range again, and created a second,
--    distinct app.jobs row each time. Live-reproduced: two byte-identical
--    calls produced created=2/superseded=0 then created=0/superseded=2, plus
--    2 separate completed job rows. Fixed by deriving a natural idempotency
--    key from the call's own semantic identity (roster_cycle_id + date range
--    + sorted employee_id set) and only running the generation loop when
--    app.enqueue_job genuinely created a fresh pending job -- the EXACT
--    already-proven pattern app.run_leave_accrual_batch/app.run_leave_carry_
--    forward_batch (HRT-280, same batch) already established for this
--    identical defect class; HRT-280's own build log explicitly flagged this
--    exact function as needing the same fix during its own Tier B walk
--    (out of that task's allowed-files scope), so this is the batch's own
--    Tier C propagation sweep closing that flagged gap, not a new discovery.

-- ===========================================================================
-- Fix 1: self/manager/HRS:View RLS scoping (finding "self-scoping-raw-table-
-- overexposure", HIGH; propagation sweep also covers schedule_swap_requests).
-- ===========================================================================

drop policy if exists schedule_assignments_select_scoped on app.schedule_assignments;
create policy schedule_assignments_select_scoped on app.schedule_assignments
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

drop policy if exists schedule_swap_requests_select_scoped on app.schedule_swap_requests;
create policy schedule_swap_requests_select_scoped on app.schedule_swap_requests
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and (
        app.can_view_hris_person_scoped_row(tenant_id, requesting_employee_id)
        or app.can_view_hris_person_scoped_row(tenant_id, target_employee_id)
      )
    )
  );

-- ===========================================================================
-- Fix 2: translate the terminal INSERT's own unique_violation on a genuine
-- supersede-race into the same friendly, retry-worthy error class
-- app.submit_leave_request (HRT-280) already established for its own
-- equivalent overlap race (concurrency-error-handling, MEDIUM).
-- ===========================================================================

create or replace function app.assign_employee_schedule(
  p_tenant_id uuid, p_employee_id uuid, p_shift_template_version_id uuid, p_work_date date, p_source text, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.schedule_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_version app.shift_template_versions;
  v_existing app.schedule_assignments;
  v_existing_found boolean;
  v_new app.schedule_assignments;
  v_decision app.rbac_decision;
  v_has_edit boolean;
  v_has_override boolean;
begin
  select * into v_employee from app.employees where master_record_id = p_employee_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if v_employee.tenant_id <> p_tenant_id then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  v_has_edit := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit')).allowed;
  v_has_override := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override')).allowed;
  if not v_has_edit and not v_has_override then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit/HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.lifecycle_status <> 'active' then
    raise exception 'employee_not_active: employee % is %, only an active employee may be scheduled', p_employee_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  select * into v_version from app.shift_template_versions where id = p_shift_template_version_id;
  if not found or v_version.tenant_id <> p_tenant_id or v_version.status <> 'published' then
    raise exception 'shift_template_version_not_available: % is not a published shift template version in this tenant', p_shift_template_version_id
      using errcode = 'no_data_found';
  end if;

  if p_work_date is null then
    raise exception 'invalid_work_date: work_date is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.schedule_assignments
  where tenant_id = p_tenant_id and employee_id = p_employee_id and work_date = p_work_date and status in ('scheduled', 'published')
  for update;
  v_existing_found := found;

  if p_idempotency_key is not null then
    declare
      v_replay app.schedule_assignments;
    begin
      select * into v_replay from app.schedule_assignments where tenant_id = p_tenant_id and employee_id = p_employee_id and idempotency_key = p_idempotency_key;
      if found then
        if v_replay.work_date = p_work_date and v_replay.shift_template_version_id = p_shift_template_version_id then
          return v_replay;
        else
          raise exception 'idempotency_key_conflict: key % was already used for a different schedule assignment', p_idempotency_key using errcode = 'unique_violation';
        end if;
      end if;
    end;
  end if;

  if v_existing_found and v_existing.status = 'published' then
    if not v_has_override then
      raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant % (superseding a published assignment)', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not v_has_edit then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_existing.id is not null then
    update app.schedule_assignments set status = 'superseded' where id = v_existing.id;
  end if;

  -- Batch 278-280 Tier C fix (concurrency-error-handling, MEDIUM,
  -- live-reproduced with two genuinely concurrent connections): a race where
  -- BOTH concurrent callers observe the SAME v_existing row (one wins the
  -- FOR UPDATE lock and commits its own supersede+insert first; the loser's
  -- blocked FOR UPDATE unblocks onto the now-superseded row, which no longer
  -- matches the WHERE clause above, so v_existing_found comes back false and
  -- this loser proceeds straight to its own INSERT) collides with the
  -- winner's brand-new row on the same partial unique index
  -- (tenant_id, employee_id, work_date). Previously an uncaught, raw
  -- Postgres unique_violation leaked the real constraint name to the caller;
  -- now translated to the same friendly, retry-worthy error class
  -- app.submit_leave_request (HRT-280) already established for its own
  -- equivalent race.
  begin
    insert into app.schedule_assignments (tenant_id, employee_id, shift_template_version_id, work_date, source, previous_assignment_id, idempotency_key, created_by)
    values (p_tenant_id, p_employee_id, p_shift_template_version_id, p_work_date, coalesce(p_source, 'manual'), v_existing.id, p_idempotency_key, p_actor_label)
    returning * into v_new;
  exception
    when unique_violation then
      raise exception 'schedule_assignment_conflict: employee % already has an active schedule assignment for % -- a concurrent assignment was just committed, retry'
        , p_employee_id, p_work_date
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_employee_schedule',
    'app.schedule_assignments', v_new.id, 'success', null, null,
    jsonb_build_object('employee_id', p_employee_id, 'work_date', p_work_date, 'shift_template_version_id', p_shift_template_version_id, 'superseded_id', v_existing.id)
  );

  return v_new;
end;
$$;

comment on function app.assign_employee_schedule is
  'HRT-279 (decisions 4/5): always inserts a new row. If a prior scheduled-or-published row exists for the same (employee, work_date), it is superseded -- HRS:Edit suffices to supersede a still-draft (''scheduled'') row, HRS:Override is required to supersede an already-published one (the "immutable by normal role" governed truth). Batch 278-280 Tier C fix (concurrency-error-handling, MEDIUM, live-reproduced): the terminal INSERT''s own unique_violation on a genuine concurrent-supersede race is now translated to schedule_assignment_conflict rather than leaking the raw constraint name.';

-- ===========================================================================
-- Fix 3: idempotent retry for app.generate_roster_schedule_assignments
-- (idempotency, MEDIUM) -- the exact app.run_leave_accrual_batch/app.run_
-- leave_carry_forward_batch (HRT-280) pattern: derive a natural key from the
-- call's own semantic identity, pass it to app.enqueue_job, and only run the
-- generation loop when a genuinely FRESH job was created.
-- ===========================================================================

create or replace function app.generate_roster_schedule_assignments(
  p_tenant_id uuid, p_roster_cycle_id uuid, p_employee_ids uuid[], p_from_date date, p_to_date date, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (created_count integer, superseded_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cycle app.roster_cycles;
  v_job app.jobs;
  v_worker_id text;
  v_employee_id uuid;
  v_offset integer;
  v_slot app.roster_cycle_slots;
  v_created integer := 0;
  v_superseded integer := 0;
  v_skipped integer := 0;
  v_existing_status text;
  v_day date;
  v_result app.schedule_assignments;
  v_natural_key text;
  v_sorted_employee_ids uuid[];
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_cycle from app.roster_cycles where id = p_roster_cycle_id;
  if not found or v_cycle.tenant_id <> p_tenant_id or v_cycle.status <> 'published' then
    raise exception 'roster_cycle_not_available: % is not a published roster cycle in this tenant', p_roster_cycle_id using errcode = 'no_data_found';
  end if;

  if p_employee_ids is null or array_length(p_employee_ids, 1) is null then
    raise exception 'invalid_employee_ids: at least one employee_id is required' using errcode = 'check_violation';
  end if;

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days (decision 8 -- bounded generation)' using errcode = 'check_violation';
  end if;

  -- Batch 278-280 Tier C fix (idempotency, MEDIUM, live-reproduced): the
  -- natural key is derived from every argument that identifies WHAT the
  -- caller actually asked for (C-01 full-tuple idempotency), sorted so
  -- argument order never changes the derived key for the same logical set.
  select array_agg(x order by x) into v_sorted_employee_ids from unnest(p_employee_ids) x;
  v_natural_key := 'roster_generation:' || p_roster_cycle_id::text || ':' || p_from_date::text || ':' || p_to_date::text
    || ':' || array_to_string(v_sorted_employee_ids, ',');

  v_job := app.enqueue_job(
    p_tenant_id, 'roster_generation',
    jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'from_date', p_from_date, 'to_date', p_to_date, 'employee_count', array_length(p_employee_ids, 1)),
    0, v_natural_key, 1, p_actor_auth_user_id, p_actor_label
  );

  -- A replay against an already-existing job (any status) is a real, safe
  -- no-op -- zero new work, the SAME job_id returned -- never a second
  -- attempt to claim/complete an already-completed job and never a repeated
  -- supersede-churn of the assignments the first call already created.
  if v_job.status = 'pending' then
    v_worker_id := 'inline-roster-generator:' || p_actor_auth_user_id::text;

    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    foreach v_employee_id in array p_employee_ids loop
      if not exists (select 1 from app.employees where master_record_id = v_employee_id and tenant_id = p_tenant_id and lifecycle_status = 'active') then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_day := p_from_date;
      while v_day <= p_to_date loop
        v_offset := ((v_day - p_from_date) % v_cycle.cycle_length_days);
        select * into v_slot from app.roster_cycle_slots where roster_cycle_id = p_roster_cycle_id and day_offset = v_offset;

        if v_slot.shift_template_id is not null then
          select status into v_existing_status from app.schedule_assignments
          where tenant_id = p_tenant_id and employee_id = v_employee_id and work_date = v_day and status in ('scheduled', 'published');

          if v_existing_status = 'published' then
            v_skipped := v_skipped + 1;
          else
            declare
              v_version_id uuid;
            begin
              select id into v_version_id from app.shift_template_versions
              where shift_template_id = v_slot.shift_template_id and status = 'published'
              order by effective_from desc limit 1;

              if v_version_id is null then
                v_skipped := v_skipped + 1;
              else
                begin
                  v_result := app.assign_employee_schedule(p_tenant_id, v_employee_id, v_version_id, v_day, 'bulk_generated', null, p_actor_auth_user_id, p_actor_label);
                  update app.schedule_assignments set roster_cycle_id = p_roster_cycle_id where id = v_result.id;
                  if v_existing_status is not null then
                    v_superseded := v_superseded + 1;
                  else
                    v_created := v_created + 1;
                  end if;
                exception
                  when insufficient_privilege or check_violation or no_data_found or unique_violation then
                    v_skipped := v_skipped + 1;
                end;
              end if;
            end;
          end if;
        end if;

        v_existing_status := null;

        v_day := v_day + 1;
      end loop;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_roster_schedule_assignments',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'created_count', v_created, 'superseded_count', v_superseded, 'skipped_count', v_skipped)
    );
  end if;

  created_count := v_created; superseded_count := v_superseded; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.generate_roster_schedule_assignments is
  'HRT-279 (decision 8): a real app.jobs row, tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Batch 278-280 Tier C fix (idempotency, MEDIUM, live-reproduced): now derives a natural idempotency key from (roster_cycle_id, from_date, to_date, sorted employee_id set) and only runs the generation loop when app.enqueue_job genuinely created a fresh pending job -- an identical retry is now a safe no-op (zero new work, the SAME job_id returned), mirroring app.run_leave_accrual_batch/app.run_leave_carry_forward_batch (HRT-280) exactly, which HRT-280''s own build log had already flagged this function as needing but left out of that task''s own allowed-files scope.';
