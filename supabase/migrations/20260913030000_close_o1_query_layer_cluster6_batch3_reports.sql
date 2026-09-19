-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 6
-- (platform-intelligence-reports) batch 3 of N.
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table in server/queries/*.ts has NEVER worked in production. Closes 6
-- broken `.from()` call sites across 2 files:
--
--   server/queries/report.ts:30              listActiveReportTypes
--   server/queries/report.ts:39              getReportTypeByCode
--   server/queries/report.ts:52              listReportRuns
--   server/queries/report.ts:66              listReportRunsForType
--   server/queries/report.ts:81              listReportTypeVersions
--   server/queries/saved-report-view.ts:24   getSavedReportViewById
--
-- 5 new app.*/public.* Option-2 wrapper pairs (10 functions), ALL SECURITY
-- INVOKER with ZERO actor parameter -- every real call site of all 6 TS
-- functions uses `createSupabaseServerClient()` only. `listReportRuns` and
-- `listReportRunsForType` deliberately share ONE new function
-- (app.list_report_runs, an optional nullable p_report_type_code parameter)
-- rather than two near-duplicate functions, per this batch's own
-- "could share one new function" note -- an implementation choice, disclosed.
--
-- ===========================================================================
-- SECURITY POSTURE -- three grant/RLS shapes
-- ===========================================================================
--
-- SHAPE 1 (no RLS, full-row grant, platform-wide): app.report_types
-- (20260724330000_create_commercial_reports.sql:61-...) and app.report_type_
-- versions (20260802010000_create_intelligence_reporting_engine.sql:110-...).
-- `relrowsecurity` never enabled for either (confirmed by repo-wide grep);
-- both carry a plain, never-narrowed `grant select ... to authenticated,
-- service_role`. `select *` is safe for both.
--
-- SHAPE 2 (RLS-scoped, tenant-membership predicate WITH explicit supreme-admin
-- disjunct, full-row grant): app.report_runs. RULE B, fresh grep of both
-- `create policy` and any later `alter policy` -- exactly 2 hits, the
-- original `create policy` (20260724330000:332-336) and the later `alter
-- policy` (20260730560000_harden_customer_user_layer_default_deny.sql:298-299,
-- current): `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_
-- customer_user_layer(tenant_id)) OR is_supreme_admin()`. `grant select on
-- app.report_runs to authenticated, service_role` (20260724330000:346) never
-- narrowed. `select *` is safe.
--
-- SHAPE 3 (RLS-scoped, 3-branch owner-vs-tenant-shared-vs-supreme-admin
-- predicate, full-row grant): app.saved_report_views. RULE B: `grep -rn
-- "saved_report_views_select_scoped" supabase/migrations/*.sql` -- the policy
-- was DROPPED AND RECREATED, not altered (a different mechanism than every
-- other RULE B finding in this series so far, independently traced rather
-- than assumed): the original `create policy`
-- (20260802030000_create_intelligence_saved_report_views.sql:449-...) was
-- explicitly `drop policy`-ed and replaced by a second `create policy` at
-- 20260810500000_harden_own_row_rls_membership_gap.sql:83-92 (current, no
-- later drop/replace exists). CURRENT text, reproduced verbatim rather than
-- re-derived:
--   using (
--     app.is_supreme_admin()
--     or (owner_auth_user_id = (select auth.uid())
--         and app.has_active_tenant_membership(tenant_id)
--         and not app.actor_holds_customer_user_layer(tenant_id))
--     or (sharing_scope = 'tenant'
--         and app.has_active_tenant_membership(tenant_id)
--         and not app.actor_holds_customer_user_layer(tenant_id))
--   );
-- This is a genuinely different shape from every other RLS predicate closed
-- in this whole Ø1-query-layer effort so far (owner-row vs tenant-shared-row
-- vs supreme-admin, not merely tenant-membership-vs-customer-layer) -- the new
-- function below relies entirely on the calling role's own live RLS
-- evaluation (SECURITY INVOKER, zero actor parameter), never re-implementing
-- this 3-branch logic in its own SQL body, so there is no risk of the subtle
-- reproduction error this batch's own recon note explicitly warned about.
-- `grant select on app.saved_report_views to authenticated, service_role`
-- (20260802030000:459) never narrowed -- `select *` is safe.

-- ---------------------------------------------------------------------------
-- 1. app.list_active_report_types -- replaces server/queries/report.ts:30
--    (listActiveReportTypes)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("report_types").select("*").eq("status", "active").order("code", { ascending: true })`.
create function app.list_active_report_types()
returns setof app.report_types
language sql
stable
as $$
  select * from app.report_types where status = 'active' order by code asc;
$$;

comment on function app.list_active_report_types() is
  'COM-159/O1 remediation: every active report type, code ascending, replacing server/queries/report.ts:30''s broken .from("report_types").select("*").eq("status", "active").order("code", { ascending: true }) (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- this table carries no RLS at all and a plain, never-narrowed grant select ... to authenticated, service_role. Deliberately security invoker (the unmarked default), matching this codebase''s own established shape for a zero-actor-param, no-RLS global reference table.';

create function public.list_active_report_types()
returns setof app.report_types
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_active_report_types();
$wrap$;

comment on function public.list_active_report_types() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_active_report_types with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_active_report_types() from public;
grant execute on function app.list_active_report_types() to authenticated, service_role;

revoke execute on function public.list_active_report_types() from anon, authenticated, service_role, public;
grant execute on function public.list_active_report_types() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.get_report_type_by_code -- replaces server/queries/report.ts:39
--    (getReportTypeByCode)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("report_types").select("*").eq("code", code).maybeSingle()`.
-- Deliberately NO status filter -- unlike app.list_active_report_types above,
-- matching the original .from() call's own documented difference exactly (a
-- retired report type must still resolve by code here).
create function app.get_report_type_by_code(p_code text)
returns setof app.report_types
language sql
stable
as $$
  select * from app.report_types where code = p_code;
$$;

comment on function app.get_report_type_by_code(text) is
  'COM-159/O1 remediation: one report type by code (any status, including retired), replacing server/queries/report.ts:39''s broken .from("report_types").select("*").eq("code", code).maybeSingle() (app is not exposed to PostgREST). Same security posture as app.list_active_report_types above. `returns setof app.report_types`, never a bare composite -- the standing defect-class check -- so a nonexistent code returns a GENUINELY EMPTY result, matching the original .maybeSingle() -> null contract exactly.';

create function public.get_report_type_by_code(p_code text)
returns setof app.report_types
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_report_type_by_code(p_code);
$wrap$;

comment on function public.get_report_type_by_code(text) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_report_type_by_code with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_report_type_by_code(text) from public;
grant execute on function app.get_report_type_by_code(text) to authenticated, service_role;

revoke execute on function public.get_report_type_by_code(text) from anon, authenticated, service_role, public;
grant execute on function public.get_report_type_by_code(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_report_runs -- replaces server/queries/report.ts:52
--    (listReportRuns) AND server/queries/report.ts:66 (listReportRunsForType)
-- ---------------------------------------------------------------------------
-- Replaces both: `.from("report_runs").select("*").eq("tenant_id",
-- tenantId)[.eq("report_type_code", reportTypeCode)].order("requested_at",
-- { ascending: false }).limit(limit)`. ONE shared function with a nullable
-- p_report_type_code parameter -- when null, behaves exactly like
-- listReportRuns; when supplied, exactly like listReportRunsForType.
create function app.list_report_runs(p_tenant_id uuid, p_report_type_code text default null, p_limit integer default 50)
returns setof app.report_runs
language sql
stable
as $$
  select * from app.report_runs
  where tenant_id = p_tenant_id
    and (p_report_type_code is null or report_type_code = p_report_type_code)
  order by requested_at desc
  limit greatest(coalesce(p_limit, 50), 0);
$$;

comment on function app.list_report_runs(uuid, text, integer) is
  'COM-159/O1 remediation: run history for one tenant, most recent first, optionally filtered to one report type, replacing BOTH server/queries/report.ts:52''s listReportRuns and server/queries/report.ts:66''s listReportRunsForType (the two are byte-for-byte identical except for the optional report_type_code filter) -- one shared function rather than two near-duplicates, a disclosed implementation choice (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies entirely on the calling role''s own live RLS evaluation of report_runs_select_scoped, CURRENT text (RULE B, 2 hits -- the original CREATE POLICY and the later, current ALTER POLICY): `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()`. p_limit passed straight through, matching both original calls'' own caller-supplied, unclamped limit (both default to 50).';

create function public.list_report_runs(p_tenant_id uuid, p_report_type_code text default null, p_limit integer default 50)
returns setof app.report_runs
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_report_runs(p_tenant_id, p_report_type_code, p_limit);
$wrap$;

comment on function public.list_report_runs(uuid, text, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_report_runs with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_report_runs(uuid, text, integer) from public;
grant execute on function app.list_report_runs(uuid, text, integer) to authenticated, service_role;

revoke execute on function public.list_report_runs(uuid, text, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_report_runs(uuid, text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.list_report_type_versions -- replaces server/queries/report.ts:81
--    (listReportTypeVersions)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("report_type_versions").select("*")
-- .eq("report_type_code", reportTypeCode).order("version_number", { ascending: false })`.
create function app.list_report_type_versions(p_report_type_code text)
returns setof app.report_type_versions
language sql
stable
as $$
  select * from app.report_type_versions
  where report_type_code = p_report_type_code
  order by version_number desc;
$$;

comment on function app.list_report_type_versions(text) is
  'IAE-002/O1 remediation: the full append-only definition-version history for one report type, newest first, replacing server/queries/report.ts:81''s broken .from("report_type_versions").select("*").eq("report_type_code", reportTypeCode).order("version_number", { ascending: false }) (app is not exposed to PostgREST). Zero parameters beyond p_report_type_code, zero in-function authority check -- this table carries no RLS at all and a plain, never-narrowed grant select ... to authenticated, service_role. Deliberately security invoker (the unmarked default).';

create function public.list_report_type_versions(p_report_type_code text)
returns setof app.report_type_versions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_report_type_versions(p_report_type_code);
$wrap$;

comment on function public.list_report_type_versions(text) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_report_type_versions with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_report_type_versions(text) from public;
grant execute on function app.list_report_type_versions(text) to authenticated, service_role;

revoke execute on function public.list_report_type_versions(text) from anon, authenticated, service_role, public;
grant execute on function public.list_report_type_versions(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.get_saved_report_view_by_id -- replaces server/queries/
--    saved-report-view.ts:24 (getSavedReportViewById)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("saved_report_views").select("*").eq("id", viewId).maybeSingle()`.
-- See this migration's own SHAPE 3 section above for the full 3-branch RLS
-- predicate this function relies on live rather than re-implements.
create function app.get_saved_report_view_by_id(p_view_id uuid)
returns setof app.saved_report_views
language sql
stable
as $$
  select * from app.saved_report_views where id = p_view_id;
$$;

comment on function app.get_saved_report_view_by_id(uuid) is
  'IAE-004/O1 remediation: one saved report view by id, replacing server/queries/saved-report-view.ts:24''s broken .from("saved_report_views").select("*").eq("id", viewId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies ENTIRELY on the calling role''s own live RLS evaluation of saved_report_views_select_scoped, whose CURRENT text (RULE B: the policy was DROPPED AND RECREATED, not altered -- confirmed current via 20260810500000_harden_own_row_rls_membership_gap.sql:83-92, no later drop/replace exists) is a genuinely 3-branch predicate (supreme-admin bypass, owner-row-plus-tenant-membership, or tenant-shared-row-plus-tenant-membership) -- deliberately NOT re-implemented in this function''s own SQL body, since a hand-rolled reproduction of this exact shape is the specific subtle-error risk this batch''s own recon note flagged. `returns setof app.saved_report_views`, never a bare composite, so a nonexistent id or an RLS-hidden row (private to a different owner, or a different tenant''s row entirely) both return a GENUINELY EMPTY result, matching the original .maybeSingle() -> null contract exactly. The sibling listSavedReportViews (server/queries/saved-report-view.ts) already correctly uses app.list_saved_report_views (RPC, pre-existing) for its own distinct list-shaped, paginated "own-or-tenant-shared" scope -- not reused here, since that function has no by-id path or cursor-free single-row shape.';

create function public.get_saved_report_view_by_id(p_view_id uuid)
returns setof app.saved_report_views
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_saved_report_view_by_id(p_view_id);
$wrap$;

comment on function public.get_saved_report_view_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_saved_report_view_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_saved_report_view_by_id(uuid) from public;
grant execute on function app.get_saved_report_view_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_saved_report_view_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_saved_report_view_by_id(uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/report.ts.
--
-- 1) listActiveReportTypes(client) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_active_report_types");
--      if (error) throw new ReportQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseReportType(row));
--
-- 2) getReportTypeByCode(client, code) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("get_report_type_by_code", { p_code: code });
--      if (error) throw new ReportQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseReportType(row as Record<string, unknown>);
--
-- 3) listReportRuns(client, tenantId, limit=50) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_report_runs", { p_tenant_id: tenantId, p_report_type_code: null, p_limit: limit });
--      if (error) throw new ReportQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseReportRun(row));
--
-- 4) listReportRunsForType(client, tenantId, reportTypeCode, limit=50) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_report_runs", { p_tenant_id: tenantId, p_report_type_code: reportTypeCode, p_limit: limit });
--      if (error) throw new ReportQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseReportRun(row));
--
-- 5) listReportTypeVersions(client, reportTypeCode) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_report_type_versions", { p_report_type_code: reportTypeCode });
--      if (error) throw new ReportQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseReportTypeVersion(row));
--
--    ReportQueryTableClient (line 19) changes from `Pick<SupabaseClient, "from">`
--    to `Pick<SupabaseClient, "rpc">` -- every function in this file converts here.
--
-- File: server/queries/saved-report-view.ts.
--
-- 6) getSavedReportViewById(client, viewId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("get_saved_report_view_by_id", { p_view_id: viewId });
--      if (error) throw new SavedReportViewQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseSavedReportView(row as Record<string, unknown>);
--
--    SavedReportViewQueryClient (line 13) already carries "rpc" alongside "from"
--    -- narrows from `Pick<SupabaseClient, "from" | "rpc">` to
--    `Pick<SupabaseClient, "rpc">` -- this was the file''s only "from" usage
--    (listSavedReportViews already used "rpc" exclusively).
