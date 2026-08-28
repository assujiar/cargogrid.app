-- Scenario 3 (CG-S10-ATW-024, Prompt 243): app.claim_next_job under a large
-- enqueued backlog -- measures queue age and claim throughput under concurrent
-- claimers. Each transaction is one fast synthetic worker cycle: claim one job,
-- then immediately complete it (models scripts/load-tests/job-poll-worker.sh's
-- own claim/process/ack loop at pgbench-driven concurrency, rather than the
-- slower bash polling loop, for throughput measurement purposes -- the bash
-- script itself is the scope-bounded, explicitly-disclosed test-only soak driver,
-- see its own header). No-op (never errors) once the backlog is fully drained.
--
-- Disclosure added ISS-2026-141/148 (Track B Batch 5): this job_type array
-- (and scripts/load-tests/seed.sql's own matching 5,000-row backlog,
-- seed.sql:355) predates Phase 8/9 (dated 2026-07/08, before either phase's
-- own 20260801*/20260804*+ migration range) but genuinely already covers, at
-- volume, the generic CLAIM/COMPLETE throughput of the exact job_type values
-- that back one Phase 8 and four Phase 9 async capabilities: `loyalty_
-- expiration` (Phase 8, CPL-323 tier/point expiration worker),
-- `report_generation`/`dashboard_refresh` (Phase 9, the reporting engine and
-- dashboard-builder materialized-view refresh), `webhook_retry` (Phase 9,
-- the webhook delivery worker), and `integration_sync` (Phase 9, Integration
-- Hub). This was never disclosed anywhere in docs/runtime/KNOWN_ISSUES.md
-- before this pass -- both ISS-2026-141 and ISS-2026-148 describe "zero
-- load/performance-test evidence... for any Phase 8/9 route or RPC," which
-- remains true for the actual per-job-type HANDLER logic (this scenario
-- proves only the shared queue's own claim-once/no-double-claim/throughput
-- properties, generic across every job_type, never what an individual
-- report_generation or webhook_retry job handler itself does once claimed)
-- and for every SYNCHRONOUS route/RPC of either phase, but the async
-- background-dispatch layer specifically is not a total blank the way the
-- entries' own "zero... any Phase 8/9 route or RPC" framing could be read to
-- imply -- narrowing, not closing, either gap.
do $$
declare
  v_worker text := 'loadtest-worker-' || pg_backend_pid()::text;
  v_job app.jobs;
begin
  v_job := app.claim_next_job(
    v_worker,
    array['report_generation', 'notification_batch', 'webhook_retry', 'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync'],
    300
  );
  if v_job.job_id is not null then
    perform app.complete_job(v_job.job_id, v_worker, null, 'loadtest-pgbench');
  end if;
end $$;
