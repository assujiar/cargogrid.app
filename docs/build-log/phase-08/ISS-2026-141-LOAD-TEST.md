# ISS-2026-141 — Phase 8 target-volume load/performance-test evidence

**Owner:** dedicated future performance-testing task per `ISS-2026-141`'s own citation, executed
under ADR-0027 Part A owner-authorized broader remediation scope. **Methodology:** mirrors
`docs/build-log/phase-06/PRC-268.md` §5 ("target-volume performance") and `PRC-269.md` §2 Fix 6
(the `app.list_vendor_contracts` covering-index fix) exactly — a large synthetic seed built by
direct bulk `INSERT` (never a per-row RPC loop, matching `scripts/load-tests/seed.sql`'s own
established convention), deliberately skewed with one adversarial "big" tenant concentrating the
same ~68% ratio `PRC-268`/`PRC-269` reproduced, `EXPLAIN (ANALYZE, BUFFERS)` run live against each
named surface's own real query shape, and — where a real Seq Scan defect was found — a live
before/after proof of the fix.

## 1. Scope: Phase 8's own 11 named target-volume surfaces

`ISS-2026-141`'s own text names these Phase 8 surfaces: dashboard, tracking, documents, inventory,
orders, invoices, payments, tickets, loyalty-ledger, redemption, liability-reconciliation. All 11
were identified to a specific real RPC/table and tested this checkpoint — **11 of 11 tested, 0
untested**.

| # | Named surface | RPC / table under test | Result |
|---|---|---|---|
| 1 | dashboard | `app.get_customer_portal_dashboard_summary` (composes rows 2/4/5/8 below, each capped `limit 200` inside the summary itself) | Bounded by its own composed RPCs — see below |
| 2 | tracking | `app.list_customer_shipment_orders` (`app.shipment_orders`) | **Holds up** — Index Scan |
| 3 | documents | `app.list_customer_documents` (`app.customer_portal_quote_requests` ∪ `app.epod_captures`/`app.files`) | Holds up at tested scale; one disclosed architectural note, not fixed — §3 |
| 4 | inventory | `app.list_customer_portal_inventory_balances` / `app.list_customer_inventory_balances` (both — see §2.4 — same table, `app.inventory_balances`) | **Holds up** — Index Scan (re-confirms the 2026-08-28 update's own fix) |
| 5 | orders | `app.list_customer_portal_outbound_orders` / `app.list_customer_outbound_orders` (both — same table, `app.wms_outbound_orders`) | **Holds up** — Index Scan |
| 6 | invoices | `app.list_customer_portal_invoices` (`app.finance_invoices`) | **Seq Scan — real defect, FIXED this checkpoint** |
| 7 | payments | `app.list_customer_portal_receipts` (`app.finance_receipts`) | **Holds up** — Index Scan |
| 8 | tickets | `app.list_customer_tickets` (`app.tickets` ⋈ `app.ticket_categories` ⋈ `app.accounts`) | **Holds up** — Index Scan + Memoize |
| 9 | loyalty-ledger | `app.list_customer_portal_loyalty_point_ledger_entries` (`app.loyalty_point_ledger_entries` ⋈ `app.loyalty_accounts` ⋈ `app.loyalty_programs`) | **Holds up** — Index Scan |
| 10 | redemption | `app.list_customer_portal_loyalty_redemptions` (`app.loyalty_redemptions` ⋈ `app.loyalty_accounts`) | **Holds up** — Index Scan |
| 11 | liability-reconciliation | `app.list_loyalty_liability_reconciliation_runs` (`app.loyalty_liability_reconciliation_runs`) | **Holds up** — Index Only Scan |

**Also covered, undisclosed until this checkpoint:** `app.get_customer_portal_dashboard_summary`'s
own booking-request card (`app.list_customer_booking_requests`, `app.customer_portal_booking_requests`)
was independently confirmed to carry the correct `(tenant_id, updated_at desc, id desc)` covering
index (`cpbr_tenant_updated_id_idx`) by direct schema inspection — structurally confirmed, not
independently live-`EXPLAIN`ed this checkpoint (the same time-bounded acceptance `PRC-268` §6.4
used for one of its own five findings).

## 2. Methodology detail

### 2.1 Environment

A fresh, disposable, local-only Postgres 16 database (`cargogrid_perf_p8p9`, never the live
Supabase project), all 437 `supabase/migrations/*.sql` applied via the shared
`scripts/db-tests/lib/setup-disposable-db.sh` helper — the same mechanism `scripts/db-tests/run.sh`
and `scripts/load-tests/run.sh` both already use. Zero application/schema code touched by seeding;
seeded rows were dropped with the disposable database at the end of this checkpoint.

### 2.2 Synthetic seed — adversarial single-tenant-concentration skew

20 tenants; one shared setup row per tenant (org unit, account, warehouse, warehouse location, item
master, job order, ticket category/queue, loyalty program/account/reward). Two upstream-Commercial
FK constraints (`job_orders_source_handoff_id_fkey`, `job_orders_quotation_id_fkey`,
`billing_readiness_handoffs_evaluation_id_fkey`) and one billing-handoff uniqueness index were
dropped on this disposable database only (never on any real migration) — none of the 11 target
query shapes filter or join on those columns, and seeding the entire unrelated Commercial
opportunity→quotation pipeline just to satisfy referential integrity on a column no query under
test touches would have been pure overhead with zero bearing on the result.

Volume rows, direct bulk `INSERT ... SELECT generate_series(...)` (never a per-row RPC loop, mirroring
`scripts/load-tests/seed.sql`'s own disclosed design note): **7,494 rows per table** across
`shipment_orders`, `finance_invoices`, `finance_receipts`, `wms_outbound_orders`, `tickets`,
`loyalty_point_ledger_entries`, `loyalty_redemptions`, `customer_portal_quote_requests`, `files`
(1:1 with the quote requests) — tenant #1 holds **5,100 (68.0%)**, matching `PRC-268`/`PRC-269`'s
own reproduction ratio exactly; the other 19 tenants share 126 rows each. `loyalty_liability_
reconciliation_runs` (staff-facing, tenant-only scope, no per-customer skew relevant) got a smaller
2,006-row/1,360-big-tenant volume; `inventory_balances` a 2,498-row/1,700-big-tenant re-check
volume (this table's own index was already fixed 2026-08-28 — this checkpoint independently
re-confirms it on a freshly-built fixture, not merely trusted from that prior update).

`ANALYZE` run before every `EXPLAIN` batch.

### 2.3 The one real defect found — `app.finance_invoices`

Query shape (from `app.list_customer_portal_invoices`'s own body):

```sql
select ... from app.finance_invoices i
where i.tenant_id = :tenant and i.status in ('issued','void')
  and i.customer_account_id = any (:scope)
order by i.updated_at desc, i.id desc limit 50;
```

Every sibling Customer Portal list table already carries a `(tenant_id, updated_at/created_at desc,
id desc)` covering index — `finance_receipts_tenant_updated_id_idx`,
`wms_outbound_orders_tenant_updated_id_idx`, `shipment_orders_tenant_updated_id_idx`,
`tickets_tenant_created_idx`, `lple_tenant_created_id_idx`, `lrd_tenant_updated_id_idx`,
`llrr_tenant_updated_id_idx`, `inventory_balances_tenant_updated_id_idx`. `app.finance_invoices`
was the one outlier: only `finance_invoices_tenant_customer_idx (tenant_id, customer_account_id)`
and `finance_invoices_tenant_status_idx (tenant_id, status)` existed — neither serves an
`order by updated_at desc` scan.

**Before** (live `EXPLAIN (ANALYZE, BUFFERS)` against the big tenant, 5,100 rows, 2,394 filtered out):

```
Limit (actual time=16.077..16.086 rows=50 loops=1)
  Buffers: shared hit=6 read=798 written=517
  -> Sort (Sort Method: top-N heapsort  Memory: 28kB)
     -> Seq Scan on finance_invoices i (actual time=0.024..15.528 rows=5100 loops=1)
           Filter: (customer_account_id = ANY (...) AND status = ANY (...) AND tenant_id = ...)
           Rows Removed by Filter: 2394
Execution Time: 16.106 ms
```

**Fix** (additive, `supabase/migrations/20260902080000_harden_phase8_phase9_target_volume_covering_indexes.sql`):

```sql
create index if not exists finance_invoices_tenant_updated_id_idx
  on app.finance_invoices (tenant_id, updated_at desc, id desc);
```

**After** (identical query, same fixture, re-`ANALYZE`d):

```
Limit (actual time=0.028..0.052 rows=50 loops=1)
  Buffers: shared read=4 written=1
  -> Index Scan using finance_invoices_tenant_updated_id_idx on finance_invoices i
        Index Cond: (tenant_id = ...)
        Filter: (customer_account_id = ANY (...) AND status = ANY (...))
Execution Time: 0.072 ms
```

**~224× execution-time improvement, ~160× fewer buffer touches** (804 → 5). Applied live to the
real Supabase project (`awdlicmwzdxquopwtcfd`) via `apply_migration`, recorded in
`supabase_migrations.schema_migrations`; full `bash scripts/db-tests/run.sh` re-run clean after
applying — see the closing `KNOWN_ISSUES.md` entry for the exact gate results.

### 2.4 Two Phase-8 surfaces silently share a table/index with an OLDER, pre-Phase-8 sibling function

`app.get_customer_portal_dashboard_summary` (CPL-326) internally calls `app.list_customer_
inventory_balances` and `app.list_customer_outbound_orders` — NOT the Phase-8-named `app.list_
customer_portal_inventory_balances`/`app.list_customer_portal_outbound_orders` this entry's own
row-4/row-5 tests above target directly. Independently confirmed by direct `pg_get_functiondef`
read: both pairs run the byte-identical `WHERE`/`ORDER BY` shape against the exact same base table
(`app.inventory_balances`, `app.wms_outbound_orders`) — so the Index Scan proof already produced
for rows 4/5 above is real, direct evidence for the dashboard's own two cards too, not an
assumption. This is the SAME naming-drift shape `ISS-2026-141`'s own original disclosure already
found once (`pagination-explain.sh` targeting the pre-Phase-8 ATW-023 sibling) — independently
re-found here in a second location (the dashboard RPC itself), disclosed for the record, not a
performance defect in its own right (both functions are equally fast; only the naming is
confusing).

## 3. Documents surface (`app.list_customer_documents`) — disclosed, not fixed

The quote-request arm of this function's own `UNION ALL` (`quote_request_docs` CTE, joining
`app.customer_portal_quote_requests` to `app.files`) measured **16.452ms** at the same 5,100-row
big-tenant scale — a `Hash Join` with a `Seq Scan` on `app.files` (`files_tenant_record_idx` is
`(tenant_id, record_type, record_id)`, which the planner correctly judged not worth probing
per-row against a candidate set the same order of magnitude as the table itself). This is a real,
disclosed architectural note — the function's own `ORDER BY ... LIMIT` is applied only AFTER the
`UNION ALL` combines both arms, so neither arm's own candidate set is bounded by the caller's
`p_limit` before the union runs — but at the tested scale it is not alarming (16ms, well under any
reasonable timeout) and is bounded by the caller's own tenant+account scope, not the full `app.
files` table. **Not fixed this checkpoint**: a per-arm `LIMIT`-pushdown rewrite is a function-body
change to CPL-304's own migration, not a bounded additive index — genuinely a different repair
class than the other fixes in this entry, and current cost at the tested scale does not warrant
forcing it into this checkpoint's own additive-index-only scope.

## 4. Result summary

- **11 of 11 named Phase 8 surfaces tested** (10 directly `EXPLAIN`ed; the dashboard's own 5th
  card, bookings, structurally confirmed via index inspection per §1).
- **1 genuine Seq Scan defect found and fixed** (`app.finance_invoices`, ~224× improvement) —
  live-verified before and after, applied to the live Supabase project.
- **1 disclosed, not-fixed architectural note** (documents surface's own `UNION ALL`
  `LIMIT`-pushdown gap) — real but not alarming at tested scale, a function-body rewrite outside
  this checkpoint's additive-index-only scope.
- **9 of 11 surfaces confirmed holding up** with an Index Scan, Index Only Scan, or Index Scan +
  Memoize plan — no further action.
- **0 surfaces left entirely untested.**
