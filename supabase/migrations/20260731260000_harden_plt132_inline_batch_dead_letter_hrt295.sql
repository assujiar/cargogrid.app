-- HRT-295 (CG-S12-HRT-023, HRT-294 finding PLT-132): inline batch jobs never
-- reach dead_letter on a mid-loop failure (HIGH).
--
-- The defect, exactly as HRT-294 live-reproduced it (docs/runtime/
-- KNOWN_ISSUES.md, "PLT-132 inline batch jobs never reach dead_letter on
-- mid-loop failure"): app.run_ticket_escalation_evaluation_batch and
-- app.run_ticket_sla_evaluation_batch call app.enqueue_job exactly once, then
-- loop calling their own per-item evaluator with NO exception-handling block
-- around the loop and NO call to app.record_job_failure anywhere.
-- app.run_leave_accrual_batch/app.run_leave_carry_forward_batch share the
-- identical shape (their per-item INSERT is caught ONLY for the narrow
-- unique_violation idempotency-replay case, nothing else).
-- app.generate_roster_schedule_assignments (20260730960000) is the sole
-- partial exception -- its own innermost per-item call already catches
-- insufficient_privilege/check_violation/no_data_found/unique_violation, but
-- (a) that whitelist is not exhaustive -- anything outside those four classes
-- still escapes uncaught, and (b) even the four classes it DOES catch are
-- only silently counted (v_skipped), never durably recorded anywhere
-- findable.
--
-- Every one of these five RPCs is ONE top-level function call, i.e. ONE
-- Postgres transaction with no savepoint. An uncaught exception ANYWHERE in
-- the per-item loop rolls back the WHOLE transaction -- including
-- app.enqueue_job's own earlier INSERT into app.jobs, committed nowhere
-- since the whole call is one transaction. The job row never persists in ANY
-- state, neither pending nor dead_letter -- HRT-294 live-confirmed a forced
-- mid-loop cancellation left zero app.jobs rows behind. app.record_job_
-- failure (this checkpoint's own full read of 20260719180000, the framework
-- migration) is therefore never even reachable: there is no job row left to
-- call it against.
--
-- ===========================================================================
-- Design decision (Prompt 295 charter section 33's own "make the correct,
-- defensible, bounded call yourself, documenting your reasoning" instruction)
-- ===========================================================================
--
-- app.record_job_failure's own contract (re-read in full from
-- 20260719180000 before writing this fix) is JOB-level: it increments
-- app.jobs.attempts, and transitions the JOB to 'pending' (with an
-- app.compute_job_backoff_seconds() retry delay) or 'dead_letter' once
-- max_attempts is reached. It is designed to be called ONCE per failed
-- ATTEMPT of the WHOLE job, by a caller that is about to give up on this
-- attempt entirely -- not once per FAILED ITEM inside an otherwise-still-
-- running attempt. Calling it per-item while continuing the loop would
-- itself be broken: the very first per-item call would flip the job to
-- 'pending'/'dead_letter' (releasing the lease, clearing locked_by), so the
-- unconditional app.complete_job at the end of the loop -- still needed for
-- every item that DID succeed -- would then raise job_lease_not_held (it
-- requires status='in_progress' AND locked_by=p_worker_id, both already
-- cleared). True job-level dead-lettering that coexists with "the rest of
-- the batch still gets evaluated" would need app.enqueue_job's insert and
-- app.complete_job's/app.record_job_failure's own resolution to run in a
-- genuinely SEPARATE transaction from the per-item evaluation loop (e.g. a
-- real out-of-process worker claiming the job via app.claim_next_job and
-- calling complete/record_job_failure afterward) -- no such multi-
-- transaction pattern exists anywhere in this repository yet (every one of
-- these five RPCs is deliberately an inline, synchronous, single-transaction
-- "self-claim" convenience wrapper, per each function's own pre-existing
-- comment). Building that out is a structurally different, materially larger
-- change than this finding's own "repair the smallest evidence-ranked set of
-- defects" charter authorizes -- flagged here, disclosed, not silently
-- implemented as a bigger redesign.
--
-- The bounded, defensible fix actually shipped below, identically shaped
-- across all five functions: wrap EACH per-item evaluation in its own
-- nested BEGIN/EXCEPTION block, inside the SAME transaction. A genuine
-- per-item failure is caught (`when others` -- exhaustive, never a narrower
-- allowlist that could itself silently let a new exception class straight
-- through) -- EXCEPT `query_canceled` (SQLSTATE 57014), which is explicitly
-- re-raised in its own branch BEFORE `when others` in every one of the five
-- blocks below. `WHEN OTHERS` in PL/pgSQL also catches `query_canceled`, a
-- real, documented gotcha -- without this exclusion, an operator's own
-- deliberate `pg_cancel_backend`/`statement_timeout` against a stuck or
-- runaway batch (the exact mechanism HRT-294's own live reproduction used to
-- force this finding's original mid-loop failure) would be silently
-- absorbed as "this one item failed" and the loop would carry on to the
-- next item instead of actually stopping -- defeating the operator's own
-- cancellation, not merely tolerating a business-level per-item error.
-- Recorded durably and findably via app.capture_audit_event
-- (result='failure', reason=sqlerrm, resource_type/resource_id identifying
-- the exact failing item, after_value carrying job_id/sqlstate/period for
-- correlation -- the SAME durable, queryable, RLS/authority-gated mechanism
-- app.record_job_failure itself already uses for its own audit trail, and
-- the same "always record a discriminated row, never a silent drop" shape
-- app._queue_ticket_escalation_notification (HRT-291) already established
-- for its own narrower notification-only failure case), and the loop
-- CONTINUES to the next item. app.complete_job is still called unconditionally
-- once the loop finishes -- the job's own unit of work (attempt every
-- eligible item) genuinely completed, even when some items individually
-- failed -- so the job row is NEVER lost: it always reaches a real terminal
-- state (`completed`) with a real, non-lost app.jobs row, closing HRT-294's
-- own exact live-reproduction (zero rows afterward). The batch-level
-- app.capture_audit_event call at the very end now also discloses
-- failed_count alongside the existing evaluated/accrued/created counts, so
-- an operator reading the audit trail sees partial-failure evidence at a
-- glance without a second query.
--
-- Disclosed limitation (same "record, do not silently auto-retry" posture
-- HRT-291's own notification-failure handling already disclosed): a job-
-- level idempotency-key replay of the SAME period only re-runs the loop
-- while the job is still 'pending' (every one of these five functions' own
-- pre-existing guard) -- once `completed`, a byte-identical replay is a
-- deliberate no-op, so an item that failed is not automatically retried by
-- calling the same RPC again with the same period_label. The failure is
-- durably visible in app.audit_logs (queryable via app.query_audit_logs/
-- app.export_audit_logs) for an operator to act on -- a real, disclosed
-- design boundary, not a silent gap; building an automatic per-item retry
-- queue is out of this finding's own bounded scope.
--
-- app.generate_roster_schedule_assignments specifically: its own pre-
-- existing four-code allowlist (insufficient_privilege/check_violation/
-- no_data_found/unique_violation -> v_skipped++) is left completely
-- UNCHANGED (never weakening an already-passing test, Prompt 132 §29's own
-- explicit requirement, re-affirmed by this task's own instructions) -- a
-- new, ADDITIONAL `when others` branch is appended after it, only ever
-- reached by an exception OUTSIDE that already-handled set, closing exactly
-- the coverage gap described above without touching any already-verified
-- skipped_count assertion.
--
-- No RETURNS TABLE signature of any of the five functions changes -- adding
-- a new output column is unnecessary (the durable evidence lives in
-- app.audit_logs, independently queryable) and would be a needless, non-
-- additive-in-spirit ripple into server/mutations/{leave,shift-roster,
-- ticketing}.ts's own already-typed positional/keyed result parsing.
--
-- Regression proof (per function, scripts/db-tests/*.sql, this same batch):
-- a genuine per-item failure is forced via a REAL data condition, never an
-- artificial statement-timeout -- for app.run_ticket_sla_evaluation_batch, an
-- organically reachable one already exists in the shipped code
-- (app.compute_sla_business_minutes' own disclosed 5-year business-minutes
-- bound, `sla_range_too_large`, hit by a clock whose started_at is
-- legitimately years in the past -- a real, valid timestamptz value, no
-- corruption). The other four have no such organically reachable failure
-- left given how tightly CHECK/FK-constrained their own tables already are
-- (a genuinely good property of this schema, confirmed by this task's own
-- exhaustive attempt to find one) -- for those, each test installs a
-- temporary, narrowly-scoped CHECK constraint on the exact table the
-- per-item evaluator writes to, keyed to ONE real, already-committed
-- sentinel row's own identity column (e.g. `ticket_id is distinct from
-- '<sentinel>'`) -- a genuine Postgres check_violation raised by real SQL
-- execution against that row's real data, structurally indistinguishable
-- from any of this schema's own dozens of pre-existing CHECK constraints,
-- dropped again at the end of each test section for hygiene (scripts/db-
-- tests/run.sh runs every *.sql file against the SAME disposable database in
-- sequence, never one database per file).
--
-- Disclosed, NOT fixed here (out of this finding's own registered five-
-- function scope -- ISS-2026-112/KNOWN_ISSUES.md names exactly these five;
-- "repair the smallest evidence-ranked set", Prompt 295 charter section 33):
-- a repository-wide grep for `app.enqueue_job(` followed by a per-item
-- `for`/`foreach`/`while` loop before its own `app.complete_job` call found
-- a SIXTH, same-shape instance still inside Phase 7 HRIS -- `app.run_
-- training_certificate_expiry_reminder_batch` (HRT-284,
-- `20260731040000_create_hris_training_talent.sql:2807-2867`) -- its own
-- per-certificate loop catches ONLY `unique_violation` (the identical
-- pre-fix shape `app.run_leave_accrual_batch`/`app.run_leave_carry_forward_
-- batch` had), so any OTHER exception there still aborts the whole
-- transaction today, losing its own just-enqueued app.jobs row exactly like
-- this finding's own five. (Its sibling in the same file, `app.run_
-- training_certificate_expiry_batch`, is a single set-based UPDATE with no
-- per-row loop at all -- structurally immune, correctly undisclosed as a
-- non-instance.) `app.calculate_payroll_run` (HRT-282, `202607310000
-- 00_create_hris_payroll_foundation.sql:2033-2143`) was also found by the
-- same grep and inspected -- it does NOT share this defect: it already
-- wraps each per-employee calculation in its own `when others` block
-- (recording to `app.payroll_exceptions`, `complete_job` still called
-- unconditionally after the loop) and additionally implements a genuine
-- chunked heartbeat/cooperative-cancellation mechanism for long runs,
-- predating this fix. Several further `enqueue_job`-plus-loop shapes exist
-- entirely outside Phase 7 (Finance/Commercial dashboard report generation,
-- Procurement dashboard reports, Advanced TMS route/load planning and label/
-- barcode operations) -- outside this checkpoint's own HRIS/Ticketing-scoped
-- charter and this task's registered finding, so deliberately NOT
-- inspected or fixed here; flagged for a future sweep rather than silently
-- left unswept, mirroring this same repository's own established
-- "out of this task's own allowed-files scope... flagged here for the
-- batch's own Tier C propagation sweep" precedent
-- (`20260730930000_create_hris_leave_permit_business_trip.sql`'s own header).

-- ===========================================================================
-- 1. app.run_ticket_escalation_evaluation_batch (HRT-291, 20260731160000)
-- ===========================================================================

create or replace function app.run_ticket_escalation_evaluation_batch(p_tenant_id uuid, p_as_of timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (evaluated_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_ticket record;
  v_evaluated integer := 0;
  v_failed integer := 0;
  v_as_of timestamptz := coalesce(p_as_of, now());
begin
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'ticket_escalation_evaluation', jsonb_build_object('as_of', v_as_of, 'period_label', p_period_label),
    0, 'ticket_escalation_evaluation:' || p_tenant_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-ticket-escalation-evaluation:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_ticket in
      select t.id from app.tickets t
      where t.tenant_id = p_tenant_id
        and t.channel in ('internal', 'customer')
        and (t.status not in ('closed', 'cancelled') or exists (select 1 from app.ticket_escalations e where e.ticket_id = t.id and e.status <> 'resolved'))
    loop
      -- PLT-132 (HRT-295) fix: one ticket's own evaluation failure must never
      -- abort the whole transaction -- see this migration's own header for
      -- the full reasoning. Caught narrowly around exactly this one call.
      begin
        perform app._evaluate_ticket_escalation(v_ticket.id, v_as_of, v_job.job_id, p_actor_auth_user_id, p_actor_label);
        v_evaluated := v_evaluated + 1;
      exception
        when query_canceled then
          -- A genuine operator/statement_timeout cancellation must still
          -- abort the WHOLE batch, never be silently absorbed as "this one
          -- ticket failed" -- WHEN OTHERS below would otherwise catch
          -- query_canceled too (a real, documented PL/pgSQL gotcha), which
          -- would defeat an operator's own deliberate attempt to stop a
          -- runaway batch. Re-raised, never caught.
          raise;
        when others then
          v_failed := v_failed + 1;
          perform app.capture_audit_event(
            p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_escalation_evaluation_batch_item_failed',
            'app.tickets', v_ticket.id, 'failure', sqlerrm,
            null, jsonb_build_object('job_id', v_job.job_id, 'period_label', p_period_label, 'sqlstate', sqlstate)
          );
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_escalation_evaluation_batch',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('period_label', p_period_label, 'evaluated_count', v_evaluated, 'failed_count', v_failed)
    );
  end if;

  evaluated_count := v_evaluated; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_ticket_escalation_evaluation_batch is
  'HRT-291 (decisions 6/8/9/10), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Idempotent per (tenant, period_label) at the JOB level (a replayed period is a pending-status no-op), AND every individual ticket evaluation inside the loop is separately idempotent at the LEDGER level regardless of job replay -- two independent, overlapping guarantees, mirroring app.run_ticket_sla_evaluation_batch (HRT-289) exactly. Also re-evaluates any ticket with a still-open escalation regardless of its own current status/channel filter, so a closed ticket''s dangling escalation is still resolved (C-18). HRT-295: a genuine per-ticket evaluation failure is now caught (never aborts the whole batch transaction, which previously lost the just-enqueued app.jobs row entirely -- HRT-294 PLT-132) and durably recorded via app.capture_audit_event (action=run_ticket_escalation_evaluation_batch_item_failed) -- the job still reaches completed with a disclosed failed_count.';

-- ===========================================================================
-- 2. app.run_ticket_sla_evaluation_batch (HRT-289, 20260731120000)
-- ===========================================================================

create or replace function app.run_ticket_sla_evaluation_batch(p_tenant_id uuid, p_as_of timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (evaluated_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_clock record;
  v_evaluated integer := 0;
  v_failed integer := 0;
  v_as_of timestamptz := coalesce(p_as_of, now());
begin
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'ticket_sla_evaluation', jsonb_build_object('as_of', v_as_of, 'period_label', p_period_label),
    0, 'ticket_sla_evaluation:' || p_tenant_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-ticket-sla-evaluation:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_clock in
      select c.id from app.ticket_sla_clocks c where c.tenant_id = p_tenant_id and c.status in ('running', 'paused')
    loop
      -- PLT-132 (HRT-295) fix: see app.run_ticket_escalation_evaluation_batch
      -- above (this same migration) for the full reasoning -- identical
      -- shape here, one clock at a time.
      begin
        perform app._evaluate_ticket_sla_clock(v_clock.id, v_as_of, v_job.job_id);
        v_evaluated := v_evaluated + 1;
      exception
        when query_canceled then
          -- See app.run_ticket_escalation_evaluation_batch above (this same
          -- migration) -- a genuine cancel/timeout must still abort the
          -- WHOLE batch, never be silently absorbed per-clock.
          raise;
        when others then
          v_failed := v_failed + 1;
          perform app.capture_audit_event(
            p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_sla_evaluation_batch_item_failed',
            'app.ticket_sla_clocks', v_clock.id, 'failure', sqlerrm,
            null, jsonb_build_object('job_id', v_job.job_id, 'period_label', p_period_label, 'sqlstate', sqlstate)
          );
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_sla_evaluation_batch',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('period_label', p_period_label, 'evaluated_count', v_evaluated, 'failed_count', v_failed)
    );
  end if;

  evaluated_count := v_evaluated; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_ticket_sla_evaluation_batch is
  'HRT-289 (decisions 6/8), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Idempotent per (tenant, period_label) at the JOB level (a replayed period is a pending-status no-op, mirrors app.run_training_certificate_expiry_batch), AND every individual clock evaluation inside the loop is separately idempotent at the LEDGER level regardless of job replay (decision 6) -- two independent, overlapping guarantees, live-tested independently. HRT-295: a genuine per-clock evaluation failure is now caught (never aborts the whole batch transaction, which previously lost the just-enqueued app.jobs row entirely -- HRT-294 PLT-132) and durably recorded via app.capture_audit_event (action=run_ticket_sla_evaluation_batch_item_failed) -- the job still reaches completed with a disclosed failed_count.';

-- ===========================================================================
-- 3. app.run_leave_accrual_batch (HRT-280, 20260730930000)
-- ===========================================================================

create or replace function app.run_leave_accrual_batch(p_tenant_id uuid, p_leave_type_id uuid, p_as_of_date date, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (accrued_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_job app.jobs;
  v_worker_id text;
  v_employee record;
  v_policy app.leave_type_policy_versions;
  v_accrued integer := 0;
  v_skipped integer := 0;
  v_failed integer := 0;
  v_key text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id and status = 'published';
  if not found then
    raise exception 'leave_type_not_available: % is not a published leave type in this tenant', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_as_of_date is null or p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: p_as_of_date and a non-empty p_period_label are required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'leave_accrual', jsonb_build_object('leave_type_id', p_leave_type_id, 'as_of_date', p_as_of_date, 'period_label', p_period_label),
    0, 'leave_accrual:' || p_leave_type_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-leave-accrual:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
      -- PLT-132 (HRT-295) fix: the WHOLE per-employee body (resolution,
      -- eligibility gates, AND the ledger insert) is now inside its own
      -- outer exception boundary -- previously ONLY the ledger insert's own
      -- unique_violation (safe idempotent-replay skip) was caught; any OTHER
      -- exception anywhere in this per-employee body still aborted the
      -- entire batch transaction, losing the just-enqueued app.jobs row
      -- (see this migration's own header). `continue` used inside this
      -- outer block still targets the enclosing FOR loop correctly (a plain
      -- BEGIN/END block is not itself a loop).
      begin
        select * into v_policy from app.resolve_effective_leave_type_policy_version(p_tenant_id, p_leave_type_id, v_employee.branch_org_unit_id, p_as_of_date) limit 1;
        if not found or v_policy.accrual_frequency = 'none' or v_policy.accrual_amount_per_period <= 0 then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        if v_policy.eligibility_min_tenure_days > 0 and (v_employee.hire_date is null or (p_as_of_date - v_employee.hire_date) < v_policy.eligibility_min_tenure_days) then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        if v_policy.accrual_max_balance is not null and app.get_employee_leave_balance(p_tenant_id, v_employee.master_record_id, p_leave_type_id, p_as_of_date) >= v_policy.accrual_max_balance then
          v_skipped := v_skipped + 1;
          continue;
        end if;

        v_key := 'accrual:' || v_policy.id::text || ':' || p_period_label;
        begin
          insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, idempotency_key, created_by)
          values (p_tenant_id, v_employee.master_record_id, p_leave_type_id, 'accrual', v_policy.accrual_amount_per_period, p_as_of_date, v_policy.id, v_key, p_actor_label);
          v_accrued := v_accrued + 1;
        exception
          when unique_violation then
            -- Already posted for this employee/policy_version/period -- the
            -- ledger''s own idempotency_key unique index is the real re-run
            -- safety net (section 17 "async accrual... jobs" must be safely
            -- re-runnable).
            v_skipped := v_skipped + 1;
        end;
      exception
        when query_canceled then
          -- See app.run_ticket_escalation_evaluation_batch above (this same
          -- migration) -- a genuine cancel/timeout must still abort the
          -- WHOLE batch, never be silently absorbed per-employee.
          raise;
        when others then
          v_failed := v_failed + 1;
          perform app.capture_audit_event(
            p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_accrual_batch_item_failed',
            'app.employees', v_employee.master_record_id, 'failure', sqlerrm,
            null, jsonb_build_object('job_id', v_job.job_id, 'leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'sqlstate', sqlstate)
          );
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_accrual_batch',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'accrued_count', v_accrued, 'skipped_count', v_skipped, 'failed_count', v_failed)
    );
  end if;

  accrued_count := v_accrued; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_leave_accrual_batch is
  'HRT-280 (decision 13), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete), mirrors app.generate_roster_schedule_assignments (HRT-279) exactly. Idempotent per (policy_version_id, period_label) via the ledger''s own unique idempotency_key -- re-running the SAME period for the SAME policy version is always a safe no-op, never a double-accrual. HRT-295: a genuine per-employee failure (anywhere in resolution/eligibility/posting, not merely the already-caught unique_violation replay case) is now caught (never aborts the whole batch transaction, which previously lost the just-enqueued app.jobs row entirely -- HRT-294 PLT-132) and durably recorded via app.capture_audit_event (action=run_leave_accrual_batch_item_failed) -- the job still reaches completed with a disclosed failed_count.';

-- ===========================================================================
-- 4. app.run_leave_carry_forward_batch (HRT-280, 20260730930000)
-- ===========================================================================

create or replace function app.run_leave_carry_forward_batch(p_tenant_id uuid, p_leave_type_id uuid, p_effective_date date, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (expired_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_job app.jobs;
  v_worker_id text;
  v_employee record;
  v_policy app.leave_type_policy_versions;
  v_current numeric;
  v_excess numeric;
  v_expired integer := 0;
  v_skipped integer := 0;
  v_failed integer := 0;
  v_key text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id and status = 'published';
  if not found then
    raise exception 'leave_type_not_available: % is not a published leave type in this tenant', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_effective_date is null or p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: p_effective_date and a non-empty p_period_label are required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'leave_carry_forward_expiry', jsonb_build_object('leave_type_id', p_leave_type_id, 'effective_date', p_effective_date, 'period_label', p_period_label),
    0, 'leave_carry_forward:' || p_leave_type_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-leave-carry-forward:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
      -- PLT-132 (HRT-295) fix: same shape as app.run_leave_accrual_batch
      -- above (this same migration) -- the whole per-employee body is now
      -- inside its own outer exception boundary.
      begin
        select * into v_policy from app.resolve_effective_leave_type_policy_version(p_tenant_id, p_leave_type_id, v_employee.branch_org_unit_id, p_effective_date) limit 1;
        if not found then
          v_skipped := v_skipped + 1;
          continue;
        end if;

        v_current := app.get_employee_leave_balance(p_tenant_id, v_employee.master_record_id, p_leave_type_id, p_effective_date - 1);
        v_excess := v_current - v_policy.carry_forward_max_units;
        if v_excess <= 0 then
          v_skipped := v_skipped + 1;
          continue;
        end if;

        v_key := 'carry_forward_expire:' || v_policy.id::text || ':' || p_period_label;
        begin
          insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, idempotency_key, created_by)
          values (p_tenant_id, v_employee.master_record_id, p_leave_type_id, 'carry_forward_expire', -v_excess, p_effective_date, v_policy.id, v_key, p_actor_label);
          v_expired := v_expired + 1;
        exception
          when unique_violation then
            v_skipped := v_skipped + 1;
        end;
      exception
        when query_canceled then
          -- See app.run_ticket_escalation_evaluation_batch above (this same
          -- migration) -- a genuine cancel/timeout must still abort the
          -- WHOLE batch, never be silently absorbed per-employee.
          raise;
        when others then
          v_failed := v_failed + 1;
          perform app.capture_audit_event(
            p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_carry_forward_batch_item_failed',
            'app.employees', v_employee.master_record_id, 'failure', sqlerrm,
            null, jsonb_build_object('job_id', v_job.job_id, 'leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'sqlstate', sqlstate)
          );
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_carry_forward_batch',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'expired_count', v_expired, 'skipped_count', v_skipped, 'failed_count', v_failed)
    );
  end if;

  expired_count := v_expired; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_leave_carry_forward_batch is
  'HRT-280 (decision 13, section 20 "carry-forward jobs"), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a single batch handles BOTH a real capped carry-forward AND a strict use-it-or-lose-it type (carry_forward_max_units=0) -- no second expiry mechanism (never a per-vintage/FIFO lot tracker, a disclosed V1 simplification: the whole balance in excess of the cap is forfeited as one ledger event, not the OLDEST accrual specifically). Idempotent per (policy_version_id, period_label), mirrors app.run_leave_accrual_batch exactly, including its HRT-295 per-employee exception boundary: a genuine per-employee failure is now caught (never aborts the whole batch transaction, which previously lost the just-enqueued app.jobs row entirely -- HRT-294 PLT-132) and durably recorded via app.capture_audit_event (action=run_leave_carry_forward_batch_item_failed) -- the job still reaches completed with a disclosed failed_count.';

-- ===========================================================================
-- 5. app.generate_roster_schedule_assignments (HRT-279, 20260730910000,
--    latest shape from 20260730960000)
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
  v_failed integer := 0;
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

  select array_agg(x order by x) into v_sorted_employee_ids from unnest(p_employee_ids) x;
  v_natural_key := 'roster_generation:' || p_roster_cycle_id::text || ':' || p_from_date::text || ':' || p_to_date::text
    || ':' || array_to_string(v_sorted_employee_ids, ',');

  v_job := app.enqueue_job(
    p_tenant_id, 'roster_generation',
    jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'from_date', p_from_date, 'to_date', p_to_date, 'employee_count', array_length(p_employee_ids, 1)),
    0, v_natural_key, 1, p_actor_auth_user_id, p_actor_label
  );

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
                    -- Pre-existing, unchanged (Batch 278-280 Tier C, HRT-279):
                    -- the already-verified, already-tested "expected business
                    -- rejection" allowlist -- left completely untouched so no
                    -- already-passing skipped_count assertion regresses.
                    v_skipped := v_skipped + 1;
                  when query_canceled then
                    -- See app.run_ticket_escalation_evaluation_batch above
                    -- (this same migration) -- a genuine cancel/timeout must
                    -- still abort the WHOLE batch, never be silently
                    -- absorbed per-employee-day.
                    raise;
                  when others then
                    -- PLT-132 (HRT-295) fix: anything OUTSIDE the allowlist
                    -- above previously still escaped uncaught, aborting the
                    -- whole batch transaction and losing the just-enqueued
                    -- app.jobs row entirely (see this migration's own
                    -- header). Now durably recorded and the loop continues.
                    v_failed := v_failed + 1;
                    perform app.capture_audit_event(
                      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_roster_schedule_assignments_item_failed',
                      'app.employees', v_employee_id, 'failure', sqlerrm,
                      null, jsonb_build_object('job_id', v_job.job_id, 'roster_cycle_id', p_roster_cycle_id, 'work_date', v_day, 'sqlstate', sqlstate)
                    );
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
      jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'created_count', v_created, 'superseded_count', v_superseded, 'skipped_count', v_skipped, 'failed_count', v_failed)
    );
  end if;

  created_count := v_created; superseded_count := v_superseded; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.generate_roster_schedule_assignments is
  'HRT-279 (decision 8), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row, tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Batch 278-280 Tier C fix (idempotency, MEDIUM): derives a natural idempotency key from (roster_cycle_id, from_date, to_date, sorted employee_id set) and only runs the generation loop when app.enqueue_job genuinely created a fresh pending job. Its own pre-existing four-code allowlist (insufficient_privilege/check_violation/no_data_found/unique_violation -> silently skipped) is unchanged; HRT-295 adds a new when-others branch AFTER it for exactly the exception classes that allowlist never covered -- previously still able to abort the whole batch transaction and lose the just-enqueued app.jobs row entirely (HRT-294 PLT-132) -- now durably recorded via app.capture_audit_event (action=generate_roster_schedule_assignments_item_failed) with a disclosed failed_count, and the job still reaches completed.';
