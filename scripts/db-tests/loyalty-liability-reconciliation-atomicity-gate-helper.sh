#!/usr/bin/env bash
# Real three-process, lock-gated concurrency proof helper for
# scripts/db-tests/customer-loyalty-liability-reconciliation.sql (CPL-325,
# CG-S13-CPL-027, Prompt 325 -- regression for supabase/migrations/
# 20260801310000_harden_customer_portal_loyalty_liability_reconciliation_
# snapshot_atomicity.sql). Not a *.sql file -- scripts/db-tests/run.sh only
# globs *.sql as test files, so this helper is never picked up as a test
# file on its own; it is invoked from within the .sql test via psql's own
# `\!` meta-command, mirroring scripts/db-tests/wms-picking-concurrency-
# helper.sh's own established pattern, extended to a THIRD party (a "gate"
# session) since this specific defect requires deterministically pinning a
# concurrent commit to land strictly inside another transaction's own
# single-statement execution window -- a plain two-process race (the
# wms-picking helper's own shape) cannot reliably force that narrow an
# interleaving on ordinary hardware.
#
# Three genuinely independent psql client processes against the SAME
# disposable test database:
#   1. GATE_SQL    -- opens a transaction, takes a table-level ACCESS
#                      EXCLUSIVE lock, sleeps, then commits (releasing the
#                      lock). Started FIRST, given a short head start to
#                      actually acquire its lock before the other two begin.
#   2. MUTATOR_SQL -- a statement that does NOT touch the gate-locked table
#                      (so it is free to run and commit WHILE the gate is
#                      held) -- the concurrent write whose visibility this
#                      test is probing.
#   3. READER_SQL  -- a statement that DOES touch the gate-locked table (so
#                      it blocks until the gate releases) -- the function
#                      under test. Under correct single-statement-snapshot
#                      semantics, the snapshot READER_SQL uses is fixed at
#                      ITS OWN statement start (before it ever blocks on the
#                      gate), so it must see the SAME pre-mutation state
#                      across every table it reads, regardless of the
#                      mutator's commit landing while it was parked.
#
# The calling .sql script is responsible for asserting on the resulting
# database state afterward (never on this script's own stdout).
#
# Required environment (set via psql's own `\setenv` immediately before `\!`
# invokes this script -- see the calling .sql file for the exact pattern):
#   PG_TEST_DB   -- the disposable test database name
#   GATE_SQL     -- the exact multi-statement SQL string the gate session
#                   runs (its own explicit BEGIN/COMMIT, so it executes as
#                   one transaction across the whole -c call)
#   MUTATOR_SQL  -- the exact SQL statement the mutator process runs
#   READER_SQL   -- the exact SQL statement the reader process runs
#   GATE_OUT / MUTATOR_OUT / READER_OUT -- output file paths for each
#                   process's own stdout+stderr
set -euo pipefail

: "${PG_TEST_DB:?PG_TEST_DB must be set}"
: "${GATE_SQL:?GATE_SQL must be set}"
: "${MUTATOR_SQL:?MUTATOR_SQL must be set}"
: "${READER_SQL:?READER_SQL must be set}"
: "${GATE_OUT:?GATE_OUT must be set}"
: "${MUTATOR_OUT:?MUTATOR_OUT must be set}"
: "${READER_OUT:?READER_OUT must be set}"

PGURL="postgresql://postgres:postgres@127.0.0.1:5432/${PG_TEST_DB}"

psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$GATE_SQL" > "$GATE_OUT" 2>&1 &
PID_GATE=$!

# Give the gate session a real head start to acquire its own lock before the
# mutator/reader ever start -- both of the latter are launched as separate
# OS processes and need the lock to already be held for this test to prove
# anything (a race where the gate loses would silently degrade to a no-op
# proof, not a false failure -- but this head start makes that vanishingly
# unlikely on any real machine).
sleep 0.5

psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$MUTATOR_SQL" > "$MUTATOR_OUT" 2>&1 &
PID_MUTATOR=$!
psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$READER_SQL" > "$READER_OUT" 2>&1 &
PID_READER=$!

# Deliberately do not fail this script if any leg errors -- the calling
# .sql script inspects the output files and the resulting database state
# itself.
wait "$PID_GATE" || true
wait "$PID_MUTATOR" || true
wait "$PID_READER" || true

echo "gate process exit output:"
cat "$GATE_OUT"
echo "mutator process exit output:"
cat "$MUTATOR_OUT"
echo "reader process exit output:"
cat "$READER_OUT"
