-- Tier C review of Prompt 295 (CG-S12-HRT-023, HRT-295) -- closes the
-- residual gap in HRT-295's own ISS-2026-112 (PLT-132 dead-letter) fix
-- (20260731260000) that the spec-compliance and security review lenses
-- both independently live-reproduced: a GENUINE statement_timeout/operator
-- cancellation mid-loop still reproduces ISS-2026-112's own exact original
-- defect (the batch's own just-enqueued app.jobs row vanishes with zero
-- trace anywhere) for all five hardened functions, because
-- 20260731260000's own inner per-item `when query_canceled then raise;`
-- correctly refuses to treat a cancellation as "this one item failed,
-- continue" but then has nothing outside the loop to catch the re-raised
-- exception -- it propagates all the way out of the function, rolling back
-- the whole transaction including app.enqueue_job's own earlier INSERT.
-- Never edits 20260731260000 itself (already shipped in this same
-- checkpoint) -- CREATE OR REPLACE FUNCTION again, next free timestamp.
--
-- ===========================================================================
-- Independently re-derived before writing this fix (own reproduction, not
-- accepted from any lens report).
-- ===========================================================================
--
-- set statement_timeout = '15ms'; select app.run_ticket_escalation_
-- evaluation_batch(<tenant>, now(), '<period>', <admin>, 'admin') against a
-- real backdated-inactivity ticket fixture -> ERROR: canceling statement
-- due to statement timeout, cancellation landing inside the per-item loop
-- (after app.enqueue_job already ran) -> select count(*) from app.jobs
-- where idempotency_key = '...' -> 0 rows, neither pending nor dead_letter
-- -- ISS-2026-112's own exact original live reproduction, byte for byte,
-- reproduced against 20260731260000's own shipped code.
--
-- Postgres statement_timeout semantics independently verified live (own
-- disposable-database probe, a standalone plpgsql function, not asserted
-- from documentation alone) before designing this fix: (1) a PL/pgSQL
-- EXCEPTION block that catches query_canceled WITHOUT re-raising allows
-- further statements in the SAME top-level call to execute and COMMIT
-- normally, and the caller receives an ordinary successful return, no
-- error -- the one-shot statement_timeout alarm is consumed by its first
-- firing and is not re-armed for the remainder of that same top-level
-- statement's execution; (2) catching query_canceled and then RE-RAISING
-- rolls back everything the handler itself did too, including any cleanup
-- writes, and the caller sees the ERROR -- confirmed with a real forged
-- `set statement_timeout` + real writes in both branches. This means the
-- ONLY way to make the job row durably survive a genuine mid-loop
-- cancellation, in this repository's existing single-transaction "inline
-- batch" architecture (no out-of-process worker/second transaction exists
-- anywhere, per 20260731260000's own header), is to catch query_canceled
-- OUTSIDE the loop and NOT re-raise it further -- returning a normal,
-- clearly partial result to the caller instead of an opaque connection
-- error that leaves no server-side trace at all.
--
-- ===========================================================================
-- Fix: an OUTER exception boundary around each function's own "loop +
-- complete_job + success audit event" block, catching query_canceled ONLY.
-- ===========================================================================
--
-- The INNER per-item `when query_canceled then raise;` (20260731260000,
-- unchanged here) still does exactly what its own comment says: a genuine
-- cancellation is never silently absorbed as "this one item failed, try
-- the next" -- it is re-raised immediately, and the loop stops. What
-- changes is what happens to that re-raised exception next: instead of
-- falling all the way out of the function (destroying the job row), it is
-- now caught by a new OUTER handler wrapped around the whole "acquire
-- lease + loop + complete_job + success audit" block. That handler:
--   1. Does NOT resume the loop -- no further items are evaluated, exactly
--      the behavior a genuine operator cancellation or an organically
--      exhausted statement_timeout budget should produce (stop working
--      immediately), never "silently absorbed as a per-item failure and
--      carry on".
--   2. Calls app.record_job_failure(v_job.job_id, ...) -- the SAME real
--      PLT-132 retry/dead-letter primitive ISS-2026-112 named as never
--      reached. Re-read in full before use (20260719180000): it requires
--      only that the job is not ALREADY terminal (completed/cancelled/
--      dead_letter) -- unlike app.complete_job, it does NOT require
--      status='in_progress' AND locked_by=<this worker>, so it is safe to
--      call here even though the job's own lease bookkeeping was never
--      released by a normal exit path. It correctly increments attempts
--      and transitions the job to 'pending' (with a real exponential-
--      backoff next_attempt_at) or 'dead_letter' (once max_attempts is
--      reached) -- the exact mechanism this finding's own title says was
--      never reached, now genuinely reached for this failure mode too.
--   3. Records its own richer, function-specific audit event (evaluated/
--      accrued/created count so far, tenant, period_label) alongside
--      record_job_failure's own generic one, so an operator sees BOTH the
--      generic job-framework failure record AND the batch-specific partial
--      progress in one place.
--   4. Does NOT re-raise -- per the verified Postgres semantics above, this
--      is the only way the job-preserving writes above can actually
--      persist. The caller's top-level call therefore now returns
--      NORMALLY (the SAME evaluated_count/job_id output shape every
--      successful call already returns, just with a smaller count and a
--      job now sitting in pending/dead_letter rather than completed) --
--      never an opaque `ERROR: canceling statement due to statement
--      timeout` with nothing left to show for it server-side. A caller
--      that specifically wants to know whether THIS invocation was
--      interrupted can already tell, without any new output column: the
--      job's own status (queryable via app.jobs, already RLS-visible to
--      authenticated per PLT-131/132's own established policy) is
--      'pending'/'dead_letter' instead of 'completed'.
--
-- This does NOT weaken the inner per-item catch's own guarantee -- an
-- ordinary per-item business failure (a real check_violation/no_data_found/
-- etc.) is still caught, recorded, and the loop still continues to the
-- next item exactly as 20260731260000 shipped; only a genuine
-- query_canceled now additionally survives at the batch level instead of
-- destroying the job row.
--
-- Regression proof (own, new -- scripts/db-tests/ticketing-escalation.sql
-- and scripts/db-tests/ticketing-sla.sql, this same batch): a REAL forged
-- `set statement_timeout` mid-loop cancellation against a real fixture,
-- proving (a) the top-level call now returns NORMALLY (no error), (b) the
-- job row survives in 'pending' or 'dead_letter' -- never absent, (c) a
-- durable, findable app.audit_logs row names the interruption and the
-- partial evaluated_count, and (d) a subsequent retry of the SAME
-- (still-'pending') job via a second call to the same RPC with the SAME
-- idempotency key completes the remaining work correctly (per-item
-- idempotency, already established by 20260731260000/its own predecessor
-- migrations, makes a full re-run of all eligible items safe).
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

    -- HRT-295 Tier C fix: outer boundary -- see this migration's own header
    -- for the full reasoning. Catches ONLY the re-raised query_canceled a
    -- genuine mid-loop cancellation produces; any other exception here
    -- would be a genuine bug in this function's own control flow, not a
    -- per-item business condition (those are already caught below), so it
    -- is deliberately left to propagate.
    begin
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
            -- abort the WHOLE per-item loop, never be silently absorbed as
            -- "this one ticket failed" -- WHEN OTHERS below would otherwise
            -- catch query_canceled too (a real, documented PL/pgSQL
            -- gotcha), which would defeat an operator's own deliberate
            -- attempt to stop a runaway batch. Re-raised to the new OUTER
            -- boundary immediately below, which preserves the job row
            -- instead of letting it vanish (HRT-295 Tier C fix).
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
    exception
      when query_canceled then
        -- HRT-295 Tier C fix: preserve the job row via the framework's OWN
        -- real record_job_failure mechanism instead of letting the whole
        -- transaction (including enqueue_job's own earlier insert) roll
        -- back and vanish -- closing ISS-2026-112's own exact live
        -- reproduction for the interrupted-batch case. Deliberately NOT
        -- re-raised (verified live: re-raising here would roll back this
        -- handler's own writes too) -- the caller's top-level call now
        -- returns normally, with a partial evaluated_count, instead of an
        -- opaque connection error and zero server-side trace.
        perform app.record_job_failure(
          v_job.job_id,
          format('batch_interrupted: query_canceled after evaluating %s ticket(s) of the eligible set', v_evaluated),
          p_actor_auth_user_id, p_actor_label
        );
        perform app.capture_audit_event(
          p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_escalation_evaluation_batch_interrupted',
          'app.jobs', v_job.job_id, 'failure', 'query_canceled',
          null, jsonb_build_object('period_label', p_period_label, 'evaluated_count', v_evaluated, 'failed_count', v_failed)
        );
    end;
  end if;

  evaluated_count := v_evaluated; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_ticket_escalation_evaluation_batch is
  'HRT-291 (decisions 6/8/9/10), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Idempotent per (tenant, period_label) at the JOB level (a replayed period is a pending-status no-op), AND every individual ticket evaluation inside the loop is separately idempotent at the LEDGER level regardless of job replay -- two independent, overlapping guarantees, mirroring app.run_ticket_sla_evaluation_batch (HRT-289) exactly. Also re-evaluates any ticket with a still-open escalation regardless of its own current status/channel filter, so a closed ticket''s dangling escalation is still resolved (C-18). HRT-295: a genuine per-ticket evaluation failure is caught (never aborts the whole batch transaction) and durably recorded via app.capture_audit_event (action=run_ticket_escalation_evaluation_batch_item_failed) -- the job still reaches completed with a disclosed failed_count. Tier C review fix (20260731290000): a genuine query_canceled (statement_timeout or operator cancellation) mid-loop no longer destroys the job row either -- an outer boundary calls app.record_job_failure (real pending/dead_letter transition) and returns normally with a partial evaluated_count, closing ISS-2026-112''s own exact original reproduction for this failure mode too.';

-- ===========================================================================
-- 2. app.run_ticket_sla_evaluation_batch (HRT-289, 20260731120000, hardened
--    by 20260731260000) -- identical shape/reasoning to #1 above.
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

    -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
    -- above (this same migration) for the full reasoning.
    begin
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
            -- See app.run_ticket_escalation_evaluation_batch above (this
            -- same migration) -- re-raised to the new outer boundary
            -- immediately below.
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
    exception
      when query_canceled then
        -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
        -- above (this same migration) -- preserves the job row via
        -- app.record_job_failure and returns normally.
        perform app.record_job_failure(
          v_job.job_id,
          format('batch_interrupted: query_canceled after evaluating %s clock(s) of the eligible set', v_evaluated),
          p_actor_auth_user_id, p_actor_label
        );
        perform app.capture_audit_event(
          p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_sla_evaluation_batch_interrupted',
          'app.jobs', v_job.job_id, 'failure', 'query_canceled',
          null, jsonb_build_object('period_label', p_period_label, 'evaluated_count', v_evaluated, 'failed_count', v_failed)
        );
    end;
  end if;

  evaluated_count := v_evaluated; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_ticket_sla_evaluation_batch is
  'HRT-289 (decisions 6/8), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Idempotent per (tenant, period_label) at the JOB level, AND every individual clock evaluation inside the loop is separately idempotent at the LEDGER level regardless of job replay. HRT-295: a genuine per-clock evaluation failure is caught and durably recorded via app.capture_audit_event (action=run_ticket_sla_evaluation_batch_item_failed) -- the job still reaches completed with a disclosed failed_count. Tier C review fix (20260731290000): a genuine query_canceled mid-loop no longer destroys the job row either -- an outer boundary calls app.record_job_failure and returns normally with a partial evaluated_count.';

-- ===========================================================================
-- 3. app.run_leave_accrual_batch (HRT-280, 20260730930000, hardened by
--    20260731260000) -- identical shape/reasoning to #1 above.
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

    -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
    -- above (this same migration) for the full reasoning.
    begin
      for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
        -- PLT-132 (HRT-295) fix: the WHOLE per-employee body (resolution,
        -- eligibility gates, AND the ledger insert) is inside its own outer
        -- exception boundary -- see this migration's own header. `continue`
        -- used inside this outer block still targets the enclosing FOR loop
        -- correctly (a plain BEGIN/END block is not itself a loop).
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
            -- See app.run_ticket_escalation_evaluation_batch above (this
            -- same migration) -- re-raised to the new outer boundary
            -- immediately below.
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
    exception
      when query_canceled then
        -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
        -- above (this same migration).
        perform app.record_job_failure(
          v_job.job_id,
          format('batch_interrupted: query_canceled after processing %s employee(s) of the eligible set (accrued=%s, skipped=%s)', v_accrued + v_skipped, v_accrued, v_skipped),
          p_actor_auth_user_id, p_actor_label
        );
        perform app.capture_audit_event(
          p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_accrual_batch_interrupted',
          'app.jobs', v_job.job_id, 'failure', 'query_canceled',
          null, jsonb_build_object('leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'accrued_count', v_accrued, 'skipped_count', v_skipped, 'failed_count', v_failed)
        );
    end;
  end if;

  accrued_count := v_accrued; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_leave_accrual_batch is
  'HRT-280 (decision 13), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete), mirrors app.generate_roster_schedule_assignments (HRT-279) exactly. Idempotent per (policy_version_id, period_label) via the ledger''s own unique idempotency_key. HRT-295: a genuine per-employee failure is caught and durably recorded via app.capture_audit_event (action=run_leave_accrual_batch_item_failed) -- the job still reaches completed with a disclosed failed_count. Tier C review fix (20260731290000): a genuine query_canceled mid-loop no longer destroys the job row either -- an outer boundary calls app.record_job_failure and returns normally with partial accrued/skipped counts.';

-- ===========================================================================
-- 4. app.run_leave_carry_forward_batch (HRT-280, 20260730930000, hardened
--    by 20260731260000) -- identical shape/reasoning to #3 above.
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

    -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
    -- above (this same migration) for the full reasoning.
    begin
      for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
        -- PLT-132 (HRT-295) fix: same shape as app.run_leave_accrual_batch
        -- above (this same migration) -- the whole per-employee body is
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
            -- See app.run_ticket_escalation_evaluation_batch above (this
            -- same migration) -- re-raised to the new outer boundary
            -- immediately below.
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
    exception
      when query_canceled then
        -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
        -- above (this same migration).
        perform app.record_job_failure(
          v_job.job_id,
          format('batch_interrupted: query_canceled after processing %s employee(s) of the eligible set (expired=%s, skipped=%s)', v_expired + v_skipped, v_expired, v_skipped),
          p_actor_auth_user_id, p_actor_label
        );
        perform app.capture_audit_event(
          p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_carry_forward_batch_interrupted',
          'app.jobs', v_job.job_id, 'failure', 'query_canceled',
          null, jsonb_build_object('leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'expired_count', v_expired, 'skipped_count', v_skipped, 'failed_count', v_failed)
        );
    end;
  end if;

  expired_count := v_expired; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_leave_carry_forward_batch is
  'HRT-280 (decision 13, section 20 "carry-forward jobs"), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a single batch handles BOTH a real capped carry-forward AND a strict use-it-or-lose-it type. Idempotent per (policy_version_id, period_label). HRT-295: a genuine per-employee failure is caught and durably recorded (action=run_leave_carry_forward_batch_item_failed) -- the job still reaches completed with a disclosed failed_count. Tier C review fix (20260731290000): a genuine query_canceled mid-loop no longer destroys the job row either -- an outer boundary calls app.record_job_failure and returns normally with partial expired/skipped counts.';

-- ===========================================================================
-- 5. app.generate_roster_schedule_assignments (HRT-279, 20260730910000,
--    latest shape from 20260730960000, hardened by 20260731260000).
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

    -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
    -- above (this same migration) for the full reasoning.
    begin
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
                      -- (this same migration) -- re-raised to the new outer
                      -- boundary below (around the whole foreach loop).
                      raise;
                    when others then
                      -- PLT-132 (HRT-295) fix: anything OUTSIDE the allowlist
                      -- above is durably recorded and the loop continues.
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
    exception
      when query_canceled then
        -- HRT-295 Tier C fix: see app.run_ticket_escalation_evaluation_batch
        -- above (this same migration).
        perform app.record_job_failure(
          v_job.job_id,
          format('batch_interrupted: query_canceled after processing %s employee-day slot(s) (created=%s, superseded=%s, skipped=%s)', v_created + v_superseded + v_skipped, v_created, v_superseded, v_skipped),
          p_actor_auth_user_id, p_actor_label
        );
        perform app.capture_audit_event(
          p_tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_roster_schedule_assignments_interrupted',
          'app.jobs', v_job.job_id, 'failure', 'query_canceled',
          null, jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'created_count', v_created, 'superseded_count', v_superseded, 'skipped_count', v_skipped, 'failed_count', v_failed)
        );
    end;
  end if;

  created_count := v_created; superseded_count := v_superseded; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.generate_roster_schedule_assignments is
  'HRT-279 (decision 8), PLT-132 hardened by HRT-295 (CG-S12-HRT-023): a real app.jobs row, tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Batch 278-280 Tier C fix (idempotency, MEDIUM): derives a natural idempotency key from (roster_cycle_id, from_date, to_date, sorted employee_id set). Its own pre-existing four-code allowlist (insufficient_privilege/check_violation/no_data_found/unique_violation -> silently skipped) is unchanged; HRT-295 adds a when-others branch AFTER it, durably recorded via app.capture_audit_event (action=generate_roster_schedule_assignments_item_failed) with a disclosed failed_count. Tier C review fix (20260731290000): a genuine query_canceled mid-loop no longer destroys the job row either -- an outer boundary calls app.record_job_failure and returns normally with partial created/superseded/skipped counts.';
