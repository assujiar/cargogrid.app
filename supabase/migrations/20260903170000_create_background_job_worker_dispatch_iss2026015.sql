-- ISS-2026-015 (and ISS-2026-070 item 2's remaining half): nothing in this repository polls
-- `app.jobs` and executes what it finds. Jobs are enqueued from 31 distinct places and none of
-- them has ever run.
--
-- ===========================================================================
-- What was already here, and what genuinely was not
-- ===========================================================================
--
-- The job FRAMEWORK is complete and well built, and this migration adds nothing to it:
-- `app.claim_next_job` locks with `for update skip locked`, honours priority, respects
-- `next_attempt_at` backoff, and counts a lease-expiry re-claim as an attempt so a crash-looping
-- job cannot occupy a worker forever; `app.record_job_failure` applies exponential backoff via
-- `app.compute_job_backoff_seconds` and dead-letters at `max_attempts`; `app.complete_job`
-- refuses a worker that does not hold the lease; `app.heartbeat_job` and
-- `app.requeue_dead_letter_job` exist. None of that needed building.
--
-- The missing piece was the one in the middle: **a dispatcher that takes a claimed job and
-- actually performs the work its `job_type` names**, and a loop that drives claim -> execute ->
-- complete/fail. That is what this migration adds, mirroring `app._run_scheduled_task_once` /
-- `app.run_due_scheduled_tasks` (20260831090000) rather than inventing a second shape.
--
-- ===========================================================================
-- The honest boundary: which job types a database CAN execute
-- ===========================================================================
--
-- 33 job types are registered. Most of them cannot be executed by Postgres at all, and pretending
-- otherwise would be the worst possible outcome here -- a job marked `completed` whose work never
-- happened is strictly worse than a job that never ran, because it destroys the evidence that it
-- is outstanding.
--
-- `webhook_retry`, `notification_batch`, `integration_sync`, `external_sync`,
-- `logistics_partner_sync`, `finance_bank_feed_sync`, `print_label`, `document_generation`,
-- `report_generation`, `audit_export` and friends are **external handoffs**. This repository is
-- explicit about that split by design: `app.get_webhook_delivery_dispatch_info` and
-- `app.get_notification_dispatch_info` hand an outside process what it needs, and
-- `app.record_webhook_delivery_attempt` / `app.record_notification_delivery_attempt` record what
-- came back. The database prepares and records; something outside performs the network call.
--
-- So `app.dispatchable_job_types()` names ONLY the job types with a real in-database executor,
-- and `app.run_due_jobs` claims only those. Everything else stays `pending` and unclaimed --
-- visible, queryable, and honestly outstanding -- rather than being claimed and dead-lettered for
-- a failure that is not the job's fault. `scripts/jobs/run-worker.ts`, added alongside this
-- migration, is the process that closes the other half.
--
-- ===========================================================================
-- Authority: a job runs as whoever enqueued it, re-checked every run
-- ===========================================================================
--
-- Every executor below is permission-gated and takes an actor. The worker passes the job's own
-- `requested_by_auth_user_id` -- the real person whose action enqueued the work -- exactly as the
-- scheduler passes `authorized_by_auth_user_id`. Nothing runs as "the system", nothing new is
-- minted, and every audit row a job writes names somebody accountable. If that person's rights
-- have since been revoked the executor raises, the job fails, backs off, and eventually
-- dead-letters with the authority error recorded -- which is the correct outcome, not a bug.
--
-- ===========================================================================
-- Live schema re-verified before writing this file
-- ===========================================================================
--
--   * All 9 executors dispatched below were confirmed to exist with the exact signatures used
--     here, read from the hosted project via pg_get_function_identity_arguments -- not assumed
--     from a migration file.
--   * app.claim_next_job(text, text[], integer) returns app.jobs and returns NULL (an all-null
--     row) when nothing is due, which is why the loop tests `job_id is null` rather than `found`.
--   * app.complete_job raises `job_lease_not_held` unless the caller holds the lease, so the
--     worker id passed to complete must be the same one that claimed.

-- ===========================================================================
-- STEP 1: the dispatchable set.
--
-- Deliberately a function rather than a constant, so `app.run_due_jobs` and the db-tests read the
-- SAME list and cannot drift, and so adding an executor later is one migration touching one
-- place.
-- ===========================================================================

create function app.dispatchable_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'kb_article_expiry',
    'incident_escalation_sweep',
    'leave_accrual',
    'leave_carry_forward_expiry',
    'loyalty_benefit_issuance_sweep',
    'loyalty_earning_evaluation_sweep',
    'loyalty_expiry_sweep',
    'loyalty_points_posting_sweep',
    'loyalty_tier_recalculation_sweep'
  ]::text[];
$$;

comment on function app.dispatchable_job_types() is
  'ISS-2026-015: the job types app._execute_job_once can genuinely run inside the database, and therefore the only ones app.run_due_jobs claims. Every other registered job type is an external handoff (webhook delivery, notification send, integration sync, printing, document/report generation) that Postgres cannot perform -- those stay pending and unclaimed, which keeps them visibly outstanding instead of being claimed and dead-lettered for a failure that is not theirs. Read by both the worker and its regression test so the two cannot drift.';

-- Granted explicitly so this matches its public.* wrapper's grant set exactly. Postgres gives a
-- new function EXECUTE to PUBLIC by default, and scripts/db-tests/public-api-wrapper-regression.sql
-- refuses any wrapper whose grants differ from its app.* counterpart in EITHER direction -- it
-- caught this omission on the first run, which is precisely what that zero-tolerance check is for.
-- `authenticated` is deliberate here and only here: the list is a constant with no tenant data, so
-- an operations console can show which job types a worker will pick up.
revoke execute on function app.dispatchable_job_types() from public, anon;
grant execute on function app.dispatchable_job_types() to authenticated, service_role;

-- ===========================================================================
-- STEP 2: the dispatch itself. A CASE, never dynamic SQL assembled from the row -- job_type is
-- constraint-controlled today, but a worker that EXECUTEs a statement built from a table column
-- is one bad migration away from an injection surface. Same reasoning, same shape, as
-- app._run_scheduled_task_once.
-- ===========================================================================

create function app._execute_job_once(p_job app.jobs)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  -- The identity that enqueued the work. Every executor re-checks it; none of them trusts the
  -- worker itself, which holds no authority of its own.
  v_actor uuid := p_job.requested_by_auth_user_id;
  v_label text := 'job:' || p_job.job_type;
  -- A stable per-job idempotency label. Job id rather than the day, because two jobs of the same
  -- type for the same tenant on the same day are two genuinely different pieces of work, and a
  -- day-keyed label would make the second one a silent no-op inside the sweeps' own idempotency.
  v_period text := 'job:' || p_job.job_id::text;
  v_leave_type_id uuid;
begin
  case p_job.job_type
    when 'kb_article_expiry' then
      perform app.expire_kb_article_versions_batch(p_job.tenant_id, now(), v_period, v_actor, v_label);

    when 'incident_escalation_sweep' then
      perform app.run_incident_escalation_sweep(p_job.tenant_id, now(), v_period, v_actor, v_label);

    when 'leave_accrual' then
      v_leave_type_id := nullif(p_job.payload ->> 'leave_type_id', '')::uuid;
      if v_leave_type_id is null then
        raise exception 'job_payload_incomplete: a leave_accrual job requires payload.leave_type_id' using errcode = 'check_violation';
      end if;
      perform app.run_leave_accrual_batch(p_job.tenant_id, v_leave_type_id, current_date, v_period, v_actor, v_label);

    when 'leave_carry_forward_expiry' then
      v_leave_type_id := nullif(p_job.payload ->> 'leave_type_id', '')::uuid;
      if v_leave_type_id is null then
        raise exception 'job_payload_incomplete: a leave_carry_forward_expiry job requires payload.leave_type_id' using errcode = 'check_violation';
      end if;
      perform app.run_leave_carry_forward_batch(p_job.tenant_id, v_leave_type_id, current_date, v_period, v_actor, v_label);

    when 'loyalty_benefit_issuance_sweep' then
      perform app.run_loyalty_benefit_issuance_rule_sweep(p_job.tenant_id, now(), v_actor, v_label, v_period);

    when 'loyalty_earning_evaluation_sweep' then
      perform app.run_loyalty_earning_evaluation_sweep(p_job.tenant_id, now(), v_actor, v_label, v_period);

    when 'loyalty_expiry_sweep' then
      perform app.run_loyalty_expiry_sweep(p_job.tenant_id, now(), v_actor, v_label, v_period);

    when 'loyalty_points_posting_sweep' then
      perform app.run_loyalty_points_posting_sweep(p_job.tenant_id, now(), v_actor, v_label, v_period);

    when 'loyalty_tier_recalculation_sweep' then
      perform app.run_loyalty_tier_recalculation_sweep(p_job.tenant_id, now(), v_actor, v_label, v_period);

    else
      -- Defence in depth. app.run_due_jobs only ever claims app.dispatchable_job_types(), so this
      -- arm is unreachable through the worker; it exists so that a future migration that adds a
      -- type to that list without adding a branch here fails loudly on the first run instead of
      -- silently completing a job whose work never happened.
      raise exception 'job_type_not_dispatchable: % has no in-database executor', p_job.job_type
        using errcode = 'check_violation';
  end case;
end;
$$;

comment on function app._execute_job_once(app.jobs) is
  'ISS-2026-015 (internal, service_role-only): performs the work one claimed app.jobs row names. Deliberately a CASE rather than dynamic SQL built from the row -- a worker that EXECUTEs a statement assembled from a table column is one bad migration away from an injection surface. Runs as the job''s own requested_by_auth_user_id, so every executor''s permission gate is re-checked against the real person whose action enqueued it and every audit row names somebody accountable; the worker holds no authority of its own. A job_type with no branch raises rather than silently succeeding, which is the one outcome worse than not running at all.';

revoke execute on function app._execute_job_once(app.jobs) from public, anon, authenticated;
grant execute on function app._execute_job_once(app.jobs) to service_role;

-- ===========================================================================
-- STEP 3: the worker loop. This is the function an external process calls on a timer -- the same
-- entry-point shape as app.run_due_scheduled_tasks, so one process can drive both.
-- ===========================================================================

create function app.run_due_jobs(
  p_worker_id text,
  p_limit integer default 10,
  p_lease_seconds integer default 300
)
returns table (job_id uuid, tenant_id uuid, job_type text, outcome text, detail text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_processed integer := 0;
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 100);
begin
  if p_worker_id is null or length(trim(p_worker_id)) = 0 then
    raise exception 'job_worker_id_required: a worker id is required' using errcode = 'check_violation';
  end if;

  while v_processed < v_limit loop
    -- Claims ONLY the types this database can actually execute; everything else stays pending
    -- for the process that can. app.claim_next_job returns an all-null row when nothing is due.
    v_job := app.claim_next_job(p_worker_id, app.dispatchable_job_types(), p_lease_seconds);
    exit when v_job.job_id is null;

    v_processed := v_processed + 1;
    job_id := v_job.job_id;
    tenant_id := v_job.tenant_id;
    job_type := v_job.job_type;

    begin
      perform app._execute_job_once(v_job);
      perform app.complete_job(v_job.job_id, p_worker_id, null, 'worker:' || p_worker_id);
      outcome := 'completed';
      detail := null;
    exception
      -- Scoped to ONE job deliberately: a single bad job must never abort the rest of the batch,
      -- and the failure has to be recorded rather than lost. app.record_job_failure owns the
      -- retry/backoff/dead-letter decision; this handler does not second-guess it. The claim
      -- happened in an earlier statement so it survives this block's own rollback, which is what
      -- lets the failure be attributed to the right job.
      when others then
        outcome := 'failed';
        detail := sqlerrm;
        perform app.record_job_failure(v_job.job_id, sqlerrm, v_job.requested_by_auth_user_id, 'worker:' || p_worker_id);
    end;

    return next;
  end loop;

  return;
end;
$$;

comment on function app.run_due_jobs(text, integer, integer) is
  'ISS-2026-015: the background job worker''s database entry point -- claim, execute, complete or record failure, up to p_limit jobs per call. This is what an external process calls on a timer, and it is deliberately the same shape as app.run_due_scheduled_tasks so ONE process can drive both (see scripts/jobs/run-worker.ts). Claims only app.dispatchable_job_types(); every other registered type is an external handoff Postgres cannot perform and stays pending rather than being claimed and dead-lettered for a failure that is not its own. A failing job is isolated to its own BEGIN/EXCEPTION so it cannot abort the batch, and app.record_job_failure keeps ownership of the retry/backoff/dead-letter decision. Returns one row per job attempted, so the caller can log what actually happened rather than a bare count.';

revoke execute on function app.run_due_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function app.run_due_jobs(text, integer, integer) to service_role;

-- ===========================================================================
-- STEP 4: the RGL-394 Option-2 public.* wrappers. Every externally-callable app.* function needs
-- exactly one, enforced by scripts/db-tests/public-api-wrapper-regression.sql.
--
-- service_role ONLY for the worker loop -- an authenticated browser session must never be able to
-- drive the job queue. `dispatchable_job_types` is a harmless constant list and is readable by
-- authenticated too, so an operations console can show which types a worker will pick up.
-- ===========================================================================

-- SECURITY INVOKER, matching app.dispatchable_job_types(), which is a `language sql` IMMUTABLE
-- constant touching no table. The wrapper-regression test refuses any wrapper whose security mode
-- differs from its counterpart -- it is an RLS-bypass class check, and it caught a `security
-- definer` here on the first run. Definer would have been pointless privilege for a function that
-- reads nothing.
create function public.dispatchable_job_types()
returns text[]
language sql
immutable
set search_path = app, public, pg_temp
as $wrap$
  select app.dispatchable_job_types();
$wrap$;

comment on function public.dispatchable_job_types() is
  'RGL-394 Option-2 wrapper: a thin pass-through to app.dispatchable_job_types, never a reimplementation. SECURITY INVOKER, matching its counterpart -- the function is a constant list and needs no elevated privilege.';

revoke execute on function public.dispatchable_job_types() from anon, authenticated, service_role, public;
grant execute on function public.dispatchable_job_types() to authenticated, service_role;

create function public.run_due_jobs(p_worker_id text, p_limit integer default 10, p_lease_seconds integer default 300)
returns table (job_id uuid, tenant_id uuid, job_type text, outcome text, detail text)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_due_jobs(p_worker_id, p_limit, p_lease_seconds);
$wrap$;

comment on function public.run_due_jobs(text, integer, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_due_jobs, never a reimplementation. service_role only -- driving the job queue is a server-side act, never something a browser session performs.';

revoke execute on function public.run_due_jobs(text, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.run_due_jobs(text, integer, integer) to service_role;
