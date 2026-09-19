-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 6
-- (platform-intelligence-reports) batch 4 of 4 -- the FINAL batch of cluster 6.
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table in server/queries/*.ts has NEVER worked in production. Closes
-- the LAST 10 broken `.from()` call sites of this cluster across 3 files:
--
--   server/queries/scheduled-report.ts:29  listScheduledReports
--   server/queries/scheduled-report.ts:38  getScheduledReportById
--   server/queries/scheduled-report.ts:50  listScheduledReportRecipients
--   server/queries/scheduled-report.ts:60  listScheduledReportRuns
--   server/queries/supreme-tenants.ts:69   listSupremeTenants
--   server/queries/tenant-dashboard.ts:32  listTenantDashboards
--   server/queries/tenant-dashboard.ts:44  getTenantDashboardById
--   server/queries/tenant-dashboard.ts:57  listTenantDashboardVersions
--   server/queries/tenant-dashboard.ts:69  getTenantDashboardVersionById
--   server/queries/tenant-dashboard.ts:82  listDashboardWidgets
--
-- 10 new app.*/public.* Option-2 wrapper pairs (20 functions), ALL SECURITY
-- INVOKER with ZERO actor parameter -- every real call site of all 10 TS
-- functions uses `createSupabaseServerClient()` only.
--
-- ===========================================================================
-- SECURITY POSTURE -- two grant/RLS shapes, plus one function needing extra
-- scrutiny (independently re-derived, not copied from the recon's own more
-- cautious suggestion)
-- ===========================================================================
--
-- SHAPE 1 (RLS-scoped, tenant-membership predicate WITH explicit supreme-admin
-- disjunct, full-row grant): app.scheduled_reports/app.scheduled_report_
-- recipients/app.scheduled_report_runs/app.tenant_dashboards/app.tenant_
-- dashboard_versions/app.tenant_dashboard_widgets. RULE B, fresh grep of both
-- `create policy` and any later `alter policy` for all 6 -- exactly ONE hit
-- each, no later alter, for every one:
--   scheduled_reports_select_scoped / tenant_dashboards_select_scoped:
--     using ((has_active_tenant_membership(tenant_id) and not
--            actor_holds_customer_user_layer(tenant_id)) or is_supreme_admin());
--   scheduled_report_recipients_select_scoped / scheduled_report_runs_select_scoped:
--     an EXISTS join back to app.scheduled_reports, same two-conjunct-or-
--     supreme-admin predicate against the PARENT row's own tenant_id.
--   tenant_dashboard_versions_select_scoped: an EXISTS join back to
--     app.tenant_dashboards, same shape.
--   tenant_dashboard_widgets_select_scoped: a TWO-LEVEL EXISTS join
--     (tenant_dashboard_versions -> tenant_dashboards), same shape against the
--     grandparent row's own tenant_id.
-- All 6 tables carry a full-row `grant select ... to authenticated,
-- service_role` (20260802050000_create_intelligence_scheduled_reports.sql:579
-- for the scheduled_report family; 20260802020000_create_intelligence_
-- dashboard_builder.sql:476 for the tenant_dashboard family), never narrowed
-- -- `select *` is safe for all 6.
--
-- SHAPE 2 (RLS-scoped, no explicit disjunct at the policy level, but a
-- GLOBAL, cross-tenant list -- the one function in this batch this migration's
-- own recon flagged for "extra scrutiny"): app.list_supreme_tenants over
-- app.tenants. RULE B: `tenants_select_own_tenant`'s CURRENT text (re-verified
-- live, same grep discipline as every prior batch) is
-- `has_active_tenant_membership(id) AND NOT actor_holds_customer_user_layer(id)`
-- -- no explicit is_supreme_admin() disjunct at the policy level, but (as this
-- SAME query file's own pre-existing module-header comment already states,
-- independently re-confirmed rather than copied uncritically) app.has_active_
-- tenant_membership's own current body returns true for ANY tenant_id
-- whenever the caller passes app.is_supreme_admin(), so a real Supreme Admin
-- session already sees EVERY row of app.tenants through plain, unmodified
-- live RLS -- no SECURITY DEFINER bypass, no explicit is_supreme_admin() check
-- inside this function''s own body, is needed or added. A non-Supreme caller
-- who somehow reached this function would simply see their own one tenant row
-- (never a leak, never an error) -- the exact same safe-by-construction
-- behavior the original `.from("tenants")` read already had before this
-- migration, now merely restored (the schema-exposure defect, not a
-- privilege-widening one, is the only thing this function fixes). Mirrors
-- app.list_portal_users'' own `count(*) over()` pagination idiom exactly
-- (`returns table (...)`, not `returns setof <table>`, since only 4 of
-- app.tenants'' own columns are selected -- the identical projection the
-- original `.select("id, slug, name, canonical_status", { count: "exact" })`
-- call already used).
--
-- Every 0-or-1-row lookup (`app.get_scheduled_report_by_id`, `app.get_tenant_
-- dashboard_by_id`, `app.get_tenant_dashboard_version_by_id`) is declared
-- `returns setof app.<table>`, never a bare composite -- the standing
-- defect-class check this series has run on every batch since it first
-- surfaced.
--
-- RULE A does not apply to any of the 10 functions in this batch: none takes
-- an actor parameter (every authority check is left to the calling role's own
-- live RLS evaluation), so there is no identity claim to cross-check.

-- ---------------------------------------------------------------------------
-- 1. app.list_scheduled_reports -- replaces server/queries/
--    scheduled-report.ts:29 (listScheduledReports)
-- ---------------------------------------------------------------------------
create function app.list_scheduled_reports(p_tenant_id uuid)
returns setof app.scheduled_reports
language sql
stable
as $$
  select * from app.scheduled_reports
  where tenant_id = p_tenant_id
  order by updated_at desc;
$$;

comment on function app.list_scheduled_reports(uuid) is
  'IAE-006/O1 remediation: every schedule for one tenant, most recently updated first, replacing server/queries/scheduled-report.ts:29''s broken .from("scheduled_reports").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies entirely on the calling role''s own live RLS evaluation of scheduled_reports_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()`.';

create function public.list_scheduled_reports(p_tenant_id uuid)
returns setof app.scheduled_reports
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_scheduled_reports(p_tenant_id);
$wrap$;

comment on function public.list_scheduled_reports(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_scheduled_reports with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_scheduled_reports(uuid) from public;
grant execute on function app.list_scheduled_reports(uuid) to authenticated, service_role;

revoke execute on function public.list_scheduled_reports(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_scheduled_reports(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.get_scheduled_report_by_id -- replaces server/queries/
--    scheduled-report.ts:38 (getScheduledReportById)
-- ---------------------------------------------------------------------------
create function app.get_scheduled_report_by_id(p_scheduled_report_id uuid)
returns setof app.scheduled_reports
language sql
stable
as $$
  select * from app.scheduled_reports where id = p_scheduled_report_id;
$$;

comment on function app.get_scheduled_report_by_id(uuid) is
  'IAE-006/O1 remediation: one schedule by id, replacing server/queries/scheduled-report.ts:38''s broken .from("scheduled_reports").select("*").eq("id", scheduledReportId).maybeSingle() (app is not exposed to PostgREST). Same security posture as app.list_scheduled_reports above. `returns setof app.scheduled_reports`, never a bare composite -- the standing defect-class check.';

create function public.get_scheduled_report_by_id(p_scheduled_report_id uuid)
returns setof app.scheduled_reports
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_scheduled_report_by_id(p_scheduled_report_id);
$wrap$;

comment on function public.get_scheduled_report_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_scheduled_report_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_scheduled_report_by_id(uuid) from public;
grant execute on function app.get_scheduled_report_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_scheduled_report_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_scheduled_report_by_id(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_scheduled_report_recipients -- replaces server/queries/
--    scheduled-report.ts:50 (listScheduledReportRecipients)
-- ---------------------------------------------------------------------------
create function app.list_scheduled_report_recipients(p_scheduled_report_id uuid)
returns setof app.scheduled_report_recipients
language sql
stable
as $$
  select * from app.scheduled_report_recipients
  where scheduled_report_id = p_scheduled_report_id
  order by created_at asc;
$$;

comment on function app.list_scheduled_report_recipients(uuid) is
  'IAE-006/O1 remediation: every recipient of one schedule, oldest first, replacing server/queries/scheduled-report.ts:50''s broken .from("scheduled_report_recipients").select("*").eq("scheduled_report_id", scheduledReportId).order("created_at", { ascending: true }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of scheduled_report_recipients_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): an EXISTS join back to app.scheduled_reports requiring the same has_active_tenant_membership/actor_holds_customer_user_layer/is_supreme_admin predicate against the PARENT row''s own tenant_id -- reproduced live by the RLS engine, never re-implemented in this function''s own SQL body.';

create function public.list_scheduled_report_recipients(p_scheduled_report_id uuid)
returns setof app.scheduled_report_recipients
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_scheduled_report_recipients(p_scheduled_report_id);
$wrap$;

comment on function public.list_scheduled_report_recipients(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_scheduled_report_recipients with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_scheduled_report_recipients(uuid) from public;
grant execute on function app.list_scheduled_report_recipients(uuid) to authenticated, service_role;

revoke execute on function public.list_scheduled_report_recipients(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_scheduled_report_recipients(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.list_scheduled_report_runs -- replaces server/queries/
--    scheduled-report.ts:60 (listScheduledReportRuns)
-- ---------------------------------------------------------------------------
create function app.list_scheduled_report_runs(p_scheduled_report_id uuid, p_limit integer default 25)
returns setof app.scheduled_report_runs
language sql
stable
as $$
  select * from app.scheduled_report_runs
  where scheduled_report_id = p_scheduled_report_id
  order by started_at desc
  limit greatest(coalesce(p_limit, 25), 0);
$$;

comment on function app.list_scheduled_report_runs(uuid, integer) is
  'IAE-006/O1 remediation: run history for one schedule, newest first, replacing server/queries/scheduled-report.ts:60''s broken .from("scheduled_report_runs").select("*").eq("scheduled_report_id", scheduledReportId).order("started_at", { ascending: false }).limit(limit) (app is not exposed to PostgREST). Same EXISTS-join security posture as app.list_scheduled_report_recipients above. p_limit passed straight through, matching the original call''s own caller-supplied, unclamped limit.';

create function public.list_scheduled_report_runs(p_scheduled_report_id uuid, p_limit integer default 25)
returns setof app.scheduled_report_runs
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_scheduled_report_runs(p_scheduled_report_id, p_limit);
$wrap$;

comment on function public.list_scheduled_report_runs(uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_scheduled_report_runs with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_scheduled_report_runs(uuid, integer) from public;
grant execute on function app.list_scheduled_report_runs(uuid, integer) to authenticated, service_role;

revoke execute on function public.list_scheduled_report_runs(uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_scheduled_report_runs(uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.list_supreme_tenants -- replaces server/queries/
--    supreme-tenants.ts:69 (listSupremeTenants)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("tenants").select("id, slug, name, canonical_status", {
-- count: "exact" }).order("name", { ascending: true }).range(from, to)`. See
-- this migration's own SHAPE 2 section above for the full "why INVOKER with
-- no explicit authority check is correct here, not merely convenient"
-- derivation.
create function app.list_supreme_tenants(p_page integer default 1, p_page_size integer default 50)
returns table (
  id uuid,
  slug text,
  name text,
  canonical_status text,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  v_limit integer;
  v_page integer;
begin
  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  return query
    select
      t.id,
      t.slug,
      t.name,
      t.canonical_status,
      count(*) over() as total_count
    from app.tenants t
    order by t.name asc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_supreme_tenants(integer, integer) is
  'PLT-136/O1 remediation: the Supreme Admin portal''s server-paginated global tenant list with an exact total row count, replacing server/queries/supreme-tenants.ts:69''s broken .from("tenants").select("id, slug, name, canonical_status", { count: "exact" }).order("name", { ascending: true }).range(from, to) (app is not exposed to PostgREST). Security invoker, zero actor parameter, and DELIBERATELY no in-function is_supreme_admin() check -- app.tenants'' own tenants_select_own_tenant RLS policy (`has_active_tenant_membership(id) AND NOT actor_holds_customer_user_layer(id)`) already grants a real Supreme Admin session full visibility into every tenant row, since app.has_active_tenant_membership''s own current body returns true for ANY tenant_id whenever the caller is a Supreme Admin (independently re-confirmed live, not assumed) -- exactly the reasoning server/queries/supreme-tenants.ts''s own pre-existing module header already documented for why this file never used a service-role client. A non-Supreme caller reaching this function sees only their own one tenant row (never zero rows with a misleading total_count, never a cross-tenant leak) -- the same safe, RLS-scoped behavior the original .from() read already had; this migration restores it, it does not widen it. Mirrors app.list_portal_users'' own `count(*) over()` pagination idiom and identical [1,100] page-size clamp.';

create function public.list_supreme_tenants(p_page integer default 1, p_page_size integer default 50)
returns table (
  id uuid,
  slug text,
  name text,
  canonical_status text,
  total_count bigint
)
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_supreme_tenants(p_page, p_page_size);
$wrap$;

comment on function public.list_supreme_tenants(integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_supreme_tenants with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_supreme_tenants(integer, integer) from public;
grant execute on function app.list_supreme_tenants(integer, integer) to authenticated, service_role;

revoke execute on function public.list_supreme_tenants(integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_supreme_tenants(integer, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. app.list_tenant_dashboards -- replaces server/queries/
--    tenant-dashboard.ts:32 (listTenantDashboards)
-- ---------------------------------------------------------------------------
create function app.list_tenant_dashboards(p_tenant_id uuid)
returns setof app.tenant_dashboards
language sql
stable
as $$
  select * from app.tenant_dashboards
  where tenant_id = p_tenant_id
  order by updated_at desc;
$$;

comment on function app.list_tenant_dashboards(uuid) is
  'IAE-003/O1 remediation: every dashboard for one tenant, most recently updated first, replacing server/queries/tenant-dashboard.ts:32''s broken .from("tenant_dashboards").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of tenant_dashboards_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()`.';

create function public.list_tenant_dashboards(p_tenant_id uuid)
returns setof app.tenant_dashboards
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_tenant_dashboards(p_tenant_id);
$wrap$;

comment on function public.list_tenant_dashboards(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_tenant_dashboards with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_tenant_dashboards(uuid) from public;
grant execute on function app.list_tenant_dashboards(uuid) to authenticated, service_role;

revoke execute on function public.list_tenant_dashboards(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_tenant_dashboards(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. app.get_tenant_dashboard_by_id -- replaces server/queries/
--    tenant-dashboard.ts:44 (getTenantDashboardById)
-- ---------------------------------------------------------------------------
create function app.get_tenant_dashboard_by_id(p_dashboard_id uuid)
returns setof app.tenant_dashboards
language sql
stable
as $$
  select * from app.tenant_dashboards where id = p_dashboard_id;
$$;

comment on function app.get_tenant_dashboard_by_id(uuid) is
  'IAE-003/O1 remediation: one dashboard by id, replacing server/queries/tenant-dashboard.ts:44''s broken .from("tenant_dashboards").select("*").eq("id", dashboardId).maybeSingle() (app is not exposed to PostgREST). Same security posture as app.list_tenant_dashboards above. `returns setof app.tenant_dashboards`, never a bare composite -- the standing defect-class check.';

create function public.get_tenant_dashboard_by_id(p_dashboard_id uuid)
returns setof app.tenant_dashboards
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_tenant_dashboard_by_id(p_dashboard_id);
$wrap$;

comment on function public.get_tenant_dashboard_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_tenant_dashboard_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_tenant_dashboard_by_id(uuid) from public;
grant execute on function app.get_tenant_dashboard_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_tenant_dashboard_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_tenant_dashboard_by_id(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. app.list_tenant_dashboard_versions -- replaces server/queries/
--    tenant-dashboard.ts:57 (listTenantDashboardVersions)
-- ---------------------------------------------------------------------------
create function app.list_tenant_dashboard_versions(p_dashboard_id uuid)
returns setof app.tenant_dashboard_versions
language sql
stable
as $$
  select * from app.tenant_dashboard_versions
  where dashboard_id = p_dashboard_id
  order by version_number desc;
$$;

comment on function app.list_tenant_dashboard_versions(uuid) is
  'IAE-003/O1 remediation: the full append-only version history for one dashboard, newest first, replacing server/queries/tenant-dashboard.ts:57''s broken .from("tenant_dashboard_versions").select("*").eq("dashboard_id", dashboardId).order("version_number", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of tenant_dashboard_versions_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): an EXISTS join back to app.tenant_dashboards requiring the same has_active_tenant_membership/actor_holds_customer_user_layer/is_supreme_admin predicate against the PARENT row''s own tenant_id.';

create function public.list_tenant_dashboard_versions(p_dashboard_id uuid)
returns setof app.tenant_dashboard_versions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_tenant_dashboard_versions(p_dashboard_id);
$wrap$;

comment on function public.list_tenant_dashboard_versions(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_tenant_dashboard_versions with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_tenant_dashboard_versions(uuid) from public;
grant execute on function app.list_tenant_dashboard_versions(uuid) to authenticated, service_role;

revoke execute on function public.list_tenant_dashboard_versions(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_tenant_dashboard_versions(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9. app.get_tenant_dashboard_version_by_id -- replaces server/queries/
--    tenant-dashboard.ts:69 (getTenantDashboardVersionById)
-- ---------------------------------------------------------------------------
create function app.get_tenant_dashboard_version_by_id(p_version_id uuid)
returns setof app.tenant_dashboard_versions
language sql
stable
as $$
  select * from app.tenant_dashboard_versions where id = p_version_id;
$$;

comment on function app.get_tenant_dashboard_version_by_id(uuid) is
  'IAE-003/O1 remediation: one dashboard version by id, replacing server/queries/tenant-dashboard.ts:69''s broken .from("tenant_dashboard_versions").select("*").eq("id", versionId).maybeSingle() (app is not exposed to PostgREST). Same security posture as app.list_tenant_dashboard_versions above. `returns setof app.tenant_dashboard_versions`, never a bare composite.';

create function public.get_tenant_dashboard_version_by_id(p_version_id uuid)
returns setof app.tenant_dashboard_versions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_tenant_dashboard_version_by_id(p_version_id);
$wrap$;

comment on function public.get_tenant_dashboard_version_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_tenant_dashboard_version_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_tenant_dashboard_version_by_id(uuid) from public;
grant execute on function app.get_tenant_dashboard_version_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_tenant_dashboard_version_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_tenant_dashboard_version_by_id(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10. app.list_dashboard_widgets -- replaces server/queries/
--     tenant-dashboard.ts:82 (listDashboardWidgets)
-- ---------------------------------------------------------------------------
create function app.list_dashboard_widgets(p_dashboard_version_id uuid)
returns setof app.tenant_dashboard_widgets
language sql
stable
as $$
  select * from app.tenant_dashboard_widgets
  where dashboard_version_id = p_dashboard_version_id
  order by display_order asc;
$$;

comment on function app.list_dashboard_widgets(uuid) is
  'IAE-003/O1 remediation: the widgets bound to one dashboard version, in display order, replacing server/queries/tenant-dashboard.ts:82''s broken .from("tenant_dashboard_widgets").select("*").eq("dashboard_version_id", dashboardVersionId).order("display_order", { ascending: true }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of tenant_dashboard_widgets_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): a TWO-LEVEL EXISTS join (tenant_dashboard_versions -> tenant_dashboards) requiring the same has_active_tenant_membership/actor_holds_customer_user_layer/is_supreme_admin predicate against the GRANDPARENT row''s own tenant_id -- reproduced live by the RLS engine, never re-implemented (no join at all appears in this function''s own SQL body).';

create function public.list_dashboard_widgets(p_dashboard_version_id uuid)
returns setof app.tenant_dashboard_widgets
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_dashboard_widgets(p_dashboard_version_id);
$wrap$;

comment on function public.list_dashboard_widgets(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_dashboard_widgets with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_dashboard_widgets(uuid) from public;
grant execute on function app.list_dashboard_widgets(uuid) to authenticated, service_role;

revoke execute on function public.list_dashboard_widgets(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_dashboard_widgets(uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/scheduled-report.ts. All 4 functions keep their exact
-- original signatures; the module's own client type (line 18) changes from
-- `Pick<SupabaseClient, "from">` to `Pick<SupabaseClient, "rpc">`.
--
--   listScheduledReports(client, tenantId):
--     client.rpc("list_scheduled_reports", { p_tenant_id: tenantId })
--   getScheduledReportById(client, scheduledReportId):
--     client.rpc("get_scheduled_report_by_id", { p_scheduled_report_id: scheduledReportId })
--     -> const row = Array.isArray(data) ? data[0] : data; return row ? parse(row) : null;
--   listScheduledReportRecipients(client, scheduledReportId):
--     client.rpc("list_scheduled_report_recipients", { p_scheduled_report_id: scheduledReportId })
--   listScheduledReportRuns(client, scheduledReportId, limit=25):
--     client.rpc("list_scheduled_report_runs", { p_scheduled_report_id: scheduledReportId, p_limit: limit })
--
-- File: server/queries/supreme-tenants.ts. listSupremeTenants(client, input)
-- keeps its exact signature; the module's own client type (currently
-- `Pick<SupabaseClient, "from">`, unnamed/inline) changes to
-- `Pick<SupabaseClient, "rpc">`. New body:
--
--   const pageSize = Math.min(Math.max(Math.trunc(input.pageSize), 1), MAX_PAGE_SIZE);
--   const page = Math.max(Math.trunc(input.page), 1);
--   const { data, error } = await client.rpc("list_supreme_tenants", { p_page: page, p_page_size: pageSize });
--   if (error) throw new SupremeTenantsQueryError(error.message);
--   const rows = (data ?? []) as Record<string, unknown>[];
--   return {
--     tenants: rows.map((row) => parseSupremeTenant(row)),
--     totalCount: rows.length > 0 ? Number(rows[0]!.total_count) : 0,
--     page,
--     pageSize,
--   };
--
-- (The function''s own clamping of pageSize/page is kept client-side too,
-- matching the original code exactly -- the new RPC clamps independently
-- server-side as defense in depth, mirroring app.list_portal_users'' own
-- established double-clamp convention.)
--
-- File: server/queries/tenant-dashboard.ts. All 5 functions keep their exact
-- original signatures; the module's own client type (line 20) changes from
-- `Pick<SupabaseClient, "from">` to `Pick<SupabaseClient, "rpc">`.
--
--   listTenantDashboards(client, tenantId):
--     client.rpc("list_tenant_dashboards", { p_tenant_id: tenantId })
--   getTenantDashboardById(client, dashboardId):
--     client.rpc("get_tenant_dashboard_by_id", { p_dashboard_id: dashboardId })
--   listTenantDashboardVersions(client, dashboardId):
--     client.rpc("list_tenant_dashboard_versions", { p_dashboard_id: dashboardId })
--   getTenantDashboardVersionById(client, versionId):
--     client.rpc("get_tenant_dashboard_version_by_id", { p_version_id: versionId })
--   listDashboardWidgets(client, dashboardVersionId):
--     client.rpc("list_dashboard_widgets", { p_dashboard_version_id: dashboardVersionId })
