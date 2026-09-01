# PRC-063 — ISS-2026-063 sub-item (2): extending the PRC-268/PRC-269 large-scale load proof to the remaining 5 target-volume surfaces

**Governing entry:** `docs/runtime/KNOWN_ISSUES.md` — `ISS-2026-063`. Two of the entry's three sub-items were already closed at Track B Batch 3 (`2026-08-27`); this checkpoint closes the third and last: "extending the `PRC-268`/`PRC-269` large-scale `EXPLAIN`-based load proof to the remaining 5 of 9 named surfaces (scorecards, match-case list, capacity, assignment, export throughput)."

**Status at end of this checkpoint:** all 5 surfaces measured live. 1 (scorecards) already used an efficient index path — no fix needed. 4 (match-case list, capacity, assignment, export/report-run history) genuinely degraded under the same adversarial skew `PRC-269` used to find `ISS-2026-056`, and are now fixed by `supabase/migrations/20260902090000_extend_procurement_dashboard_list_covering_indexes_iss2026063.sql`, applied live and object-verified. This is a real, newly-discovered performance defect class, not a confirmation of "indexing discipline by design" as the entry's own original framing assumed — disclosed exactly that way in the `KNOWN_ISSUES.md` closure below.

## 1. Scope and governing documents

- `docs/build-log/phase-06/PRC-268.md` §5 and §6.4 — read in full first. Establishes the methodology this checkpoint mirrors exactly: a synthetic multi-tenant scale (`PRC-268` used 25 tenants × 200 vendors = 5,000 identities), `EXPLAIN (ANALYZE, BUFFERS)` against the RPC's own literal query shape (never `EXPLAIN` on the opaque `SELECT app.rpc(...)` call node, since every target RPC here is `SECURITY DEFINER` PL/pgSQL), and the specific adversarial skew that actually found `ISS-2026-056`: "one tenant holds 68% of the table."
- `docs/build-log/phase-06/PRC-269.md` §2 Fix 6 — read in full first. The exact reproduction/fix/verification shape this checkpoint's own 4 fixes copy: a throwaway disposable database (never wired into `pnpm run db:test`), 7,497-row / 68.0%-skew seed, before/after `EXPLAIN (ANALYZE, BUFFERS)`, a plain `CREATE INDEX` (no `CONCURRENTLY` — this repository does not use it anywhere), applied live.
- `docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/271_PROCUREMENT_VENDOR_CLOSURE_VERIFICATION_PROMPT.md` item 21 — the source of the "~9 named target-volume surfaces" language: "target-volume vendor/rate search, RFQ list, PO list, ... capacity/assignment, scorecards, match, export ...". `PRC-268`/`PRC-269` covered vendor/rate search, RFQ list, PO list, vendor-contract list (4). This checkpoint covers the remaining 5 named in the `ISS-2026-063` entry's own text: scorecards, match-case list, capacity, assignment, export throughput.
- `scripts/load-tests/seed.sql`/`run.sh` (`CG-S10-ATW-024`, `ISS-2026-014`) — read in full first, as the task instructed. Establishes this repository's one other precedent for a large synthetic-volume seed: real RPCs for cheap one-time setup, bulk `INSERT...SELECT` directly into already-migrated tables for volume rows (never a per-row RPC loop), disclosed rather than silently substituted. `scripts/load-tests/` had no procurement-specific seed generator before this checkpoint (confirmed by direct listing) — this checkpoint adds one, following that same convention, rather than reusing `PRC-268`/`PRC-269`'s own seed (which was never committed to the repository; both build logs describe it in prose only, "built in a throwaway database").

## 2. Which RPC/query backs each of the 5 named surfaces

Identified by direct read of `server/queries/procurement-dashboard.ts`, `server/queries/vendor-performance.ts`, `server/queries/vendor-invoice-matching.ts`, `server/queries/vendor-capacity.ts`, `server/queries/vendor-assignment.ts`, `server/queries/report.ts`, and the app router page that actually calls each — never assumed from the RPC name alone.

| Surface | Real backing RPC / query | Table | Caller |
|---|---|---|---|
| Scorecards | `app.list_vendor_kpi_scorecards` (`p_vendor_master_id is null` branch) | `app.vendor_kpi_scorecards` | `listVendorKpiScorecards`, `server/queries/vendor-performance.ts` |
| Match-case list | `app.list_vendor_bill_match_cases` (no optional filters) | `app.vendor_bill_match_cases` | `listVendorBillMatchCases`, `server/queries/vendor-invoice-matching.ts` |
| Capacity | `app.list_vendor_capacity_offers` (no optional filters) | `app.vendor_capacity_offers` | `listVendorCapacityOffers`, `server/queries/vendor-capacity.ts` |
| Assignment | `app.list_vendor_assignment_invitations` (no optional filters) | `app.vendor_assignment_invitations` | `listVendorAssignmentInvitations`, `server/queries/vendor-assignment.ts` |
| Export throughput | `listReportRuns` (direct `.from("report_runs")`, **no** `report_type_code` filter) | `app.report_runs` | `app/(tenant)/[tenantSlug]/procurement/dashboard/page.tsx:157` — confirmed by direct read, the procurement dashboard's own export-history panel calls exactly this generic, no-type-filter query, not the type-filtered `listReportRunsForType` |

`app.report_runs` is a cross-module table (`app.enqueue_procurement_report_export` is a parallel entry point to the Finance/Ops/Commercial equivalents, all writing the same table) — a fix here benefits every module's own report-history panel identically, not procurement alone, disclosed rather than silently scoped as "procurement-only."

## 3. Synthetic-seed generator: `scripts/load-tests/procurement-scale-seed.sql`

New file, `scripts/load-tests/procurement-scale-seed.sql` — no prior procurement-specific large-scale generator existed to reuse or extend (confirmed by directory listing before writing it; `scripts/load-tests/` held only the `CG-S10-ATW-024` WMS/job/GPS seed, unrelated tables). Mirrors that file's own established discipline exactly, disclosed in its own header:

- **26 tenants** — tenant `#1` deliberately skewed, tenants `#2`–`#26` share the remainder evenly.
- **Cheap, one-time, real-shape setup via bulk `INSERT...SELECT`**, never a per-row RPC loop: 520 vendors (`app.master_records` + `app.vendor_profiles`, 20 per tenant), one real commercial-pipeline chain per tenant (lead → prospect → opportunity → quotation → job-order-handoff → job order — every NOT NULL FK a real row in the real parent table, never synthesized), 130 `shipment_orders` (5 per tenant, deliberately reused many-to-one by the volume rows below — no uniqueness constraint on `shipment_order_id` alone forces otherwise, and a real multi-round resourcing history legitimately reuses a shipment order too).
- **Five independently-skewed target tables, ~7,500 rows each, tenant `#1` holding exactly 5,100 (68.0%)** — matching `PRC-269`'s own reproduction ratio precisely, not merely "some skew": `app.vendor_kpi_scorecards`, `app.vendor_bill_match_cases` (+ one real `app.finance_vendor_bills` + `app.shipment_actual_costs` row per match case, its own real NOT NULL FK target, `is_current=false` so the reused `shipment_orders` pool never trips `shipment_actual_costs_one_current_idx`), `app.vendor_capacity_offers`, `app.vendor_assignment_invitations` (status forced to the real, unconstrained `expired` terminal state — `invited`/`accepted` are capped at one live row per `(tenant_id, shipment_order_id)` by a real partial unique index, which the reused 5-shipment-order pool would otherwise violate immediately at this row count; `declined`/`cancelled` both require a non-empty reason column, irrelevant to the query shape being measured), `app.report_runs` (spread across the 10 real `report_type_code` rows `PRC-266`'s own migration registered as exportable — not the 11 `procurement_metric_definitions` codes, which include the deliberately-non-exportable compliance-expiry queue).
- **Run once**, against a fresh disposable database with every `supabase/migrations/*.sql` already applied, via the same shared `scripts/db-tests/lib/setup-disposable-db.sh` every other db-test/load-test harness in this repository already uses — never duplicated. Never wired into `pnpm run db:test`, matching `PRC-269`'s own explicit disclosure ("a multi-thousand-row seed does not belong in the standing regression gate").
- Ends with a real row-count summary query (not a hand-typed claim) — reproduced in §5 below.

Two genuine bugs found and fixed while building this seed, disclosed rather than silently corrected:
1. A non-correlated `LATERAL (select gen_random_uuid() ...)` subquery (used to make `app.quotations.id`/`root_quotation_id` self-reference) was live-reproduced to be evaluated **once for the whole statement**, not once per row — every quotation row got the identical id, tripping the primary key. Fixed by generating the id into a keyed temp table first, then joining it in, rather than calling the volatile function twice in the same `SELECT`.
2. `app.vendor_kpi_scorecards_current_unique` (`tenant_id, vendor_master_id, window_start, window_end`) collided when the seed derived `window_start`/`window_end` from `n % 12` — at ~20 vendors × up to 5,100 rows, the same `(vendor, month-bucket)` pair repeated many times. Fixed by deriving the window from `n` directly (globally distinct per row within a tenant), not `n % 12`.

## 4. Live-verified results — before / after, per surface

Postgres 16, disposable local database, all 438 migrations applied in order, `procurement-scale-seed.sql` run, `analyze;` run, `EXPLAIN (ANALYZE, BUFFERS)` against tenant `#1` (the skewed 5,100-row tenant) with each RPC's own literal query shape copied verbatim from its migration body — the same "run EXPLAIN directly against the exact query shape" technique `scripts/load-tests/pagination-explain.sh`'s own header already documents for `SECURITY DEFINER` functions, since `EXPLAIN` on the RPC call itself only shows the opaque function-call node.

| # | Surface | Before: plan | Before: buffers | Before: time | After: plan | After: buffers | After: time | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | Scorecards | `Bitmap Index Scan` on the pre-existing `vendor_kpi_scorecards_current_unique` (highly selective — `is_current=true` is rare, ~20 of 5,100 rows per tenant) | hit=3 read=3 | 0.106–0.135 ms | *(unchanged — already efficient)* | *(unchanged)* | *(unchanged)* | **No fix needed** |
| 2 | Match-case list | `Bitmap Heap Scan` on `vendor_bill_match_cases_fingerprint_idx` (tenant_id only) across all 5,100 rows + top-N heapsort | read=333 written=9 (342) | 4.468 ms | `Index Scan` using new `vendor_bill_match_cases_tenant_created_idx`, `is_current` as a cheap post-scan `Filter` | read=5 written=4 (9) | 0.104 ms | **Fixed** — ~43× time, ~38× buffers |
| 3 | Capacity | `Bitmap Heap Scan` on `vendor_capacity_offers_tenant_service_idx` across all 5,100 rows + top-N heapsort | hit=3 read=121 (124) | 1.890 ms | `Index Scan` using new `vendor_capacity_offers_tenant_created_idx` | read=3 | 0.063 ms | **Fixed** — ~30× time, ~41× buffers |
| 4 | Assignment | `Bitmap Heap Scan` on `vendor_assignment_invitations_status_idx` across all 5,100 rows + top-N heapsort | hit=3 read=105 written=3 (111) | 1.673 ms | `Index Scan` using new `vendor_assignment_invitations_tenant_created_idx` | read=3 written=2 (5) | 0.086 ms | **Fixed** — ~19× time, ~22× buffers |
| 5 | Export (`listReportRuns`, no type filter) | `Bitmap Heap Scan` on `report_runs_tenant_requester_idx` across all 5,100 rows + top-N heapsort | hit=3 read=123 written=21 (147) | 2.436 ms | `Index Scan` using new `report_runs_tenant_requested_idx` | read=3 written=3 (6) | 0.097 ms | **Fixed** — ~25× time, ~24× buffers |

**Row-count summary (real counts from the seed's own final query, not a toy fixture):** 26 tenants, 520 vendors, 130 shipment_orders (pool), 7,500 rows each in `vendor_kpi_scorecards`/`finance_vendor_bills`/`vendor_bill_match_cases`/`vendor_capacity_offers`/`vendor_assignment_invitations`/`report_runs`; tenant `#1`'s own share of each: 5,100 (exactly 68.0%, matching `PRC-269`'s own reproduction ratio).

**Regression check — the type-filtered export variant.** `listReportRunsForType` (WITH a `report_type_code` filter) was re-verified unaffected by the new index: it continues to use its own pre-existing `report_runs_tenant_type_idx` (`Index Scan`, 8 buffers, 0.104 ms) — the new index is additive, not a replacement, and this checkpoint did not touch the type-filtered path at all.

## 5. A genuine finding within the finding: the rejected partial index

The natural first attempt for Fix 1 (match-case list) mirrored this table's own pre-existing `vendor_bill_match_cases_fingerprint_idx` convention — a **partial** index, `(tenant_id, created_at desc) where is_current`, since the RPC's own `WHERE` clause always applies `is_current` (not an optional, caller-supplied filter). This was built and measured first, and rejected:

```
Bitmap Heap Scan on vendor_bill_match_cases mc (cost=4.36..39.19 rows=10 ...) (actual ... rows=5100 ...)
  Recheck Cond: ((tenant_id = '...') AND is_current)
  ->  Bitmap Index Scan on vendor_bill_match_cases_tenant_current_created_idx (cost=0.00..4.35 rows=10 ...) (actual ... rows=5100 ...)
Execution Time: 11.648 ms
```

Even with the new partial index present and used, the planner still chose a full `Bitmap Heap Scan` + sort — its own row-count estimate for the partial index (`rows=10`) was roughly 500× lower than the real 5,100, which made the (actually much more expensive) bitmap-plus-sort path look artificially cheap in the planner's own cost model. Disabling bitmap scan (`set enable_bitmapscan=off`) forced the **identical index** into the correct ordered `Index Scan` (0.090 ms, 5 buffers) — proving the index itself was structurally fine and the defect was a planner cost-estimation trap specific to this partial-index shape at this data distribution (`is_current=true` for the overwhelming majority of rows — the rare case is a superseded historical version, the opposite skew a partial index normally wins on).

The applied fix instead uses a **plain, non-partial** index — `is_current` filtered afterward as an ordinary post-scan `Filter`, not folded into the index's own partial predicate. This gives the planner a clean, reliable `Index Scan` by default (verified above, §4 row 2), matches `ISS-2026-056`'s own `vendor_contracts_tenant_created_idx` shape exactly, and carries no partial-index caveat forward. Disclosed in full in the migration's own header/comment, not silently substituted.

## 6. The fix — migration and live application

`supabase/migrations/20260902090000_extend_procurement_dashboard_list_covering_indexes_iss2026063.sql` — 4 plain, additive `CREATE INDEX` statements (no `CONCURRENTLY`, matching this repository's own confirmed-by-grep convention, `ISS-2026-056`/`ISS-2026-113`'s own precedent):

- `vendor_bill_match_cases_tenant_created_idx` on `app.vendor_bill_match_cases (tenant_id, created_at desc)`
- `vendor_capacity_offers_tenant_created_idx` on `app.vendor_capacity_offers (tenant_id, created_at desc)`
- `vendor_assignment_invitations_tenant_created_idx` on `app.vendor_assignment_invitations (tenant_id, created_at desc)`
- `report_runs_tenant_requested_idx` on `app.report_runs (tenant_id, requested_at desc)`

Applied twice, independently: (1) against a fully clean, from-scratch, all-438-migration disposable local database — applies with zero error, and the same seed + `EXPLAIN` suite re-run against it reproduces the identical "after" numbers in §4 exactly (not merely asserted — this is the very run those numbers are captured from); (2) against the live Supabase project (`awdlicmwzdxquopwtcfd`) via the Supabase MCP `apply_migration` tool — `success: true`, and all 4 index names independently confirmed present via a direct `pg_indexes` query against the live project immediately afterward.

**Disclosed ledger quirk, not a defect in this migration:** the live project's `supabase_migrations.schema_migrations` recorded this migration under `version=20260901153930` (the MCP tool's own wall-clock call-time stamp) rather than this file's own `20260902090000` filename timestamp — the exact, already-documented, already-disclosed behavior `scripts/release/reconcile-migration-ledger.sql`'s own header describes ("the MCP apply_migration tool stamps its own wall-clock version instead of reading the file's filename-embedded timestamp"). Per this task's own ground rules, that reconciliation file is centrally amended by a coordinating session — not touched here.

No existing index dropped, no RPC body changed, no query result changed for any caller — purely additive access-path improvements, identical in kind and shape to `ISS-2026-056`.

## 7. Disposition summary

- **5 of 5 named surfaces measured live**, closing the sub-item's own stated scope exactly.
- **1 (scorecards)** already used an efficient index path at this skew scale — no fix needed, no new index added.
- **4 (match-case list, capacity, assignment, export/report-run history)** genuinely degraded under the identical adversarial skew that found `ISS-2026-056` — this is accurately reported as **more than the entry's own original "indexing discipline by design" framing implied**, matching this task's own instruction to report honestly if the item count grows. Fixed by 4 additive covering indexes, live-verified before and after, applied to both the local reproduction database and the live Supabase project.
- **One rejected design (the partial `is_current` index)** is disclosed in full (§5) rather than silently abandoned, since it is itself a genuine, reproducible planner-behavior finding relevant to any future index added to this table under a similarly-skewed `is_current`/`is_active`/`is_default` boolean-mostly-true column shape elsewhere in this repository.

## 8. Gate results (this checkpoint's own run)

| Gate | Command | Result |
|---|---|---|
| Typecheck | `pnpm run typecheck` | ✔ clean (0 errors) |
| Lint | `pnpm run lint` | pre-existing, unrelated tooling crash (`react/display-name`/`getFilename is not a function` against `app/(internal)/internal/design-system/accessibility/page.tsx`, a Node 24-vs-22 ESLint/eslint-plugin-react engine mismatch) — confirmed via `git stash` to reproduce identically against the unmodified baseline, before any change in this checkpoint existed |
| Unit/integration tests | `pnpm run test` | 5906 tests: 5904 pass, 1 fail, 1 skipped. The one failure is `scripts/docs/check-known-issues.test.ts`'s "the real ledger" suite, and only for its `SUMMARY_COUNT_STALE` findings (§3's summary counts now read 1 stale in three buckets — OPEN/open-Low/RESOLVED — the direct, expected, single-entry consequence of this checkpoint's own `ISS-2026-063` OPEN→RESOLVED flip). Per this task's own ground rules, `KNOWN_ISSUES.md`'s §3 summary count table is reconciled centrally by a coordinating session and was deliberately not touched here |
| Database tests | `bash scripts/db-tests/run.sh` (unique `TEST_DB_NAME` to avoid colliding with other concurrent sessions on the shared local Postgres) | ✔ **ALL PASSED** — every `*.sql` file, including every procurement file this checkpoint's own migration touches (`procurement-vendor-capacity.sql`, `procurement-vendor-assignment.sql`, `procurement-vendor-invoice-matching.sql`, `procurement-vendor-dashboard-reports.sql`) |
| Known-issues doc check | `pnpm run issues:check` | Same 3 `SUMMARY_COUNT_STALE` findings as the unit test above, for the identical reason — not a new/unrelated defect, the direct and expected consequence of closing this entry, left for central reconciliation per this task's own ground rules |
| Docs link check | `pnpm run docs:check` | ✔ passed |
| Protected-path check | `pnpm run git:check-paths` | ✔ passed (0 forbidden paths touched) |

A SEVERITY_DISAGREEMENT finding surfaced during this checkpoint's own gate run (§3's severity cell briefly read `Low-Medium`, a literal string the checker's `SEVERITY_PATTERN` regex does not treat as equal to the §4 heading's own regex-extracted `Low` token) — self-caught and fixed before commit, by recording `Low` in the §3 cell (matching this entry's own pre-existing convention: the ORIGINAL `Low` cell already coexisted correctly with a `Low-Medium`-worded heading, since the checker's regex reduces "Low-Medium" prose to its first matching token, `Low`, either way).
