-- HDN-382 (Observability Audit, Prompt 382, CG-S15-HDN-014), first round.
--
-- Three independent investigation lenses converged on one headline, live-reproduced
-- finding: IAE-030's own enterprise monitoring/alerting schema (app.raise_observability_
-- alert, app.record_observability_signal -- real dedup, real severity, real owner
-- routing, 100% passing its own db-tests) has ZERO real production callers anywhere in
-- this codebase. Live-forced directly (Lens 2): a job driven through the real DLQ path
-- (app.enqueue_job -> app.claim_next_job -> app.record_job_failure with max_attempts=1)
-- reaches a genuine, terminal `dead_letter` status with zero incident, zero alert, zero
-- owner notification -- only an app.audit_logs row a human would have to go looking for.
-- This directly contradicts Prompt 382's own Main Flow (§21: "A job/webhook/API/database
-- failure produces actionable alert") and Business Rule §24 ("No silent DLQ/backpressure
-- accumulation") for the single most common real failure path in this repository.
--
-- Wiring EVERY failure producer (webhook delivery, AI governed-action failure, security
-- denials) into the alerting system in one checkpoint would exceed this lane's own
-- "5-15 files, bounded repair" charter -- the remaining producers are registered, not
-- fixed, each with a named owner (see docs/runtime/KNOWN_ISSUES.md ISS-2026-249). This
-- migration wires the highest-value, most common path: app.record_job_failure's own
-- dead-letter transition, the terminal state every job type in this repository shares.
--
-- Second fix: docs/runbooks/observability-exporter-outage.md's own diagnosis step 1
-- instructs an on-call responder to check `/api/health`/`/api/ready`, describing them as
-- "implemented Phase 1" -- both lenses that read the runbook confirmed neither route
-- exists anywhere in app/api (a live 404 during a real incident). docs/standards/
-- OBSERVABILITY_STANDARDS.md §7 already fixed the exact readiness contract; this
-- migration adds the one piece of DB-side plumbing that contract requires (`/api/ready`
-- "additionally checks DB connectivity") -- a trivial, side-effect-free, tenant-data-free
-- connectivity probe. The route handlers themselves are added in the same TypeScript
-- commit as this migration, not here.

-- ===========================================================================
-- 1. app.record_job_failure: dead-letter transition now raises a real, deduplicated
-- observability alert (source_type='job', signal_type='error') instead of silently
-- landing only in app.jobs/app.audit_logs. Same signature, same exception prefixes as
-- every prior CREATE OR REPLACE of this function (see this repository's own extension
-- convention, most recently 20260719180000_create_background_job_framework.sql).
-- ===========================================================================

create or replace function app.record_job_failure(
  p_job_id uuid,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_new_attempts integer;
  v_dead_letter boolean;
  v_backoff_seconds integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status in ('completed', 'cancelled', 'dead_letter') then
    raise exception 'import_export_job_already_terminal: job % is already %, cannot record a failure', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  v_new_attempts := v_job.attempts + 1;
  v_dead_letter := v_new_attempts >= v_job.max_attempts;
  v_backoff_seconds := case when v_dead_letter then null else app.compute_job_backoff_seconds(v_new_attempts) end;

  update app.jobs
  set attempts = v_new_attempts,
      error = p_error_message,
      status = case when v_dead_letter then 'dead_letter' else 'pending' end,
      completed_at = case when v_dead_letter then now() else null end,
      locked_by = null,
      locked_until = null,
      next_attempt_at = case when v_dead_letter then null else now() + (v_backoff_seconds || ' seconds')::interval end
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_job_failure',
    'app.jobs', p_job_id, 'failure', p_error_message,
    jsonb_build_object('attempts', v_job.attempts, 'status', v_job.status),
    jsonb_build_object('attempts', v_updated.attempts, 'status', v_updated.status, 'next_attempt_at', v_updated.next_attempt_at)
  );

  -- HDN-382: a job reaching its own terminal, unrecovered dead_letter state is exactly
  -- the "silent DLQ accumulation" Business Rule §24 forbids -- raise a real, deduplicated
  -- incident rather than leaving this discoverable only via a manual app.jobs query.
  -- High severity: work has genuinely stopped for this job, unactioned, with no
  -- automatic retry remaining. app.raise_observability_alert already deduplicates
  -- repeat breaches of the same (tenant_id, source_type, signal_type) within its own
  -- alert route's window (or a 30-minute default) -- a burst of same-tenant job
  -- failures collapses into one incident plus duplicate_signal timeline events, not one
  -- incident per job (the correct behavior; ISS-2026-155's own known, disclosed,
  -- separately-owned granularity gap is unrelated to this specific call site and is not
  -- being re-litigated here).
  if v_dead_letter then
    perform app.raise_observability_alert(
      v_job.tenant_id,
      'job',
      'error',
      format('job dead-lettered: %s', v_job.job_type),
      'high',
      p_error_message
    );
  end if;

  return v_updated;
end;
$$;

comment on function app.record_job_failure is
  'PLT-131/PLT-132, extended HDN-382: on the dead_letter transition (final attempt exhausted), also raises a real, deduplicated observability alert via app.raise_observability_alert (source_type=''job'', signal_type=''error'', severity=''high'') -- closes the live-reproduced gap where a job could silently exhaust all retries with zero incident/alert/owner notification, only an audit-log row a human would have to go looking for (docs/build-log/full-system-hardening/HDN-382.md).';

-- ===========================================================================
-- 2. app.ping(): a trivial, side-effect-free, tenant-data-free DB connectivity probe
-- for /api/ready (docs/standards/OBSERVABILITY_STANDARDS.md §7's own already-fixed
-- readiness contract: "/api/ready additionally checks DB connectivity and returns 503
-- ... on failure -- never a false 'ok'"). Deliberately touches no application table --
-- a readiness probe that queried real tenant data would itself be the tenant-data-leak
-- risk Prompt 382 §14 warns against, and would add load to a hot path for no benefit
-- (proving the connection is alive requires no more than a trivial round trip).
-- ===========================================================================

create function app.ping()
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select true;
$$;

comment on function app.ping() is
  'HDN-382: side-effect-free DB connectivity probe for /api/ready. Touches no application data and requires no actor/tenant context -- exists purely to prove the database connection itself is alive, never a substitute for app.capture_audit_event or any other real business RPC.';

-- Every prior migration's own established convention (e.g. 20260717095000, 20260730950000):
-- a brand-new function created by this same migration-applying role otherwise retains an
-- implicit PUBLIC EXECUTE grant the moment any explicit GRANT statement first materializes
-- its ACL -- this blanket revoke is the actual operative mechanism, not merely
-- defense-in-depth, exactly as every other migration in this repository already relies on.
revoke execute on all functions in schema app from public;

grant execute on function app.ping() to service_role;
