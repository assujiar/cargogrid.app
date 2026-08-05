-- Scenario 3 (CG-S10-ATW-024, Prompt 243): app.claim_next_job under a large
-- enqueued backlog -- measures queue age and claim throughput under concurrent
-- claimers. Each transaction is one fast synthetic worker cycle: claim one job,
-- then immediately complete it (models scripts/load-tests/job-poll-worker.sh's
-- own claim/process/ack loop at pgbench-driven concurrency, rather than the
-- slower bash polling loop, for throughput measurement purposes -- the bash
-- script itself is the scope-bounded, explicitly-disclosed test-only soak driver,
-- see its own header). No-op (never errors) once the backlog is fully drained.
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
