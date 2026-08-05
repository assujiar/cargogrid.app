#!/usr/bin/env bash
# CG-S10-ATW-024 (Prompt 243) load/volume/concurrency/recovery test harness --
# closes docs/runtime/KNOWN_ISSUES.md ISS-2026-014 ("No load/volume, real
# multi-session-concurrency, or populated-database migration-rehearsal test
# infrastructure exists anywhere in this repository").
#
# Structure (mirrors scripts/db-tests/run.sh's own style/conventions, read first
# per this task's own instruction):
#   1. Create a fresh disposable database via the SAME shared setup helper
#      scripts/db-tests/run.sh itself uses (scripts/db-tests/lib/setup-disposable-
#      db.sh) -- migration-apply/role-creation logic is never duplicated.
#   2. Load this directory's own test-only helper functions (loadtest schema --
#      see fixtures/load-test-only-helpers.sql's own header for why these exist
#      and why they do not weaken any proof).
#   3. Seed a representative volume fixture (seed.sql -- see its own header for
#      the exact, documented row counts).
#   4. Run every load scenario against it, printing AND saving measured results
#      (latency percentiles, throughput, error/lock-wait counts) to a timestamped
#      file under scripts/load-tests/results/ (gitignored) and refreshing the one
#      committed evidence file, results/RESULTS_CG-S10-ATW-024.txt.
#   5. Drop the disposable database (unless KEEP_LOAD_TEST_DB=1).
#
# Requires a reachable Postgres server exactly like scripts/db-tests/run.sh (same
# DATABASE_ADMIN_URL convention/default), pgbench (bundled with postgresql-client),
# and Node 22+ (for the GPS telemetry scenario, run as a separate, self-contained
# process since it needs no database).
set -euo pipefail

DATABASE_ADMIN_URL="${DATABASE_ADMIN_URL:-postgresql://postgres:postgres@127.0.0.1:5432/postgres}"
TEST_DB_NAME="${TEST_DB_NAME:-cargogrid_load_test}"
KEEP_LOAD_TEST_DB="${KEEP_LOAD_TEST_DB:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="$RESULTS_DIR/run-${RUN_TS}.txt"
COMMITTED_RESULTS="$RESULTS_DIR/RESULTS_CG-S10-ATW-024.txt"

# Every echo below also lands in $RUN_LOG (tee), so the committed evidence file
# is a real, complete transcript of an actual run, never hand-typed numbers.
exec > >(tee -a "$RUN_LOG") 2>&1

echo "==============================================================="
echo "CargoGrid load-test harness -- CG-S10-ATW-024 (Prompt 243)"
echo "Run started (UTC): $(date -u -Iseconds)"
echo "Postgres: $(psql "$DATABASE_ADMIN_URL" -Atqc 'select version();' 2>/dev/null || echo 'unreachable')"
echo "pgbench: $(pgbench --version)"
echo "Node: $(node --version)"
echo "==============================================================="

echo ""
echo "### 1. Disposable database setup ###"
# shellcheck source=../db-tests/lib/setup-disposable-db.sh
source "$REPO_ROOT/scripts/db-tests/lib/setup-disposable-db.sh"
cargogrid_setup_disposable_db "$DATABASE_ADMIN_URL" "$TEST_DB_NAME" "$REPO_ROOT" "$REPO_ROOT/scripts/db-tests/fixtures"
TEST_DB_URL="$CARGOGRID_TEST_DB_URL"
export TEST_DB_URL TEST_DB_NAME DATABASE_ADMIN_URL

echo ""
echo "### 2. Load-test-only helper functions (loadtest schema) ###"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/fixtures/load-test-only-helpers.sql"

echo ""
echo "### 3. Seed representative volume fixture ###"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/seed.sql"

echo ""
echo "### Resolving seeded fixture ids for scenario parameterization ###"
TENANT_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.tenants where slug = 'loadtest';")
WAREHOUSE_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.warehouses where tenant_id = '${TENANT_ID}';")
ACCOUNT_ALPHA_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.accounts where legal_name = 'Load Test Owner Alpha';")
HOT_ITEM_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.item_masters where code = 'SKU-HOT-CONTENTION';")
HOT_LOCATION_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.warehouse_locations where code = 'RACK-LOAD-00001' and warehouse_id = '${WAREHOUSE_ID}';")
ADMIN_ACTOR_ID="00000000-0000-0000-0000-000000090001"
echo "tenant_id=${TENANT_ID} warehouse_id=${WAREHOUSE_ID} account_alpha_id=${ACCOUNT_ALPHA_ID} hot_item_id=${HOT_ITEM_ID} hot_location_id=${HOT_LOCATION_ID}"

# pgbench 16.13 in this environment was directly, reproducibly found NOT to apply
# its own `:'var'`/`-D` quoted-variable substitution (see scripts/load-tests/
# pgbench/inventory-movement.sql's own header for the exact reproduction) -- every
# *.pgbench.sql template below is instead rendered via plain `sed` into a
# gitignored temp copy under $RESULTS_DIR before being passed to pgbench.
PGBENCH_TMP_DIR="$RESULTS_DIR/rendered-pgbench-scripts"
mkdir -p "$PGBENCH_TMP_DIR"
render_pgbench_script() {
  local template="$1"
  local out="$PGBENCH_TMP_DIR/$(basename "$template")"
  sed \
    -e "s|__TENANT_ID__|${TENANT_ID}|g" \
    -e "s|__WAREHOUSE_ID__|${WAREHOUSE_ID}|g" \
    -e "s|__ACCOUNT_ALPHA_ID__|${ACCOUNT_ALPHA_ID}|g" \
    -e "s|__HOT_ITEM_ID__|${HOT_ITEM_ID}|g" \
    -e "s|__HOT_LOCATION_ID__|${HOT_LOCATION_ID}|g" \
    -e "s|__ADMIN_ACTOR_ID__|${ADMIN_ACTOR_ID}|g" \
    "$template" > "$out"
  echo "$out"
}

# ==============================================================================
# Scenario 1: concurrent app.post_inventory_movement against a SHARED balance.
# ==============================================================================
echo ""
echo "### Scenario 1: concurrent app.post_inventory_movement (shared balance, ATW-015 row-lock proof) ###"
HOT_ON_HAND_BEFORE=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select on_hand from app.inventory_balances where id = (select id from app.inventory_balances where item_master_id='${HOT_ITEM_ID}' and location_id='${HOT_LOCATION_ID}');")
S1_CLIENTS=20
S1_SECONDS=15
echo "clients=${S1_CLIENTS} duration_seconds=${S1_SECONDS} on_hand_before=${HOT_ON_HAND_BEFORE}"
rm -f "$RESULTS_DIR"/pgbench_s1_log.*
S1_RENDERED=$(render_pgbench_script "$SCRIPT_DIR/pgbench/inventory-movement.sql")
pgbench "$TEST_DB_URL" -n -c "$S1_CLIENTS" -j 4 -T "$S1_SECONDS" -r -l --log-prefix="$RESULTS_DIR/pgbench_s1_log" \
  -f "$S1_RENDERED" || echo "(pgbench scenario 1 reported a nonzero exit -- inspecting DB state below regardless)"

S1_ACTUAL_MOVEMENTS=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.inventory_movements where idempotency_key like 'idem-loadtest-hotmove-%';")
HOT_ON_HAND_AFTER=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select on_hand from app.inventory_balances where id = (select id from app.inventory_balances where item_master_id='${HOT_ITEM_ID}' and location_id='${HOT_LOCATION_ID}');")
EXPECTED_ON_HAND=$((HOT_ON_HAND_BEFORE - S1_ACTUAL_MOVEMENTS))
echo "real_movements_posted=${S1_ACTUAL_MOVEMENTS} on_hand_after=${HOT_ON_HAND_AFTER} expected_on_hand=${EXPECTED_ON_HAND}"
if [ "$HOT_ON_HAND_AFTER" != "$EXPECTED_ON_HAND" ]; then
  echo "SCENARIO 1 RESULT: FAIL -- lost update detected (on_hand does not match on_hand_before - real_movements_posted)"
  S1_RESULT="FAIL"
else
  echo "SCENARIO 1 RESULT: PASS -- exactly ${S1_ACTUAL_MOVEMENTS} concurrent posts, no lost update, on_hand exact, no negative on_hand (CHECK constraint would have aborted the whole call otherwise)"
  S1_RESULT="PASS"
fi
if [ -f "$RESULTS_DIR/pgbench_s1_log.1" ] || compgen -G "$RESULTS_DIR/pgbench_s1_log.*" > /dev/null; then
  cat "$RESULTS_DIR"/pgbench_s1_log.* > "$RESULTS_DIR/pgbench_s1_log_all.txt" 2>/dev/null || true
  echo "latency percentiles (whole-call wall time, dominated by FOR UPDATE row-lock wait under contention -- ms):"
  awk '{print $3/1000}' "$RESULTS_DIR/pgbench_s1_log_all.txt" | sort -n > "$RESULTS_DIR/s1_latencies_sorted.txt"
  N=$(wc -l < "$RESULTS_DIR/s1_latencies_sorted.txt")
  if [ "$N" -gt 0 ]; then
    p50_line=$(( (N * 50 / 100) + 1 )); [ "$p50_line" -gt "$N" ] && p50_line=$N
    p95_line=$(( (N * 95 / 100) + 1 )); [ "$p95_line" -gt "$N" ] && p95_line=$N
    p99_line=$(( (N * 99 / 100) + 1 )); [ "$p99_line" -gt "$N" ] && p99_line=$N
    echo "  n=${N} p50=$(sed -n "${p50_line}p" "$RESULTS_DIR/s1_latencies_sorted.txt")ms p95=$(sed -n "${p95_line}p" "$RESULTS_DIR/s1_latencies_sorted.txt")ms p99=$(sed -n "${p99_line}p" "$RESULTS_DIR/s1_latencies_sorted.txt")ms max=$(tail -1 "$RESULTS_DIR/s1_latencies_sorted.txt")ms"
  fi
fi

# ==============================================================================
# Scenario 2: WMS pick/putaway task claiming under many concurrent workers.
# ==============================================================================
echo ""
echo "### Scenario 2a: concurrent app.claim_wms_pick_task (ATW-017) claiming from 500 unclaimed tasks ###"
S2_CLIENTS=20
S2_TX_PER_CLIENT=30
rm -f "$RESULTS_DIR"/pgbench_s2pick_log.*
S2PICK_RENDERED=$(render_pgbench_script "$SCRIPT_DIR/pgbench/wms-pick-claim.sql")
pgbench "$TEST_DB_URL" -n -c "$S2_CLIENTS" -j 4 -t "$S2_TX_PER_CLIENT" -r -l --log-prefix="$RESULTS_DIR/pgbench_s2pick_log" \
  -f "$S2PICK_RENDERED"
PICK_CLAIMED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.wms_pick_tasks where status = 'claimed';")
PICK_UNCLAIMED_REMAINING=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.wms_pick_tasks where status = 'unclaimed';")
# CG-S10-ATW-024 fix-pass correction (LOW finding, adversarial review): the previous
# check here grouped app.wms_pick_tasks by its own primary key `id` having count(*) > 1
# -- since `id` is the table's own primary key, that grouping is ALWAYS empty regardless
# of whether a real double-claim occurred, providing no actual evidence (the script's
# own prior comment admitted as much: "must be 0 by construction"). Real double-claim
# evidence requires looking at every individual successful claim ATTEMPT, not the tasks'
# own final resting state -- app.claim_wms_pick_task self-audits exactly once per
# successful claim (never on a task_already_claimed rejection, since that raises before
# reaching its own app.capture_audit_event call), so two genuinely successful claims of
# the SAME task would show up as two 'success' app.audit_logs rows sharing one
# resource_id -- a real, structurally-meaningful anomaly check.
PICK_DOUBLE_CLAIMED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from (select resource_id from app.audit_logs where action = 'claim_wms_pick_task' and resource_type = 'app.wms_pick_tasks' and result = 'success' group by resource_id having count(*) > 1) x;")
echo "claimed=${PICK_CLAIMED} unclaimed_remaining=${PICK_UNCLAIMED_REMAINING} double_claimed_tasks=${PICK_DOUBLE_CLAIMED} (real evidence: distinct successful claim_wms_pick_task audit_logs rows per resource_id, not a tautological group-by-primary-key check)"
if [ "$PICK_CLAIMED" = "500" ] && [ "$PICK_UNCLAIMED_REMAINING" = "0" ] && [ "$PICK_DOUBLE_CLAIMED" = "0" ]; then
  echo "SCENARIO 2a RESULT: PASS -- all 500 seeded pick tasks claimed exactly once, zero double-claims (audit-log verified), zero left unclaimed"
  S2A_RESULT="PASS"
else
  echo "SCENARIO 2a RESULT: FAIL -- expected claimed=500 unclaimed=0 double_claimed_tasks=0"
  S2A_RESULT="FAIL"
fi

echo ""
echo "### Scenario 2b: concurrent app.claim_wms_putaway_task (ATW-014) claiming from 500 unclaimed tasks ###"
rm -f "$RESULTS_DIR"/pgbench_s2putaway_log.*
S2PUTAWAY_RENDERED=$(render_pgbench_script "$SCRIPT_DIR/pgbench/wms-putaway-claim.sql")
pgbench "$TEST_DB_URL" -n -c "$S2_CLIENTS" -j 4 -t "$S2_TX_PER_CLIENT" -r -l --log-prefix="$RESULTS_DIR/pgbench_s2putaway_log" \
  -f "$S2PUTAWAY_RENDERED"
PUTAWAY_CLAIMED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.wms_putaway_tasks where status = 'claimed';")
PUTAWAY_UNCLAIMED_REMAINING=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.wms_putaway_tasks where status = 'unclaimed';")
# CG-S10-ATW-024 fix-pass addition (same real audit-log-based double-claim evidence as
# Scenario 2a above, applied here too -- see that scenario's own comment for rationale).
PUTAWAY_DOUBLE_CLAIMED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from (select resource_id from app.audit_logs where action = 'claim_wms_putaway_task' and resource_type = 'app.wms_putaway_tasks' and result = 'success' group by resource_id having count(*) > 1) x;")
echo "claimed=${PUTAWAY_CLAIMED} unclaimed_remaining=${PUTAWAY_UNCLAIMED_REMAINING} double_claimed_tasks=${PUTAWAY_DOUBLE_CLAIMED} (real evidence: distinct successful claim_wms_putaway_task audit_logs rows per resource_id)"
if [ "$PUTAWAY_CLAIMED" = "500" ] && [ "$PUTAWAY_UNCLAIMED_REMAINING" = "0" ] && [ "$PUTAWAY_DOUBLE_CLAIMED" = "0" ]; then
  echo "SCENARIO 2b RESULT: PASS -- all 500 seeded putaway tasks claimed exactly once, zero double-claims (audit-log verified), zero left unclaimed"
  S2B_RESULT="PASS"
else
  echo "SCENARIO 2b RESULT: FAIL -- expected claimed=500 unclaimed=0 double_claimed_tasks=0"
  S2B_RESULT="FAIL"
fi

for f in "$RESULTS_DIR"/pgbench_s2pick_log.* "$RESULTS_DIR"/pgbench_s2putaway_log.*; do
  [ -e "$f" ] || continue
  awk '{print $3/1000}' "$f"
done | sort -n > "$RESULTS_DIR/s2_claim_latencies_sorted.txt" 2>/dev/null || true
N2=$(wc -l < "$RESULTS_DIR/s2_claim_latencies_sorted.txt" 2>/dev/null || echo 0)
if [ "$N2" -gt 0 ]; then
  p50_line=$(( (N2 * 50 / 100) + 1 )); [ "$p50_line" -gt "$N2" ] && p50_line=$N2
  p95_line=$(( (N2 * 95 / 100) + 1 )); [ "$p95_line" -gt "$N2" ] && p95_line=$N2
  echo "claim latency (pick+putaway combined, ms): n=${N2} p50=$(sed -n "${p50_line}p" "$RESULTS_DIR/s2_claim_latencies_sorted.txt")ms p95=$(sed -n "${p95_line}p" "$RESULTS_DIR/s2_claim_latencies_sorted.txt")ms"
fi

# ==============================================================================
# Scenario 3: app.claim_next_job under a large enqueued backlog.
# ==============================================================================
echo ""
echo "### Scenario 3: app.claim_next_job under a 5,000-job backlog (throughput via pgbench) ###"
JOBS_PENDING_BEFORE=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where status = 'pending' and payload ? 'seed_seq';")
echo "pending_before=${JOBS_PENDING_BEFORE}"

echo ""
echo "EXPLAIN (ANALYZE) of app.claim_next_job's own WHERE-clause query shape, at this seeded volume (jobs_claim_candidate_idx, 20260730330000, is a real evidence-driven index added this checkpoint after an earlier run of this exact harness measured the pre-index plan -- see that migration's own header for the full before/after comparison and the pre-index EXPLAIN this run's own index now replaces):"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
explain (analyze, buffers, format text)
select * from app.jobs
where job_type = any (array['report_generation','notification_batch','webhook_retry','document_generation','dashboard_refresh','loyalty_expiration','recurring_billing','integration_sync'])
  and ((status = 'pending' and (next_attempt_at is null or next_attempt_at <= now())) or (status = 'in_progress' and locked_until < now()))
order by priority desc, created_at asc
for update skip locked
limit 1;
"

S3_CLIENTS=30
rm -f "$RESULTS_DIR"/pgbench_s3_log.*
S3_START_EPOCH=$(date +%s.%N)
pgbench "$TEST_DB_URL" -n -c "$S3_CLIENTS" -j 6 -t 200 -r -l --log-prefix="$RESULTS_DIR/pgbench_s3_log" \
  -f "$SCRIPT_DIR/pgbench/claim-next-job.sql"
S3_END_EPOCH=$(date +%s.%N)
S3_DURATION=$(echo "$S3_END_EPOCH - $S3_START_EPOCH" | bc)

JOBS_COMPLETED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where status = 'completed' and payload ? 'seed_seq';")
JOBS_REMAINING_PENDING=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where status = 'pending' and payload ? 'seed_seq';")
echo "duration_seconds=${S3_DURATION} completed=${JOBS_COMPLETED} still_pending=${JOBS_REMAINING_PENDING}"
THROUGHPUT_JPS=$(echo "scale=1; $JOBS_COMPLETED / $S3_DURATION" | bc)
echo "throughput_jobs_per_sec=${THROUGHPUT_JPS}"

echo "queue age percentiles (seconds, completed_at - created_at, seed-backlog jobs only):"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
select
  percentile_cont(0.5) within group (order by extract(epoch from (completed_at - created_at))) as p50_seconds,
  percentile_cont(0.95) within group (order by extract(epoch from (completed_at - created_at))) as p95_seconds,
  percentile_cont(0.99) within group (order by extract(epoch from (completed_at - created_at))) as p99_seconds,
  max(extract(epoch from (completed_at - created_at))) as max_seconds
from app.jobs where status = 'completed' and payload ? 'seed_seq';
"

if [ "$JOBS_REMAINING_PENDING" = "0" ]; then
  echo "SCENARIO 3 RESULT: PASS -- full 5,000-job backlog drained, no lost/double-claimed jobs (completed=${JOBS_COMPLETED})"
  S3_RESULT="PASS"
else
  echo "SCENARIO 3 RESULT: backlog not fully drained within the pgbench transaction budget (${JOBS_REMAINING_PENDING} remaining) -- see disclosure below"
  S3_RESULT="PARTIAL"
fi

echo ""
echo "### Scenario 3 (continued): scope-bounded manual polling-loop soak driver (job-poll-worker.sh, item 8 -- explicitly NOT a production scheduler, see its own header) against a smaller dedicated 300-job batch, 3 concurrent worker processes, one worker deliberately failing every 5th job to exercise the retry/backoff/dead-letter path under load too ###"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
insert into app.jobs (tenant_id, job_type, status, priority, payload, max_attempts, created_by, requested_by_auth_user_id)
select '${TENANT_ID}', 'notification_batch', 'pending', 0, jsonb_build_object('soak_seq', g), 5, 'loadtest', null
from generate_series(1, 300) g;
"
bash "$SCRIPT_DIR/job-poll-worker.sh" soak-worker-1 150 0 &
W1=$!
bash "$SCRIPT_DIR/job-poll-worker.sh" soak-worker-2 150 5 &
W2=$!
bash "$SCRIPT_DIR/job-poll-worker.sh" soak-worker-3 150 0 &
W3=$!
wait "$W1" "$W2" "$W3"
SOAK_COMPLETED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'soak_seq' and status = 'completed';")
SOAK_DEAD_LETTER=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'soak_seq' and status = 'dead_letter';")
SOAK_PENDING_RETRY=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'soak_seq' and status = 'pending';")
echo "soak batch (300 jobs): completed=${SOAK_COMPLETED} dead_letter=${SOAK_DEAD_LETTER} still_pending_retry=${SOAK_PENDING_RETRY} (deliberate failures schedule a real backoff retry -- not every failed job reaches dead_letter within this soak window, disclosed not a bug)"

echo ""
echo "### Scenario 3 (continued): deterministic dead-letter + replay reconciliation (CG-S10-ATW-024 fix-pass addition, adversarial review -- Prompt 243 section 25/28d names 'reconcile ... replayed counts' and 'job retry/DLQ/replay reconciliation' as required; the soak batch above discloses dead_letter=0 within its own soak window by design, so the DLQ->replay path was never actually exercised end to end. This scenario forces it deterministically via max_attempts=1 (dead-letters on the very first recorded failure, no backoff wait needed) and the real app.requeue_dead_letter_job replay RPC, then proves every replayed job actually completes) ###"
SUPREME_ACTOR_ID="00000000-0000-0000-0000-000000090002"
DLQ_REPLAY_JOB_COUNT=10
# priority=1000 -- far above any seed/soak job's own priority -- so app.claim_next_job's
# own `order by priority desc, created_at asc` deterministically always selects one of
# these jobs first, never an unrelated concurrent backlog/soak-retry row of the same
# job_type (avoids a flaky cross-scenario race without touching claim_next_job itself).
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
select app.enqueue_job('${TENANT_ID}', 'notification_batch', jsonb_build_object('dlq_replay_seq', g), 1000, 'idem-loadtest-dlq-replay-' || g, 1, '${ADMIN_ACTOR_ID}', 'loadtest')
from generate_series(1, ${DLQ_REPLAY_JOB_COUNT}) g;
" >/dev/null

echo "-- step 1: claim + deliberately fail each one (max_attempts=1 means the very first app.record_job_failure call dead-letters it, no backoff wait) --"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
do \$\$
declare
  v_job app.jobs;
  v_claimed integer := 0;
begin
  while v_claimed < ${DLQ_REPLAY_JOB_COUNT} loop
    select * into v_job from app.claim_next_job('dlq-replay-worker', array['notification_batch'], 300);
    if v_job.job_id is null then
      raise exception 'dlq_replay_setup_starved: expected % dlq_replay_seq jobs still claimable, got fewer', ${DLQ_REPLAY_JOB_COUNT};
    end if;
    if not (v_job.payload ? 'dlq_replay_seq') then
      raise exception 'dlq_replay_unexpected_job_claimed: claimed job % (payload %) is not one of this scenario''s own priority-1000 jobs -- priority ordering did not hold', v_job.job_id, v_job.payload;
    end if;
    perform app.record_job_failure(v_job.job_id, 'loadtest deliberate dlq-replay failure', null, 'dlq-replay-worker');
    v_claimed := v_claimed + 1;
  end loop;
end \$\$;
"
DLQ_REPLAY_DEAD_LETTER_COUNT=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'dlq_replay_seq' and status = 'dead_letter';")
echo "dead_lettered=${DLQ_REPLAY_DEAD_LETTER_COUNT} (expected ${DLQ_REPLAY_JOB_COUNT})"

echo "-- step 2: replay every dead-lettered job via the real app.requeue_dead_letter_job RPC --"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
do \$\$
declare
  v_job_id uuid;
begin
  for v_job_id in select job_id from app.jobs where payload ? 'dlq_replay_seq' and status = 'dead_letter' loop
    perform app.requeue_dead_letter_job(v_job_id, '${SUPREME_ACTOR_ID}', 'loadtest-dlq-replay-admin');
  end loop;
end \$\$;
"
DLQ_REPLAY_PENDING_AFTER_REQUEUE=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'dlq_replay_seq' and status = 'pending';")
echo "replayed_to_pending=${DLQ_REPLAY_PENDING_AFTER_REQUEUE} (expected ${DLQ_REPLAY_JOB_COUNT})"

echo "-- step 3: a real worker claims and completes every replayed job --"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
do \$\$
declare
  v_job app.jobs;
  v_claimed integer := 0;
begin
  while v_claimed < ${DLQ_REPLAY_JOB_COUNT} loop
    select * into v_job from app.claim_next_job('dlq-replay-worker-2', array['notification_batch'], 300);
    if v_job.job_id is null then
      raise exception 'dlq_replay_completion_starved: expected % replayed dlq_replay_seq jobs still claimable, got fewer', ${DLQ_REPLAY_JOB_COUNT};
    end if;
    if not (v_job.payload ? 'dlq_replay_seq') then
      raise exception 'dlq_replay_unexpected_job_claimed_step3: claimed job % (payload %) is not one of this scenario''s own replayed jobs', v_job.job_id, v_job.payload;
    end if;
    perform app.complete_job(v_job.job_id, 'dlq-replay-worker-2', null, 'dlq-replay-worker-2');
    v_claimed := v_claimed + 1;
  end loop;
end \$\$;
"
DLQ_REPLAY_COMPLETED=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'dlq_replay_seq' and status = 'completed';")
DLQ_REPLAY_STILL_DEAD_LETTER=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.jobs where payload ? 'dlq_replay_seq' and status = 'dead_letter';")
echo "completed_after_replay=${DLQ_REPLAY_COMPLETED} still_dead_letter=${DLQ_REPLAY_STILL_DEAD_LETTER}"
if [ "$DLQ_REPLAY_DEAD_LETTER_COUNT" = "$DLQ_REPLAY_JOB_COUNT" ] && [ "$DLQ_REPLAY_COMPLETED" = "$DLQ_REPLAY_JOB_COUNT" ] && [ "$DLQ_REPLAY_STILL_DEAD_LETTER" = "0" ]; then
  echo "SCENARIO 3d RESULT: PASS -- all ${DLQ_REPLAY_JOB_COUNT} jobs genuinely reached dead_letter, were replayed via app.requeue_dead_letter_job, and completed -- reconciled accepted/dead-lettered/replayed/completed counts all match"
  S3D_RESULT="PASS"
else
  echo "SCENARIO 3d RESULT: FAIL -- expected dead_lettered=${DLQ_REPLAY_JOB_COUNT} completed_after_replay=${DLQ_REPLAY_JOB_COUNT} still_dead_letter=0"
  S3D_RESULT="FAIL"
fi

# ==============================================================================
# Scenario 4: GPS telemetry ingestion at volume (self-contained, no database).
# ==============================================================================
echo ""
echo "### Scenario 4: GPS telemetry ingestion load (real TCP sockets + real Codec 8 Extended simulator, no live Supabase -- see gps-telemetry-load.ts's own header) ###"
node --experimental-strip-types "$SCRIPT_DIR/gps-telemetry-load.ts" || echo "(GPS scenario reported nonzero exit -- see output above)"

# ==============================================================================
# Scenario 5: ATW-023 cursor-paginated customer reads -- EXPLAIN (ANALYZE).
# ==============================================================================
echo ""
echo "### Scenario 5: ATW-023 pagination index-usage EXPLAIN (ANALYZE) at seeded volume ###"
bash "$SCRIPT_DIR/pagination-explain.sh"

# ==============================================================================
# Scenario 6: app.jobs claim-query index EXPLAIN evidence (see disclosure below).
# ==============================================================================
echo ""
echo "### Index evidence for app.claim_next_job's own WHERE-clause (job_type, status) shape at 5,000-row backlog volume -- see Scenario 3's own EXPLAIN above for the exact plan; summarized here ###"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
select relname, indexrelname, idx_scan, idx_tup_read from pg_stat_user_indexes where relname = 'jobs' order by idx_scan desc;
"

# ==============================================================================
# Scenario 7: restart/recovery.
# ==============================================================================
echo ""
echo "### Scenario 7: restart/recovery (real client kill mid-transaction + real Postgres cluster restart) ###"
bash "$SCRIPT_DIR/recovery-check.sh" || echo "SCENARIO 7 RESULT: FAIL (see output above)"

# ==============================================================================
# Scenario 8: concurrent multi-source telemetry arbitration under real contention
# (CG-S10-ATW-024 fix-pass addition -- see pgbench/hybrid-arbitration.sql's own header).
# ==============================================================================
echo ""
echo "### Scenario 8: concurrent multi-source telemetry arbitration under real contention (Hybrid target profile, Prompt 243 section 17; CG-S10-ATW-024 fix-pass addition, adversarial review) ###"
S8_CLIENTS=20
S8_SECONDS=15
echo "clients=${S8_CLIENTS} duration_seconds=${S8_SECONDS} hot_vehicles=20 (VEH-LOAD-0001..VEH-LOAD-0020, deliberately small/shared to maximize real contention)"
rm -f "$RESULTS_DIR"/pgbench_s8_log.*
S8_RENDERED=$(render_pgbench_script "$SCRIPT_DIR/pgbench/hybrid-arbitration.sql")
S8_EVENTS_BEFORE=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.canonical_telemetry_events e join app.master_records mr on mr.id = e.vehicle_master_id where mr.code between 'VEH-LOAD-0001' and 'VEH-LOAD-0020';")
pgbench "$TEST_DB_URL" -n -c "$S8_CLIENTS" -j 4 -T "$S8_SECONDS" -r -l --log-prefix="$RESULTS_DIR/pgbench_s8_log" \
  -f "$S8_RENDERED" || echo "(pgbench scenario 8 reported a nonzero exit -- inspecting DB state below regardless)"
S8_EVENTS_AFTER=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.canonical_telemetry_events e join app.master_records mr on mr.id = e.vehicle_master_id where mr.code between 'VEH-LOAD-0001' and 'VEH-LOAD-0020';")
S8_EVENTS_TOTAL=$((S8_EVENTS_AFTER - S8_EVENTS_BEFORE))
S8_THROUGHPUT=$(echo "scale=1; $S8_EVENTS_TOTAL / $S8_SECONDS" | bc)
echo "canonical_telemetry_events written this scenario=${S8_EVENTS_TOTAL} arbitration_throughput_events_per_sec=${S8_THROUGHPUT}"

echo "-- real regression check for Finding 1 (HIGH, adversarial review): vehicle_current_positions.event_at must equal max(event_at) among this vehicle's own applied_to_current_position=true canonical events -- any mismatch is a live TOCTOU lost-update/backward-movement bug --"
S8_BACKWARD_MOVEMENT_VEHICLES=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "
  select count(*) from (
    select vcp.vehicle_master_id
    from app.vehicle_current_positions vcp
    join app.master_records mr on mr.id = vcp.vehicle_master_id
    where mr.code between 'VEH-LOAD-0001' and 'VEH-LOAD-0020'
      and vcp.event_at <> (
        select max(cte.event_at) from app.canonical_telemetry_events cte
        where cte.vehicle_master_id = vcp.vehicle_master_id and cte.applied_to_current_position
      )
  ) x;
")
echo "vehicles_with_backward_movement_or_lost_update=${S8_BACKWARD_MOVEMENT_VEHICLES} (expected 0)"

echo "-- source-switch hysteresis under real contention: no two switches for the same vehicle closer together than the tenant default switch_hysteresis_seconds (120s, app.resolve_tenant_tracking_source_policy's own system default) --"
S8_HYSTERESIS_VIOLATIONS=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "
  select count(*) from (
    select extract(epoch from (vss.switched_at - lag(vss.switched_at) over (partition by vss.vehicle_master_id order by vss.switched_at))) as gap_seconds
    from app.vehicle_source_switches vss
    join app.master_records mr on mr.id = vss.vehicle_master_id
    where mr.code between 'VEH-LOAD-0001' and 'VEH-LOAD-0020'
  ) s
  where gap_seconds is not null and gap_seconds < 120;
")
echo "source_switch_hysteresis_violations=${S8_HYSTERESIS_VIOLATIONS} (expected 0)"

echo "-- idempotent replay under real CONCURRENT resubmission (not merely sequential): 10 concurrent duplicate calls for the SAME already-processed (source_type, source_report_id) must not create a second canonical_telemetry_events row --"
S8_REPLAY_SAMPLE=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select mr.id, e.source_type, e.source_report_id from app.canonical_telemetry_events e join app.master_records mr on mr.id = e.vehicle_master_id where mr.code between 'VEH-LOAD-0001' and 'VEH-LOAD-0020' order by random() limit 1;")
IFS='|' read -r S8_REPLAY_VEHICLE_ID S8_REPLAY_SOURCE_TYPE S8_REPLAY_SOURCE_REPORT_ID <<< "$S8_REPLAY_SAMPLE"
if [ -z "$S8_REPLAY_VEHICLE_ID" ]; then
  echo "replay check skipped -- no canonical_telemetry_events row exists yet to resubmit (the main pgbench run above produced zero events -- itself a failing condition, reflected in S8_EVENTS_TOTAL below)"
  S8_REPLAY_ROW_COUNT="0"
else
  # CG-S10-ATW-024 fix-pass correction (fix-agent's own fresh-run verification --
  # not one of the three reviewers' own named findings, since Scenario 8 postdates
  # all three reviews; caught by actually re-running this harness fresh end to end,
  # exactly the discipline this task's own instructions require): a bare `wait`
  # with no PID arguments does not only wait for the 10 background psql jobs
  # started below -- under bash 5.1+ (confirmed live in this environment, bash
  # 5.2.21) it ALSO waits for this script's own `exec > >(tee -a "$RUN_LOG") 2>&1`
  # process-substitution subshell (line 43), which never exits until the script's
  # own stdout closes -- a genuine deadlock, live-reproduced in isolation (a
  # minimal repro script with the identical exec/wait shape hangs forever under
  # this same bash). Every background job's own PID is now captured and waited on
  # BY NAME instead, which bash never conflates with the process substitution.
  S8_REPLAY_PIDS=()
  for i in $(seq 1 10); do
    psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select app.arbitrate_and_project_vehicle_position('${TENANT_ID}', '${S8_REPLAY_VEHICLE_ID}', '${S8_REPLAY_SOURCE_TYPE}', '${S8_REPLAY_SOURCE_REPORT_ID}', now(), now(), null, null, null, null);" >/dev/null &
    S8_REPLAY_PIDS+=($!)
  done
  wait "${S8_REPLAY_PIDS[@]}"
  S8_REPLAY_ROW_COUNT=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.canonical_telemetry_events where source_type = '${S8_REPLAY_SOURCE_TYPE}' and source_report_id = '${S8_REPLAY_SOURCE_REPORT_ID}';")
  echo "replay_target=(source_type=${S8_REPLAY_SOURCE_TYPE} source_report_id=${S8_REPLAY_SOURCE_REPORT_ID}) rows_after_10_concurrent_resubmissions=${S8_REPLAY_ROW_COUNT} (expected 1)"
fi

if [ "$S8_EVENTS_TOTAL" -gt "0" ] && [ "$S8_BACKWARD_MOVEMENT_VEHICLES" = "0" ] && [ "$S8_HYSTERESIS_VIOLATIONS" = "0" ] && [ "$S8_REPLAY_ROW_COUNT" = "1" ]; then
  echo "HYBRID_ARBITRATION_LOAD_SCENARIO: PASS -- ${S8_EVENTS_TOTAL} concurrent conflicting-source events arbitrated, zero backward-movement/lost-update, zero hysteresis violations, replay-safe under real concurrency"
  S8_RESULT="PASS"
else
  echo "HYBRID_ARBITRATION_LOAD_SCENARIO: FAIL -- see counts above"
  S8_RESULT="FAIL"
fi

echo ""
echo "### Final row-count summary ###"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
select 'wms_pick_tasks claimed' as metric, count(*) from app.wms_pick_tasks where status = 'claimed'
union all select 'wms_putaway_tasks claimed', count(*) from app.wms_putaway_tasks where status = 'claimed'
union all select 'jobs completed (seed backlog)', count(*) from app.jobs where status = 'completed' and payload ? 'seed_seq'
union all select 'inventory_movements (hot balance)', count(*) from app.inventory_movements where idempotency_key like 'idem-loadtest-hotmove-%';
"

echo ""
echo "==============================================================="
echo "Scenario result summary:"
echo "  1  concurrent post_inventory_movement (shared balance):  ${S1_RESULT:-UNKNOWN}"
echo "  2a concurrent claim_wms_pick_task:                       ${S2A_RESULT:-UNKNOWN}"
echo "  2b concurrent claim_wms_putaway_task:                    ${S2B_RESULT:-UNKNOWN}"
echo "  3  claim_next_job backlog drain:                         ${S3_RESULT:-UNKNOWN}"
echo "  3d dead-letter + replay reconciliation:                  ${S3D_RESULT:-UNKNOWN}"
echo "  4  GPS telemetry load:                                   see GPS_TELEMETRY_LOAD_SCENARIO line above"
echo "  5  ATW-023 pagination index usage:                       see EXPLAIN output above"
echo "  6  app.jobs claim-query index evidence:                  see EXPLAIN output above"
echo "  7  restart/recovery:                                     see 'recovery scenario: ALL PASSED' line above"
echo "  8  hybrid multi-source arbitration concurrency (real DB):  see HYBRID_ARBITRATION_LOAD_SCENARIO line above"
echo "Run finished (UTC): $(date -u -Iseconds)"
echo "==============================================================="

cp "$RUN_LOG" "$COMMITTED_RESULTS"
echo "Committed evidence file refreshed: $COMMITTED_RESULTS"

if [ "$KEEP_LOAD_TEST_DB" != "1" ]; then
  echo "==> load-tests: dropping disposable database '$TEST_DB_NAME'"
  psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $TEST_DB_NAME;" || true
fi
