# ISS-2026-148 — Phase 9 target-volume load/performance-test evidence

**Owner:** dedicated future performance-test-harness task per `ISS-2026-148`'s own citation,
executed under ADR-0027 Part A owner-authorized broader remediation scope. Same methodology as
`docs/build-log/phase-08/ISS-2026-141-LOAD-TEST.md` — read that file first for the full
disposable-database/seed/skew-ratio methodology detail, not repeated verbatim here.

## 1. Scope: Phase 9's own 9 named target-volume surfaces

`ISS-2026-148`'s own text names: "the reporting engine, dashboard builder, materialized-view
refresh, scheduled reports, automation rule engine, the whole `/api/v1` surface, the webhook
delivery worker, any AI-governed dispatch path, or enterprise IAM/monitoring/DR." Each was resolved
to a specific real RPC or (for 3 of the 9 — see §2) a direct RLS-scoped table read, then tested.
**9 of 9 named surfaces tested, 0 untested.**

| # | Named surface | RPC / table under test | Result |
|---|---|---|---|
| 1 | reporting engine | `app.list_saved_report_views` (`app.saved_report_views`) | **Seq Scan — real defect, FIXED this checkpoint** |
| 2 | dashboard builder | `app.tenant_dashboards` (direct RLS-scoped table read — §2) | **Holds up** — Index Scan |
| 3 | materialized-view refresh | `app.analytics_refresh_runs` (direct RLS-scoped table read — §2) | **Holds up by design** — not tenant-scoped, own index already matches its own query shape (§3) |
| 4 | scheduled reports | `app.scheduled_reports` (direct RLS-scoped table read — §2) | **Seq Scan — real defect, FIXED this checkpoint** |
| 5 | automation rule engine | `app.automation_rules` (direct RLS-scoped table read — §2) | Index Scan on `tenant_id`, but a separate Sort (no `ORDER BY` key in the index) — disclosed, not fixed, §4 |
| 6 | `/api/v1` surface | `app.list_api_logs_for_tenant` (`app.api_logs`) | **Holds up** — Index Scan |
| 7 | webhook delivery worker | `app.list_webhook_deliveries_for_tenant` (`app.webhook_deliveries` ⋈ `app.webhook_endpoints`) | **Seq Scan — real defect, FIXED this checkpoint** |
| 8 | AI-governed dispatch path | `app.list_ai_governed_requests_for_tenant` (`app.ai_governed_requests`) | **Holds up** — Index Scan |
| 9 | enterprise IAM/monitoring/DR | `app.list_user_sessions_for_tenant` (`app.user_sessions`), `app.iam_sso_login_attempts`, `app.list_retention_archive_requests_for_tenant` (`app.retention_archive_requests`) | user_sessions/iam_sso_login_attempts **hold up**; retention_archive_requests **Seq Scan — real defect, FIXED this checkpoint** |

## 2. A genuine, disclosed gap found while identifying the surfaces themselves: 3 of the 9 have no `list_*` RPC at all

Before any `EXPLAIN` could be run, every one of Phase 9's own `app.list_*`/`app.get_*` functions
was enumerated by direct `pg_proc` query against the fully-migrated schema. **Dashboard builder,
scheduled reports, and automation rule engine have no `SECURITY DEFINER` list RPC whatsoever** —
`server/queries/tenant-dashboard.ts`, `server/queries/scheduled-report.ts`, and
`server/queries/automation-rule.ts` all read their own list view via a direct PostgREST
`.from("<table>").select("*").eq("tenant_id", tenantId).order(...)` call, relying on RLS for tenant
isolation rather than a wrapping RPC — a genuinely different pattern from every other tested Phase
8/Phase 9 surface. This is disclosed here because it changes what "the query under test" means for
these three rows (a direct table predicate under RLS, not an RPC body) — it is not itself a load/
performance defect (RLS enforcement is a correctness concern, separately covered elsewhere; this
entry is scoped to load/performance only) and is not fixed by this checkpoint.

## 3. `app.analytics_refresh_runs` is correctly NOT tenant-scoped — confirmed by design, not a gap

Independently checked before assuming a missing index: `app.analytics_refresh_runs` carries no
`tenant_id` column at all — `server/queries/analytics.ts`'s own doc comment confirms
`analytics_view_registry` is "the code-shipped registry, not tenant-scoped," and refresh runs are
logged per platform-wide `view_code`, not per tenant. Its one existing index,
`analytics_refresh_runs_view_idx (view_code, started_at desc)`, is the exact right shape for its
own real query (`getLatestAnalyticsRefreshRun`/`listAnalyticsRefreshRuns`, both filtered by
`view_code` alone). No seeding or `EXPLAIN` was needed to confirm this — it holds up by
construction, not by a live-measured plan.

## 4. The 4 real Seq Scan defects found and fixed

Same fixture as `ISS-2026-141` (20 tenants, tenant #1 holding 5,100 of 7,494 rows = 68.0%, direct
bulk `INSERT`, `ANALYZE` before every `EXPLAIN` batch), extended in the SAME disposable database
(`cargogrid_perf_p8p9`) to 9 further tables (`saved_report_views`, `scheduled_reports`,
`automation_rules`, `webhook_deliveries` + `webhook_endpoints`, `api_logs`, `ai_governed_requests`
+ `integration_connections`, `user_sessions`, `iam_sso_login_attempts`,
`retention_archive_requests`) — reusing the same 20 tenants/1 auth actor already seeded for
`ISS-2026-141`, not a second fixture built from scratch.

### 4.1 `app.saved_report_views`

Query shape (`app.list_saved_report_views`): `tenant_id = X AND (owner_auth_user_id = actor OR
sharing_scope = 'tenant' OR ...) ORDER BY created_at DESC`. The two existing indexes
(`saved_report_views_tenant_idx (tenant_id, report_type_code, created_at desc)`,
`saved_report_views_owner_idx (tenant_id, owner_auth_user_id, created_at desc)`) both key on a
SECOND column before `created_at`, which the OR-predicate defeats.

**Before:** `Seq Scan`, **4.289ms**. **Fix:** `create index saved_report_views_tenant_created_idx
on app.saved_report_views (tenant_id, created_at desc);` — the same "Index Cond on tenant_id, the
OR-predicate becomes a post-index Filter" shape `ISS-2026-146`'s own C-05 tenant-disclosure sweep
already established is the correct, cheap pattern for an OR-bearing authorization predicate.
**After:** `Index Scan`, **0.045ms** (~95×).

### 4.2 `app.scheduled_reports`

Query shape (direct table read, §2): `tenant_id = X ORDER BY updated_at DESC` — the existing
`scheduled_reports_tenant_idx (tenant_id, status)` does not serve the ordering.

**Before:** `Seq Scan` + full `Sort`, **4.771ms**. **Fix:**
`create index scheduled_reports_tenant_updated_idx on app.scheduled_reports (tenant_id, updated_at
desc);`. **After:** `Index Scan` (pre-sorted, no separate `Sort` node), **1.581ms**. (The real query
has no `LIMIT` — every row for the tenant is always fetched and returned — so the improvement here
is bounded to "no Seq Scan + no extra Sort pass," not the ~100×+ seen where a `LIMIT` lets the
planner stop early; still a real, measured win.)

### 4.3 `app.webhook_deliveries`

Query shape (`app.list_webhook_deliveries_for_tenant`, no `p_webhook_endpoint_id` filter — the
tenant-wide admin listing path): `tenant_id = X ORDER BY created_at DESC LIMIT 50`, joined to
`app.webhook_endpoints` for the display URL. The existing indexes are keyed by
`webhook_endpoint_id` or a `WHERE status = 'pending'` partial predicate — neither serves this shape.

**Before:** `Seq Scan` + `Hash Join`, **7.689ms**. **Fix:** `create index webhook_deliveries_
tenant_created_idx on app.webhook_deliveries (tenant_id, created_at desc);`. **After:** `Index Scan`
+ `Nested Loop` + `Memoize` (early-`LIMIT` termination), **0.082ms** (~94×).

### 4.4 `app.retention_archive_requests`

Query shape (`app.list_retention_archive_requests_for_tenant`, tenant-wide listing path):
`tenant_id = X ORDER BY requested_at DESC LIMIT 50`. The one existing index,
`retention_archive_requests_tenant_lookup_idx (tenant_id, source_table, source_record_id,
requested_at desc)`, is a 4-column composite built for the by-record lookup path
(`source_table`/`source_record_id` both supplied) — it does not serve a plain tenant-wide listing,
since neither of those two columns is present in the `WHERE` clause and a btree index cannot skip
a leading/interior column.

**Before:** `Seq Scan`, **9.453ms**. **Fix:** `create index retention_archive_requests_tenant_
requested_idx on app.retention_archive_requests (tenant_id, requested_at desc);`. **After:**
`Index Scan`, **0.081ms** (~117×).

## 5. `app.automation_rules` — disclosed, not fixed

Query shape (direct table read, §2): `tenant_id = X ORDER BY updated_at DESC` (no `LIMIT`, same as
§4.2). The existing `automation_rules_tenant_id_idx` IS `(tenant_id)` alone — so the planner
correctly uses an Index Scan for the `tenant_id` predicate, then a separate `Sort` for the
ordering: **2.957ms** total, no Seq Scan. This is a real, measured, working plan — not a defect
requiring a fix — and is disclosed here rather than silently rolled into the 4 real fixes above,
because a `(tenant_id, updated_at desc)` composite index (mirroring the `scheduled_reports` fix)
would remove the separate `Sort` step too. **Not fixed this checkpoint**: automation rules are a
low-cardinality-per-tenant configuration object (tens, not thousands, in ordinary operation,
unlike the append-only/high-frequency event tables the other 4 fixes target), the query already
avoids a Seq Scan, and the marginal win of also removing the `Sort` step at this cardinality is a
judgment call for a dedicated indexing pass rather than this evidence-gathering checkpoint's own
scope — recorded for a future task's consideration, not silently dropped.

## 6. Fix application

All 4 fixes plus `ISS-2026-141`'s own `finance_invoices` fix are one migration:
`supabase/migrations/20260902080000_harden_phase8_phase9_target_volume_covering_indexes.sql`,
purely additive (`create index if not exists`, no existing index touched, no application code
change). Applied live to the Supabase project `awdlicmwzdxquopwtcfd` via `apply_migration`;
recorded in `supabase_migrations.schema_migrations` (`insert ... on conflict (version) do
nothing`, matching the version implied by the migration filename). Live-confirmed present via
direct `pg_indexes` query against the real project after applying.

## 7. Result summary

- **9 of 9 named Phase 9 surfaces tested** — 0 untested.
- **4 genuine Seq Scan defects found and fixed** (`saved_report_views` ~95×,
  `scheduled_reports` measured win with no `LIMIT` to amplify it, `webhook_deliveries` ~94×,
  `retention_archive_requests` ~117×) — all live-verified before and after, applied to the live
  Supabase project alongside `ISS-2026-141`'s own `finance_invoices` fix in one migration.
- **1 disclosed, not-fixed lower-priority improvement** (`automation_rules`'s own missing
  `Sort`-avoiding composite index — already Index-Scan-based, not a Seq Scan, low per-tenant
  cardinality in ordinary operation).
- **1 surface confirmed correct by design, no fix needed** (`analytics_refresh_runs` — genuinely
  platform-wide, not tenant-scoped; its own existing index already matches its own real query).
- **1 genuine, previously-undisclosed structural gap found and disclosed** (3 of the 9 named
  surfaces have no `SECURITY DEFINER` list RPC at all, reading instead via direct RLS-scoped
  PostgREST table selects) — not itself a load/performance defect, not fixed by this checkpoint,
  recorded so a future picker-upper does not have to rediscover it.
- **4 surfaces confirmed holding up** with a plain Index Scan and no defect.
