-- Scenario 2b (CG-S10-ATW-024, Prompt 243): concurrent WMS putaway-task claiming
-- (ATW-014's app.claim_wms_putaway_task) under many simulated concurrent workers.
-- See scripts/load-tests/pgbench/wms-pick-claim.sql's own header for why
-- loadtest.claim_any_putaway_task exists.
-- __ADMIN_ACTOR_ID__ is a sed-rendered placeholder -- see inventory-movement.sql's
-- own header for why (pgbench's own quoted-variable substitution is not used).
select loadtest.claim_any_putaway_task('__ADMIN_ACTOR_ID__', 'loadtest-pgbench-worker-' || pg_backend_pid());
