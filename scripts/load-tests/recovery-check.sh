#!/usr/bin/env bash
# CG-S10-ATW-024 (Prompt 243) Scenario 7 -- restart/recovery. Mid-load,
# terminate a client connection abruptly AND restart the actual local Postgres
# cluster process, then verify: an already-committed idempotent operation
# remains exactly-once, an in-flight (never-committed) operation rolled back
# cleanly with no partial/corrupt state, and a retry with the same idempotency
# key after "recovery" returns the ORIGINAL result rather than double-applying.
#
# This is a real proof against this session's own real, dedicated local Postgres
# 16 cluster (not a shared multi-tenant server -- restarting it here is safe and
# does not affect any other workload). scripts/db-tests/run.sh's own disposable-
# database convention is unaffected by a cluster restart (the disposable database
# itself is durable, WAL-backed storage -- a clean `pg_ctlcluster restart` is not
# a data-loss event by itself, exactly the property being proven).
set -euo pipefail

: "${TEST_DB_URL:?TEST_DB_URL must be set}"
: "${TEST_DB_NAME:?TEST_DB_NAME must be set}"
: "${DATABASE_ADMIN_URL:?DATABASE_ADMIN_URL must be set}"

TENANT_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.tenants where slug = 'loadtest';")
WAREHOUSE_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.warehouses where tenant_id = '${TENANT_ID}';")
ACCOUNT_ALPHA_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.accounts where legal_name = 'Load Test Owner Alpha';")
HOT_ITEM_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.item_masters where code = 'SKU-HOT-CONTENTION';")
HOT_LOCATION_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.warehouse_locations where code = 'RACK-LOAD-00001' and warehouse_id = '${WAREHOUSE_ID}';")
# scripts/load-tests/seed.sql's own load_test_state table is a TEMPORARY table,
# scoped to the seeding session's own connection -- it no longer exists by the
# time this script runs in a fresh psql invocation. The admin actor id it seeded
# is a well-known fixture constant (see seed.sql's own header), used directly.
ADMIN_ID="00000000-0000-0000-0000-000000090001"

MOVE_SQL_TEMPLATE="select (app.post_inventory_movement('${TENANT_ID}', '${WAREHOUSE_ID}', 'adjustment', 'manual', null, '%s', 'recovery test', jsonb_build_array(jsonb_build_object('owner_account_id', '${ACCOUNT_ALPHA_ID}', 'item_master_id', '${HOT_ITEM_ID}', 'location_id', '${HOT_LOCATION_ID}', 'uom_code', 'PCS', 'signed_quantity', -1, 'status', 'on_hand')), '${ADMIN_ID}', 'loadtest-recovery')).id;"

COMMITTED_KEY="idem-loadtest-recovery-committed"
INFLIGHT_KEY="idem-loadtest-recovery-inflight-$$"

echo "== step 1: a real, fully-committed movement (baseline for the idempotent-retry proof) =="
COMMITTED_MOVEMENT_ID_BEFORE=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "$(printf "$MOVE_SQL_TEMPLATE" "$COMMITTED_KEY")")
echo "committed movement id: ${COMMITTED_MOVEMENT_ID_BEFORE}"

echo "== step 2: an in-flight (never-committed) transaction, killed mid-transaction (SIGKILL on the psql client process, genuinely idle-in-transaction server-side -- not a server-side pg_sleep, which would keep running regardless of client liveness) =="
FIFO_DIR=$(mktemp -d)
FIFO="$FIFO_DIR/inflight.fifo"
mkfifo "$FIFO"
# Launch the psql READER first, in the background -- opening a FIFO for writing
# (`exec 3>`) blocks until a reader has already opened it, so opening the write
# end before the reader exists would deadlock the whole script.
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atq < "$FIFO" &
INFLIGHT_PID=$!
# Keep the FIFO open for writing on fd 3 for the whole step -- otherwise the
# first write would hit EOF the instant psql finishes reading it.
exec 3>"$FIFO"
echo "begin;" >&3
echo "$(printf "$MOVE_SQL_TEMPLATE" "$INFLIGHT_KEY")" >&3
sleep 2
# The backend is now genuinely idle-in-transaction, waiting on this exact client
# connection for its next statement -- SIGKILL the client process outright.
kill -9 "$INFLIGHT_PID" 2>/dev/null || true
wait "$INFLIGHT_PID" 2>/dev/null || true
exec 3>&-
rm -rf "$FIFO_DIR"
sleep 1

INFLIGHT_ROW_COUNT=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.inventory_movements where idempotency_key = '${INFLIGHT_KEY}';")
if [ "$INFLIGHT_ROW_COUNT" != "0" ]; then
  echo "FAIL: expected the killed in-flight transaction to leave zero rows (clean rollback), found ${INFLIGHT_ROW_COUNT}"
  exit 1
fi
echo "PASS: killed in-flight transaction left zero committed rows (clean rollback) -- ${INFLIGHT_ROW_COUNT} rows for key ${INFLIGHT_KEY}"

echo "== step 3: restart the actual local Postgres cluster process (real server-level recovery, not merely a client reconnect) =="
BEFORE_RESTART_ON_HAND=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select on_hand from app.inventory_balances where item_master_id = '${HOT_ITEM_ID}' and location_id = '${HOT_LOCATION_ID}';")
pg_ctlcluster 16 main restart
for i in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
  echo "FAIL: Postgres did not come back up after restart within 30s"
  exit 1
fi
echo "PASS: Postgres cluster restarted and is accepting connections again"

echo "== step 4: post-restart durability -- the committed row from step 1 survived, the on_hand value is unchanged and consistent, the never-committed row from step 2 is still absent =="
AFTER_RESTART_ON_HAND=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select on_hand from app.inventory_balances where item_master_id = '${HOT_ITEM_ID}' and location_id = '${HOT_LOCATION_ID}';")
if [ "$BEFORE_RESTART_ON_HAND" != "$AFTER_RESTART_ON_HAND" ]; then
  echo "FAIL: on_hand changed across restart (before=${BEFORE_RESTART_ON_HAND}, after=${AFTER_RESTART_ON_HAND}) -- expected exact durability, no partial/corrupt state"
  exit 1
fi
echo "PASS: on_hand unchanged across restart (before=${BEFORE_RESTART_ON_HAND}, after=${AFTER_RESTART_ON_HAND})"

INFLIGHT_ROW_COUNT_AFTER=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.inventory_movements where idempotency_key = '${INFLIGHT_KEY}';")
if [ "$INFLIGHT_ROW_COUNT_AFTER" != "0" ]; then
  echo "FAIL: the never-committed in-flight row reappeared after restart (${INFLIGHT_ROW_COUNT_AFTER} rows) -- WAL should never resurrect an aborted transaction"
  exit 1
fi
echo "PASS: never-committed row still absent after restart (${INFLIGHT_ROW_COUNT_AFTER} rows)"

echo "== step 5: idempotency-key retry after 'recovery' returns the ORIGINAL committed result, never a double-apply =="
COMMITTED_MOVEMENT_ID_AFTER=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "$(printf "$MOVE_SQL_TEMPLATE" "$COMMITTED_KEY")")
if [ "$COMMITTED_MOVEMENT_ID_BEFORE" != "$COMMITTED_MOVEMENT_ID_AFTER" ]; then
  echo "FAIL: retrying the same idempotency_key after recovery returned a DIFFERENT movement id (before=${COMMITTED_MOVEMENT_ID_BEFORE}, after=${COMMITTED_MOVEMENT_ID_AFTER}) -- a double-apply"
  exit 1
fi
echo "PASS: retry with the same idempotency_key returned the identical original movement id (${COMMITTED_MOVEMENT_ID_AFTER}), no double-apply"

MOVEMENT_COUNT_FOR_KEY=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select count(*) from app.inventory_movements where idempotency_key = '${COMMITTED_KEY}';")
if [ "$MOVEMENT_COUNT_FOR_KEY" != "1" ]; then
  echo "FAIL: expected exactly 1 row in app.inventory_movements for the committed idempotency key across both calls, found ${MOVEMENT_COUNT_FOR_KEY}"
  exit 1
fi
echo "PASS: exactly 1 row in app.inventory_movements for the committed idempotency key across both calls (before restart + after restart) -- exactly-once confirmed"

echo "== recovery scenario: ALL PASSED =="
