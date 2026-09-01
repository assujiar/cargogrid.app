-- ISS-2026-063 sub-item (2) closure: the large-scale EXPLAIN-based load proof
-- from PRC-268/PRC-269 (docs/build-log/phase-06/PRC-268.md section 5,
-- PRC-269.md section 2 Fix 6) covered only 4 of the ~9 named target-volume
-- surfaces (vendor/rate search, RFQ list, PO list, vendor-contract list). This
-- migration extends that proof to 4 of the remaining 5 (match-case list,
-- capacity, assignment, export/report-run history) after live-reproducing the
-- identical planner defect PRC-269's own Fix 6 found and fixed for
-- app.list_vendor_contracts -- see docs/build-log/phase-06/PRC-063-LOAD-
-- PROOF.md for the full methodology, seed, and before/after EXPLAIN evidence.
-- The 5th surface (scorecards) was independently confirmed to already use an
-- efficient index path and needs no fix -- see that same build log.
--
-- Each of the 4 fixed RPCs shares the identical shape: `where tenant_id =
-- p_tenant_id [and other optional equality filters] order by <timestamp>
-- desc limit N`, with no index whose leading columns are (tenant_id,
-- <that same timestamp column> desc). At a 26-tenant / ~7,500-row synthetic
-- scale with one tenant deliberately holding 68.0% of each table (the exact
-- skew ratio PRC-269's own reproduction used), every one of the 4 forced the
-- planner into a Bitmap Heap Scan across that tenant's ENTIRE row set followed
-- by a top-N sort, rather than an ordered Index Scan with early-LIMIT
-- termination -- reading 100-330+ buffers and 1.6-4.5ms per call instead of
-- 3-8 buffers and ~0.1ms. Purely additive: no existing index dropped, no RPC
-- body changed, no behavior change to any query result -- only its access
-- path. Mirrors ISS-2026-056's own vendor_contracts_tenant_created_idx fix
-- (Prompt 269 Hardening) and ISS-2026-113's own tickets_tenant_created_idx fix
-- (HRT-294) exactly. Plain CREATE INDEX -- this repository does not use
-- CONCURRENTLY anywhere (confirmed by repository-wide grep, matching both of
-- those precedents' own disclosed convention).

-- Fix 1/4 -- app.list_vendor_bill_match_cases (20260730750000, "match-case
-- list"). The RPC's own WHERE clause always applies `mc.is_current` (not an
-- optional filter -- every call site passes it implicitly via the function
-- body, never a caller-supplied parameter). A PARTIAL index scoped to
-- is_current (mirroring this table's own pre-existing vendor_bill_match_
-- cases_fingerprint_idx partial-index convention) was tried FIRST and
-- REJECTED after live measurement: at this table's real distribution (is_
-- current=true for the overwhelming majority of rows -- superseded historical
-- versions are the rare case), the planner's partial-index selectivity
-- estimate came out ~500x too low (est. rows=10 against an actual 5,100),
-- which made a Bitmap Heap Scan across the ENTIRE matching set plus a
-- redundant top-N sort look artificially cheap -- confirmed by disabling
-- bitmap scan (`set enable_bitmapscan=off`), which forced the identical
-- partial index into the correct fast ordered Index Scan, proving the index
-- itself was fine and the defect was purely a planner cost-estimation trap
-- for THIS specific partial-index shape. A plain, non-partial index (is_
-- current filtered afterward as a cheap post-scan Filter, not a Recheck
-- Cond) sidesteps the estimation trap entirely and gives the planner a clean,
-- reliable ordered Index Scan by default -- matching Fixes 2-4 below and
-- ISS-2026-056''s own vendor_contracts precedent exactly, with no partial-
-- index caveat to carry forward.
create index vendor_bill_match_cases_tenant_created_idx
  on app.vendor_bill_match_cases (tenant_id, created_at desc);

comment on index app.vendor_bill_match_cases_tenant_created_idx is
  'ISS-2026-063: covering index for app.list_vendor_bill_match_cases''s own (tenant_id = ... and is_current order by created_at desc) shape -- without it the planner bitmap-scans every match case for the tenant via vendor_bill_match_cases_fingerprint_idx (tenant_id only) and sorts, rather than an ordered Index Scan with early-LIMIT termination and is_current as a cheap post-scan Filter. A partial (WHERE is_current) variant was tried and rejected -- it tripped a real planner cost-misestimation (~500x row-count underestimate) that picked an inefficient Bitmap Heap Scan even with the partial index present; this plain index does not. Live-verified ~100x execution-time / ~45x buffer-read improvement at a 5,100-row single-tenant skew. Mirrors ISS-2026-056''s own vendor_contracts_tenant_created_idx fix exactly.';

-- Fix 2/4 -- app.list_vendor_capacity_offers (20260730710000, "capacity").
-- No mandatory predicate beyond tenant_id (vendor/status/service_type are all
-- optional filters) -- a plain, non-partial covering index, matching
-- app.purchase_orders/app.rfqs/app.vendor_comparisons/app.vendor_contracts'
-- own identical shape.
create index vendor_capacity_offers_tenant_created_idx
  on app.vendor_capacity_offers (tenant_id, created_at desc);

comment on index app.vendor_capacity_offers_tenant_created_idx is
  'ISS-2026-063: covering index for app.list_vendor_capacity_offers''s own (tenant_id = ... order by created_at desc) shape -- without it the planner bitmap-scans every offer for the tenant via vendor_capacity_offers_tenant_service_idx (a status/service_type-oriented index, not ordered by created_at) and sorts. Live-verified ~25x execution-time / ~40x buffer-read improvement at a 5,100-row single-tenant skew. Mirrors ISS-2026-056''s own vendor_contracts_tenant_created_idx fix exactly.';

-- Fix 3/4 -- app.list_vendor_assignment_invitations (20260730720000,
-- "assignment"). Same shape as Fix 2 -- shipment_order_id/vendor_master_id/
-- status are all optional filters.
create index vendor_assignment_invitations_tenant_created_idx
  on app.vendor_assignment_invitations (tenant_id, created_at desc);

comment on index app.vendor_assignment_invitations_tenant_created_idx is
  'ISS-2026-063: covering index for app.list_vendor_assignment_invitations''s own (tenant_id = ... order by created_at desc) shape -- without it the planner bitmap-scans every invitation for the tenant via vendor_assignment_invitations_status_idx (not ordered by created_at) and sorts. Live-verified ~20x execution-time / ~35x buffer-read improvement at a 5,100-row single-tenant skew. Mirrors ISS-2026-056''s own vendor_contracts_tenant_created_idx fix exactly.';

-- Fix 4/4 -- app.report_runs (20260724330000, COM-159 -- "export/report-run
-- history"), the shared cross-module table server/queries/report.ts's own
-- listReportRuns reads (app/(tenant)/[tenantSlug]/procurement/dashboard/
-- page.tsx:157 calls it with no report_type_code filter). The one PRE-
-- EXISTING composite index on this table, report_runs_tenant_type_idx
-- (tenant_id, report_type_code, requested_at desc), only satisfies the ORDER
-- BY for a SINGLE report_type_code at a time (listReportRunsForType) -- a
-- caller that omits the type filter, exactly what the procurement dashboard's
-- own export-history panel does, sees rows from every report_type_code
-- interleaved, so the index's own (..., report_type_code, requested_at desc)
-- ordering does not satisfy a GLOBAL requested_at-desc walk. A second,
-- narrower covering index closes it -- purely additive, benefits every
-- module's own report-history panel identically, not procurement-only.
create index report_runs_tenant_requested_idx
  on app.report_runs (tenant_id, requested_at desc);

comment on index app.report_runs_tenant_requested_idx is
  'ISS-2026-063: covering index for the generic, no-report_type_code-filter server/queries/report.ts listReportRuns shape (tenant_id = ... order by requested_at desc) -- report_runs_tenant_type_idx alone only satisfies that ORDER BY within one report_type_code at a time, not across every type mixed together. Live-verified ~25x execution-time / ~30x buffer-read improvement at a 5,100-row single-tenant skew. Shared across every report-exporting module (Commercial/Finance/Ops/Procurement), not procurement-specific.';
