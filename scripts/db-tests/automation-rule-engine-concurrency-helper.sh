#!/usr/bin/env bash
# Real three-process concurrency proof helper for
# scripts/db-tests/automation-rule-engine.sql (Batch 2 Tier C fix pass,
# 20260803030000_harden_intelligence_batch2_tier_c_review_fixes.sql finding 4).
# Not a *.sql file -- scripts/db-tests/run.sh only globs *.sql as test files, so
# this helper is never picked up as a test file on its own; it is invoked from
# within the .sql test via psql's own `\!` meta-command, mirroring
# scripts/db-tests/wms-picking-concurrency-helper.sh's own established shape
# (extended from two racing processes to three, since proving the TOCTOU
# window this finding closed requires a third session to hold the target
# rule's own row lock long enough for BOTH racers to pass their unlocked
# idempotency pre-check before either blocks on it -- a live two-process race
# alone was not reliably reproducible; a live three-process race, matching the
# exact interleaving used to first reproduce and confirm this finding, was).
#
# Launches THREE real, independent psql client processes against the SAME
# disposable test database: process L acquires and holds a `for update` lock
# on the target automation_rules row (simulating "another actor is mid-lock"),
# started first and given a short head start; processes A and B each then
# attempt the SAME app.evaluate_event_for_automation_rules call (same tenant,
# rule, and source_event_id) while L still holds the lock, so both pass their
# own unlocked idempotency pre-check before either blocks waiting for L's
# lock to release -- the exact interleaving this finding's own fix (a second,
# post-lock idempotency re-check) closes. The calling .sql script is
# responsible for asserting on the resulting database state and on the L/A/B
# output files afterward (never on this script's own stdout).
#
# Required environment (set via psql's own `\setenv` immediately before `\!`
# invokes this script):
#   PG_TEST_DB   -- the disposable test database name
#   RACE_SQL_L   -- the lock-holding statement process L runs (expected to
#                   include its own pg_sleep so it holds the lock long enough
#                   for A and B to both start and pass their pre-check)
#   RACE_SQL_A   -- the exact SQL statement process A runs
#   RACE_SQL_B   -- the exact SQL statement process B runs
#   RACE_OUT_L   -- output file path for process L's own stdout+stderr
#   RACE_OUT_A   -- output file path for process A's own stdout+stderr
#   RACE_OUT_B   -- output file path for process B's own stdout+stderr
set -euo pipefail

: "${PG_TEST_DB:?PG_TEST_DB must be set}"
: "${RACE_SQL_L:?RACE_SQL_L must be set}"
: "${RACE_SQL_A:?RACE_SQL_A must be set}"
: "${RACE_SQL_B:?RACE_SQL_B must be set}"
: "${RACE_OUT_L:?RACE_OUT_L must be set}"
: "${RACE_OUT_A:?RACE_OUT_A must be set}"
: "${RACE_OUT_B:?RACE_OUT_B must be set}"

PGURL="postgresql://postgres:postgres@127.0.0.1:5432/${PG_TEST_DB}"

psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$RACE_SQL_L" > "$RACE_OUT_L" 2>&1 &
PID_L=$!

# Give L a real head start to acquire the row lock before A/B's own unlocked
# idempotency pre-check runs -- without this, A/B tend to race ahead of L and
# the TOCTOU window this test targets is not reliably hit (confirmed while
# first reproducing this finding: a bare two-process A/B race with no lock
# holder at all reproduced the bug only intermittently, not deterministically).
sleep 1

psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$RACE_SQL_A" > "$RACE_OUT_A" 2>&1 &
PID_A=$!
psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$RACE_SQL_B" > "$RACE_OUT_B" 2>&1 &
PID_B=$!

# Deliberately do not fail this script if any leg errors -- the calling .sql
# script inspects all three output files and the resulting database state
# itself (an ERROR in A or B's own output file is exactly the regression this
# test is designed to catch, not a harness failure).
wait "$PID_L" || true
wait "$PID_A" || true
wait "$PID_B" || true

echo "process L exit output:"
cat "$RACE_OUT_L"
echo "process A exit output:"
cat "$RACE_OUT_A"
echo "process B exit output:"
cat "$RACE_OUT_B"
