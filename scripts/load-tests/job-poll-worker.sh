#!/usr/bin/env bash
# CG-S10-ATW-024 (Prompt 243), Deliverable B item 8 -- a small, EXPLICITLY
# TEST-ONLY manual polling-loop script used only to drive scripts/load-tests/'s
# own scenario 3 (claim_next_job backlog) soak test.
#
# THIS IS NOT A PRODUCTION SCHEDULER. docs/runtime/KNOWN_ISSUES.md ISS-2026-015
# already discloses that no live scheduler/worker process exists anywhere in this
# repository, and that building one is its own separate, capability-sized,
# deliberately-deferred task. This script does not change that: it is a bounded,
# local, foreground bash loop that exits after a fixed duration or once the
# backlog is drained, with no daemonization, no retry/backoff policy beyond what
# app.record_job_failure already provides, no process supervision, no deployment
# story, and no claim of production-readiness. It exists solely so this
# checkpoint's own load-test harness has a second, independent (non-pgbench) way
# to exercise app.claim_next_job/app.complete_job/app.record_job_failure under a
# real backlog, and to demonstrate the claim/process/ack/fail cycle end to end at
# human-readable request granularity (pgbench's own scripts/load-tests/pgbench/
# claim-next-job.sql covers the higher-concurrency throughput measurement).
#
# Usage:
#   TEST_DB_URL=postgresql://postgres:postgres@127.0.0.1:5432/<db> \
#     bash scripts/load-tests/job-poll-worker.sh <worker_id> <max_iterations> [fail_every_n]
#
# fail_every_n (optional, default 0 = never): every Nth claimed job is
# deliberately failed via app.record_job_failure instead of completed, to
# exercise the retry/backoff/dead-letter path under load too, not only the
# happy path.
set -euo pipefail

: "${TEST_DB_URL:?TEST_DB_URL must be set (postgresql://... of the disposable load-test database)}"
WORKER_ID="${1:?worker_id required}"
MAX_ITERATIONS="${2:?max_iterations required}"
FAIL_EVERY_N="${3:-0}"

JOB_TYPES="array['report_generation','notification_batch','webhook_retry','document_generation','dashboard_refresh','loyalty_expiration','recurring_billing','integration_sync']"

claimed=0
completed=0
failed=0
empty_polls=0

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  job_id=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc \
    "select job_id from app.claim_next_job('${WORKER_ID}', ${JOB_TYPES}, 300);")

  if [ -z "$job_id" ]; then
    empty_polls=$((empty_polls + 1))
    continue
  fi

  claimed=$((claimed + 1))

  if [ "$FAIL_EVERY_N" -gt 0 ] && [ $((claimed % FAIL_EVERY_N)) -eq 0 ]; then
    psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc \
      "select app.record_job_failure('${job_id}', 'loadtest synthetic failure', null, '${WORKER_ID}');" >/dev/null
    failed=$((failed + 1))
  else
    psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc \
      "select app.complete_job('${job_id}', '${WORKER_ID}', null, '${WORKER_ID}');" >/dev/null
    completed=$((completed + 1))
  fi
done

echo "worker=${WORKER_ID} claimed=${claimed} completed=${completed} failed=${failed} empty_polls=${empty_polls}"
