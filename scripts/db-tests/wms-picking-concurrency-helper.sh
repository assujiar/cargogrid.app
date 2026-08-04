#!/usr/bin/env bash
# Real two-process concurrency proof helper for scripts/db-tests/advanced-tms-wms-picking.sql
# (CG-S10-ATW-017, Prompt 236). Not a *.sql file -- scripts/db-tests/run.sh only globs
# *.sql as test files, so this helper is never picked up as a test file on its own; it
# is invoked from within the .sql test via psql's own `\!` meta-command.
#
# Launches TWO real, independent psql client processes against the SAME disposable
# test database, each running exactly one RACE_SQL_A/RACE_SQL_B statement, started as
# close to simultaneously as two separate OS processes can be (backgrounded, then
# `wait`ed on) -- a genuine concurrent-session proof, not a sequential assertion in one
# session. The calling .sql script is responsible for asserting on the resulting
# database state afterward (never on this script's own stdout), so its own
# correctness does not depend on which process happened to "win" the race.
#
# Required environment (set via psql's own `\setenv` immediately before `\!` invokes
# this script -- see the calling .sql file for the exact pattern, and why `\!` itself
# does not interpolate psql variables the way ordinary SQL statements do):
#   PG_TEST_DB   -- the disposable test database name (captured via `select
#                   current_database() \gset` in the calling script; this repository's
#                   whole db-test suite always connects as postgres/postgres@127.0.0.1:
#                   5432, the same convention DATABASE_ADMIN_URL's own documented
#                   default and scripts/db-tests/run.sh already use)
#   RACE_SQL_A   -- the exact SQL statement process A runs
#   RACE_SQL_B   -- the exact SQL statement process B runs
#   RACE_OUT_A   -- output file path for process A's own stdout+stderr
#   RACE_OUT_B   -- output file path for process B's own stdout+stderr
set -euo pipefail

: "${PG_TEST_DB:?PG_TEST_DB must be set}"
: "${RACE_SQL_A:?RACE_SQL_A must be set}"
: "${RACE_SQL_B:?RACE_SQL_B must be set}"
: "${RACE_OUT_A:?RACE_OUT_A must be set}"
: "${RACE_OUT_B:?RACE_OUT_B must be set}"

PGURL="postgresql://postgres:postgres@127.0.0.1:5432/${PG_TEST_DB}"

psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$RACE_SQL_A" > "$RACE_OUT_A" 2>&1 &
PID_A=$!
psql "$PGURL" -v ON_ERROR_STOP=1 -Atqc "$RACE_SQL_B" > "$RACE_OUT_B" 2>&1 &
PID_B=$!

# Deliberately do not fail this script if one leg errors (a real, legitimate outcome
# of the race -- e.g. insufficient_remaining_quantity/task_already_claimed on the
# loser) -- the calling .sql script inspects both output files and the resulting
# database state itself.
wait "$PID_A" || true
wait "$PID_B" || true

echo "process A exit output:"
cat "$RACE_OUT_A"
echo "process B exit output:"
cat "$RACE_OUT_B"
