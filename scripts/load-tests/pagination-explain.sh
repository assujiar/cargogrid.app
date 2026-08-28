#!/usr/bin/env bash
# CG-S10-ATW-024 (Prompt 243) Scenario 6 -- confirms ATW-023's own new
# cursor-paginated customer reads (app.list_customer_inventory_balances etc.,
# 20260730310000_create_advanced_tms_customer_inventory_access.sql) actually use
# the new pagination indexes (20260730312000_add_customer_inventory_access_
# pagination_indexes.sql) at the seeded volume -- direct evidence for or against
# ATW-023's own indexing decision, not a new capability.
#
# Design note (disclosed): app.list_customer_inventory_balances etc. are
# SECURITY DEFINER PL/pgSQL functions -- `EXPLAIN ANALYZE select app.list_...(...)`
# only shows the cost of the opaque function-call node, never the plan of the
# SELECT statement running INSIDE that function's own body. This script instead
# runs EXPLAIN (ANALYZE) directly against the exact, literal query shape copied
# from each RPC's own already-applied migration body (the same technique named in
# this task's own instructions: "run EXPLAIN (ANALYZE) against the actual query
# shape"), parameterized with a real seeded tenant/owner-scope/warehouse, so the
# real index chosen by the real planner against the real seeded row counts is
# what gets captured -- never a hand-waved claim.
set -euo pipefail

: "${TEST_DB_URL:?TEST_DB_URL must be set}"

TENANT_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.tenants where slug = 'loadtest';")
OWNER_ALPHA_ID=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "select id from app.accounts where legal_name = 'Load Test Owner Alpha';")
# ISS-2026-141 (Track B Batch 5): the customer_actor_id seed.sql already
# seeds (line 117-119, hardcoded uuid, never generated) for the ATW-023
# scenario above -- reused here unchanged, never a new fixture row. Its own
# warehouse eligibility (app.grant_warehouse_customer_eligibility,
# seed.sql:120) and legacy app.principal_memberships grant (seed.sql:119)
# both already satisfy app.resolve_customer_account_scope's own "legacy
# marker contributes an account only if the new CPL-300 grant table has no
# row for that triple" fallback
# (20260801010000_create_customer_portal_account_scope.sql:279-283) --
# independently re-verified this pass by direct read, not assumed. (Not
# resolved from load_test_state -- that table is `temporary`, seed.sql:56,
# so it is only visible within the same psql session that ran seed.sql, not
# this script's own later, separate psql invocations.)
CUSTOMER_ACTOR_ID="00000000-0000-0000-0000-000000090003"

echo "=== EXPLAIN (ANALYZE): app.list_customer_inventory_balances query shape (app.inventory_balances) ==="
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
explain (analyze, buffers, format text)
select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
  b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
from app.inventory_balances b
where b.tenant_id = '${TENANT_ID}'
  and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
  and b.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[])
order by b.updated_at desc, b.id desc
limit 50;
"

echo "=== EXPLAIN (ANALYZE): app.list_customer_lot_identities query shape (app.lot_identities) ==="
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
explain (analyze, buffers, format text)
select l.id, l.item_master_id, l.lot_number, l.status, l.expiry_date, l.updated_at
from app.lot_identities l
where l.tenant_id = '${TENANT_ID}'
  and l.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[])
order by l.updated_at desc, l.id desc
limit 50;
"

echo "=== EXPLAIN (ANALYZE): app.list_customer_serial_identities query shape (app.serial_identities) ==="
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
explain (analyze, buffers, format text)
select s.id, s.item_master_id, s.serial_number, s.status, s.updated_at
from app.serial_identities s
where s.tenant_id = '${TENANT_ID}'
  and s.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[])
order by s.updated_at desc, s.id desc
limit 50;
"

echo "=== EXPLAIN (ANALYZE): app.list_customer_outbound_orders query shape (app.wms_outbound_orders) ==="
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
explain (analyze, buffers, format text)
select o.id, o.outbound_number, o.status, o.updated_at
from app.wms_outbound_orders o
where o.tenant_id = '${TENANT_ID}'
  and o.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[])
order by o.updated_at desc, o.id desc
limit 50;
"

# ISS-2026-141 (Track B Batch 5): app.list_customer_portal_inventory_balances
# (CPL-309, 20260801100000_create_customer_portal_warehouse_inventory_
# visibility.sql:247-312) is Phase 8's own real, live customer-portal-facing
# pagination RPC -- confirmed by direct read that this entry's own diagnosis
# was accurate (this file, before this pass, exercised only app.list_
# customer_inventory_balances, the differently-named, Phase-5-dated ATW-023
# sibling this Phase 8 function was never actually the same as). The query
# shape is genuinely identical to app.list_customer_inventory_balances's own
# EXPLAIN block above, over the SAME already-seeded app.inventory_balances
# rows -- CPL-309's only structural addition is the per-row app.customer_
# warehouse_eligibility_active(...) filter (20260730310000:288-..., the one
# shared eligibility predicate every ATW-023/CPL-309 list/get RPC reuses,
# never re-derived) and a v_scope resolved via app.resolve_customer_account_
# scope (CPL-300's widened resolver) rather than a literal array -- both
# reproduced here exactly as the real function body computes them, so the
# real planner sees the real predicate shape, not a hand-simplified stand-in.
echo "=== EXPLAIN (ANALYZE): app.list_customer_portal_inventory_balances query shape (app.inventory_balances, CPL-309 -- Phase 8's real function, not the ATW-023 one above) ==="
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
explain (analyze, buffers, format text)
select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
  b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
from app.inventory_balances b
where b.tenant_id = '${TENANT_ID}'
  and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
  and b.owner_account_id = any(app.resolve_customer_account_scope('${CUSTOMER_ACTOR_ID}', '${TENANT_ID}'))
  and app.customer_warehouse_eligibility_active('${TENANT_ID}', b.warehouse_id, b.owner_account_id)
order by b.updated_at desc, b.id desc
limit 50;
"

echo "=== Index-usage summary (grep-friendly) ==="
for q in \
  "select b.id from app.inventory_balances b where b.tenant_id = '${TENANT_ID}' and b.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[]) order by b.updated_at desc, b.id desc limit 50" \
  "select l.id from app.lot_identities l where l.tenant_id = '${TENANT_ID}' and l.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[]) order by l.updated_at desc, l.id desc limit 50" \
  "select s.id from app.serial_identities s where s.tenant_id = '${TENANT_ID}' and s.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[]) order by s.updated_at desc, s.id desc limit 50" \
  "select o.id from app.wms_outbound_orders o where o.tenant_id = '${TENANT_ID}' and o.owner_account_id = any(array['${OWNER_ALPHA_ID}']::uuid[]) order by o.updated_at desc, o.id desc limit 50" \
  "select b.id from app.inventory_balances b where b.tenant_id = '${TENANT_ID}' and b.owner_account_id = any(app.resolve_customer_account_scope('${CUSTOMER_ACTOR_ID}', '${TENANT_ID}')) and app.customer_warehouse_eligibility_active('${TENANT_ID}', b.warehouse_id, b.owner_account_id) order by b.updated_at desc, b.id desc limit 50" \
  ; do
  plan=$(psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -Atqc "explain (format text) $q;" | head -3)
  echo "-- $q"
  echo "$plan"
  echo
done
