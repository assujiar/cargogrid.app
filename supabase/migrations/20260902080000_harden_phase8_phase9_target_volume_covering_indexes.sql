-- ISS-2026-141 / ISS-2026-148: real, live-measured Seq Scan defects found while
-- building the target-volume load/performance-test evidence those two entries
-- disclosed was missing. Every index below is purely additive (no existing
-- index touched, no application-code change required) and closes the identical
-- defect shape already fixed once this session at PRC-269 Fix 6
-- (app.vendor_contracts, ISS-2026-056): a `tenant_id`-scoped list query ordered
-- by a timestamp column, where every SIBLING table in the same capability
-- family already carries a `(tenant_id, <timestamp> desc[, id desc])` covering
-- index but this one table does not -- so under real-world single-tenant
-- volume the planner has no choice but a full Seq Scan + Sort/top-N heapsort.
--
-- Methodology and live before/after EXPLAIN (ANALYZE, BUFFERS) evidence for
-- all 5 fixes, run against a 20-tenant / ~7,500-row-per-table synthetic seed
-- with one tenant deliberately holding ~68% of every table (the same
-- adversarial single-tenant-concentration skew ratio PRC-268/269 established),
-- is recorded in docs/build-log/phase-08/ISS-2026-141-LOAD-TEST.md and
-- docs/build-log/phase-09/ISS-2026-148-LOAD-TEST.md.

-- 1. app.finance_invoices (Phase 8, app.list_customer_portal_invoices) --
-- every sibling Customer Portal list table (finance_receipts, wms_outbound_
-- orders, shipment_orders, tickets, loyalty_point_ledger_entries, loyalty_
-- redemptions, loyalty_liability_reconciliation_runs, inventory_balances)
-- already carries this shape; finance_invoices was the one outlier. Live-
-- measured: Seq Scan, 16.106ms, 804 buffer touches -> Index Scan, 0.072ms, 5
-- buffer touches (~224x, ~160x fewer buffers).
create index if not exists finance_invoices_tenant_updated_id_idx
  on app.finance_invoices (tenant_id, updated_at desc, id desc);

-- 2. app.saved_report_views (Phase 9, app.list_saved_report_views) -- the
-- existing saved_report_views_tenant_idx/owner_idx are both keyed by a SECOND
-- column (report_type_code / owner_auth_user_id) before created_at, which does
-- not serve this function's own ownership/sharing-scope OR-predicate scan
-- ordered by created_at alone. Live-measured: Seq Scan, 4.289ms -> Index Scan
-- (tenant_id Index Cond, OR-predicate as a post-index Filter -- the identical
-- shape ISS-2026-146's own C-05 sweep already established elsewhere), 0.045ms
-- (~95x).
create index if not exists saved_report_views_tenant_created_idx
  on app.saved_report_views (tenant_id, created_at desc);

-- 3. app.scheduled_reports (Phase 9, direct RLS-scoped table read --
-- server/queries/scheduled-report.ts listScheduledReports) -- the existing
-- scheduled_reports_tenant_idx is (tenant_id, status), not helpful for the
-- real query's own `order by updated_at desc`. Live-measured: Seq Scan +
-- full Sort, 4.771ms -> Index Scan (pre-sorted, no separate Sort node),
-- 1.581ms.
create index if not exists scheduled_reports_tenant_updated_idx
  on app.scheduled_reports (tenant_id, updated_at desc);

-- 4. app.webhook_deliveries (Phase 9, app.list_webhook_deliveries_for_tenant)
-- -- the existing indexes are keyed by webhook_endpoint_id or a WHERE
-- status='pending' partial predicate, neither of which serves a tenant-wide
-- (no p_webhook_endpoint_id filter) listing ordered by created_at. Live-
-- measured: Seq Scan, 7.689ms -> Index Scan, 0.082ms (~94x).
create index if not exists webhook_deliveries_tenant_created_idx
  on app.webhook_deliveries (tenant_id, created_at desc);

-- 5. app.retention_archive_requests (Phase 9, DR/retention surface) -- the
-- existing retention_archive_requests_tenant_lookup_idx is a 4-column
-- composite (tenant_id, source_table, source_record_id, requested_at desc)
-- built for the by-record lookup path; it does not serve a plain tenant-wide
-- listing ordered by requested_at, since source_table/source_record_id are
-- not supplied. Live-measured: Seq Scan, 9.453ms -> Index Scan, 0.081ms
-- (~117x).
create index if not exists retention_archive_requests_tenant_requested_idx
  on app.retention_archive_requests (tenant_id, requested_at desc);
