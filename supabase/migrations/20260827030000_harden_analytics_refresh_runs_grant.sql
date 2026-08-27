-- Track B Batch 1, ISS-2026-174 (docs/runtime/KNOWN_ISSUES.md): app.
-- analytics_refresh_runs is a deliberately global, no-RLS ledger (this
-- repository's own design note, 20260802040000_create_intelligence_
-- analytics_materialized_views.sql, mirrors app.report_types' "global
-- catalogue" precedent) -- there is no tenant_id column to scope an RLS
-- policy on, so the HDN-373 tenant-membership-conjunct pattern does not
-- apply here. But the table's own full-row `grant select ... to
-- authenticated` exposes more than any real caller uses: row_count_before/
-- row_count_after are PLATFORM-WIDE row counts (app.refresh_analytics_view
-- is Supreme-Admin-only, and the count itself has no tenant filter -- it
-- counts every tenant's rows in the underlying materialized view), and
-- triggered_by_auth_user_id/triggered_by_label are always the Supreme
-- Admin's own real identity. Live-confirmed reachable, not theoretical:
-- server/queries/analytics.ts's own listAnalyticsRefreshRuns/
-- getLatestAnalyticsRefreshRun do a raw `select("*")`, consumed by the
-- ordinary tenant Analytics page every authenticated member can load
-- (app/(tenant)/[tenantSlug]/analytics/page.tsx).
--
-- Design decision made here, disclosed rather than silently chosen: the
-- current UI legitimately displays row_count_after (a "reconciled (N rows)"
-- freshness badge -- a real, already-shipped feature, not incidental
-- leakage) -- dropping it would be a product regression, not just a
-- security fix, and is out of this bounded pass's own scope. The narrower,
-- correct fix is a COLUMN-level grant restriction (the same app.employees/
-- PLT-114 pattern already established elsewhere in this schema): keep the
-- one genuinely-used, non-identifying column (row_count_after), drop the
-- two undisputed leaks this entry's own text names (triggered_by_
-- auth_user_id/triggered_by_label -- a named admin's real identity exposed
-- platform-wide to every tenant) plus the one unused, redundant column
-- (row_count_before, superseded by row_count_after for freshness display).
-- No application code changes: server/queries/analytics.ts's existing raw
-- table SELECT keeps working unchanged, now returning a narrower row shape.
revoke select on app.analytics_refresh_runs from authenticated;
grant select (id, view_code, status, row_count_after, reconciled, error_reason, started_at, completed_at)
  on app.analytics_refresh_runs to authenticated;

comment on table app.analytics_refresh_runs is
  'IAE-005: deliberately global, no-RLS refresh ledger (mirrors app.report_types'' own "global catalogue" precedent) -- app.refresh_analytics_view is Supreme-Admin-only, so no tenant_id column exists to scope on. ISS-2026-174 fix (Track B Batch 1): authenticated''s grant is now column-restricted to (id, view_code, status, row_count_after, reconciled, error_reason, started_at, completed_at) -- row_count_before (unused, redundant) and triggered_by_auth_user_id/triggered_by_label (a named admin''s real identity, previously exposed platform-wide to every tenant) are no longer readable by authenticated. service_role retains the full-row grant.';
