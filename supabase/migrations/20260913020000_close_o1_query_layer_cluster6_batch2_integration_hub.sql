-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 6
-- (platform-intelligence-reports) batch 2 of N.
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table in server/queries/*.ts has NEVER worked in production. Closes 5
-- broken `.from()` call sites across 2 files:
--
--   server/queries/integration-hub.ts:29              listIntegrationAdapters
--   server/queries/integration-hub.ts:38              listIntegrationConnections
--   server/queries/integration-hub.ts:47              getIntegrationConnectionById
--   server/queries/integration-hub.ts:60              listIntegrationHealthChecks
--   server/queries/third-party-provider-adapter.ts:35 getThirdPartyProviderConnection
--
-- 5 new app.*/public.* Option-2 wrapper pairs (10 functions), ALL SECURITY
-- INVOKER with ZERO actor parameter -- every real call site of all 5 TS
-- functions (app/(tenant)/[tenantSlug]/admin/integrations/page.tsx,
-- app/(tenant)/[tenantSlug]/integrations/page.tsx,
-- app/(tenant)/[tenantSlug]/integrations/[connectionId]/page.tsx) uses
-- `createSupabaseServerClient()` only; getThirdPartyProviderConnection has
-- zero real production callers today (only a unit test), same treatment
-- applied regardless per this series' own established convention.
--
-- ===========================================================================
-- SECURITY POSTURE -- three grant/RLS shapes
-- ===========================================================================
--
-- SHAPE 1 (no RLS, full-row grant): app.integration_adapters
-- (20260803020000_create_intelligence_integration_hub.sql:101-... ; `relrowsecurity`
-- never enabled anywhere in supabase/migrations, confirmed by repo-wide grep).
-- `grant select on app.integration_adapters to authenticated, service_role`
-- (same file, line 615) never revoked or narrowed. `select *` is safe.
--
-- SHAPE 2 (RLS-scoped, tenant-membership predicate, full-row grant):
-- app.integration_connections/app.integration_health_checks. RULE B, fresh
-- grep of both `create policy` and any later `alter policy` (bare policy
-- name, sorted by filename) -- exactly ONE hit each, no later alter:
--   integration_connections_select_scoped (same file, line 591-595):
--     using (app.has_active_tenant_membership(tenant_id, (select auth.uid()))
--            and not app.actor_holds_customer_user_layer(tenant_id, (select auth.uid())));
--   integration_health_checks_select_scoped (same file, line 598-607): an
--   EXISTS join back to app.integration_connections requiring the same
--   two-conjunct predicate against the PARENT row's own tenant_id.
-- Deliberately NO explicit `OR is_supreme_admin()` disjunct at the policy
-- level for either -- same shape and same non-gap as cluster 6 batch 1's own
-- app.automation_rules/app.automation_rule_versions/app.automation_rule_
-- executions: app.has_active_tenant_membership's own current body already
-- admits a Supreme Admin internally (re-verified live in this batch's own
-- db-test, not merely cited from batch 1). Both tables carry a full-row grant
-- to `authenticated` (20260803020000:616-617, never narrowed) -- `select *`
-- is safe for both.
--
-- SHAPE 3 (RLS-scoped, tenant-membership predicate WITH explicit supreme-admin
-- disjunct, COLUMN-restricted grant): app.third_party_provider_connections.
-- RULE B: current text (only 2 hits -- the original `create policy` at
-- 20260729380000_create_advanced_tms_third_party_provider_adapter.sql:534-536
-- and the later `alter policy` at 20260730560000_harden_customer_user_layer_
-- default_deny.sql:328-329, which is current) is `(has_active_tenant_
-- membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id))
-- OR is_supreme_admin()`.
-- Column grant: `authenticated`'s SELECT was narrowed from table-wide to an
-- explicit 14-column list at 20260730350000_harden_advanced_tms_third_party_
-- hybrid_tracking.sql:166-170 (Finding 1 CRITICAL, excluding the then-current
-- `webhook_secret_value`) -- confirmed as still current via a full repo-wide
-- grep of every grant/revoke statement mentioning this table (no later
-- statement touches its SELECT grant at all).
-- RULE C (a live schema-evolution wrinkle this table's own later history
-- introduces, independently traced rather than assumed from the recon's own
-- 14-column citation): `webhook_secret_value` was later DROPPED entirely --
-- `alter table app.third_party_provider_connections drop column
-- webhook_secret_value` at 20260826050000_harden_integration_secrets_
-- encryption_at_rest.sql:116, which ALSO added a brand-new
-- `webhook_secret_value_encrypted bytea` column (same file, line 114) that
-- appears nowhere in any grant statement -- authenticated therefore has ZERO
-- grant on it either. The table's CURRENT effective visible column order
-- (dropped `webhook_secret_value` skipped, `auto_disabled_at`/
-- `disabled_reason` added by 20260730110000, `webhook_secret_value_encrypted`
-- added last) is: id, tenant_id, provider_code, integration_mode, poll_cursor,
-- status, consecutive_failure_count, last_successful_ingest_at,
-- record_version, created_by, created_at, updated_at, auto_disabled_at,
-- disabled_reason, webhook_secret_value_encrypted -- 15 columns, of which
-- `authenticated` holds a grant on only the first 14 (the CURRENT
-- 20260730350000 list, itself never touching the not-yet-existing 15th at the
-- time it was written). The new function below selects all 15 positions (to
-- structurally satisfy `returns setof <table>`, which matches its query's
-- output columns to the type's CURRENT full column count/order), explicitly
-- casting `webhook_secret_value_encrypted` to null -- mirroring this whole
-- series' own established null-cast idiom for a column the calling role holds
-- no grant on (app.get_latest_analytics_refresh_run, app.get_latest_
-- automation_rule_publish_approval_request). The TS contract
-- (ThirdPartyProviderConnectionSchema) never declared this field to begin
-- with, so the extra null key is simply ignored by Zod's own default
-- unknown-key-stripping `.parse()` behavior -- no contract change needed.

-- ---------------------------------------------------------------------------
-- 1. app.list_integration_adapters -- replaces server/queries/
--    integration-hub.ts:29 (listIntegrationAdapters)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("integration_adapters").select("*").order("name", { ascending: true })`.
create function app.list_integration_adapters()
returns setof app.integration_adapters
language sql
stable
as $$
  select * from app.integration_adapters order by name asc;
$$;

comment on function app.list_integration_adapters() is
  'IAE-008/O1 remediation: the full, code-shipped integration-adapter catalog ("marketplace" listing), name ascending, replacing server/queries/integration-hub.ts:29''s broken .from("integration_adapters").select("*").order("name", { ascending: true }) (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- this table carries no RLS at all and a plain, never-narrowed grant select ... to authenticated, service_role. Deliberately security invoker (the unmarked default), matching this codebase''s own established shape for a zero-actor-param, no-RLS global reference table.';

create function public.list_integration_adapters()
returns setof app.integration_adapters
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_integration_adapters();
$wrap$;

comment on function public.list_integration_adapters() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_integration_adapters with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_integration_adapters() from public;
grant execute on function app.list_integration_adapters() to authenticated, service_role;

revoke execute on function public.list_integration_adapters() from anon, authenticated, service_role, public;
grant execute on function public.list_integration_adapters() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.list_integration_connections -- replaces server/queries/
--    integration-hub.ts:38 (listIntegrationConnections)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("integration_connections").select("*").eq("tenant_id",
-- tenantId).order("updated_at", { ascending: false })`.
create function app.list_integration_connections(p_tenant_id uuid)
returns setof app.integration_connections
language sql
stable
as $$
  select * from app.integration_connections
  where tenant_id = p_tenant_id
  order by updated_at desc;
$$;

comment on function app.list_integration_connections(uuid) is
  'IAE-008/O1 remediation: every integration connection for one tenant, most recently updated first, replacing server/queries/integration-hub.ts:38''s broken .from("integration_connections").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies entirely on the calling role''s own live RLS evaluation of integration_connections_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY, no later alter): `has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)` -- no separate is_supreme_admin() disjunct at the policy level, but has_active_tenant_membership''s own current body already admits a Supreme Admin internally (verified live in this batch''s own db-test). app.integration_connection_credentials is deliberately never touched by this function, mirroring server/queries/integration-hub.ts''s own module-header disclosure exactly -- that table has zero authenticated/anon grant and zero RLS policy by design.';

create function public.list_integration_connections(p_tenant_id uuid)
returns setof app.integration_connections
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_integration_connections(p_tenant_id);
$wrap$;

comment on function public.list_integration_connections(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_integration_connections with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_integration_connections(uuid) from public;
grant execute on function app.list_integration_connections(uuid) to authenticated, service_role;

revoke execute on function public.list_integration_connections(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_integration_connections(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.get_integration_connection_by_id -- replaces server/queries/
--    integration-hub.ts:47 (getIntegrationConnectionById)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("integration_connections").select("*").eq("id", connectionId).maybeSingle()`.
create function app.get_integration_connection_by_id(p_connection_id uuid)
returns setof app.integration_connections
language sql
stable
as $$
  select * from app.integration_connections where id = p_connection_id;
$$;

comment on function app.get_integration_connection_by_id(uuid) is
  'IAE-008/O1 remediation: one integration connection by id, replacing server/queries/integration-hub.ts:47''s broken .from("integration_connections").select("*").eq("id", connectionId).maybeSingle() (app is not exposed to PostgREST). Same security posture as app.list_integration_connections above (invoker, zero actor param, same RLS predicate, keyed by id instead of tenant_id). `returns setof app.integration_connections`, never a bare composite -- the standing defect-class check -- so a nonexistent id or an RLS-hidden row both return a GENUINELY EMPTY result, matching the original .maybeSingle() -> null contract exactly.';

create function public.get_integration_connection_by_id(p_connection_id uuid)
returns setof app.integration_connections
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_integration_connection_by_id(p_connection_id);
$wrap$;

comment on function public.get_integration_connection_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_integration_connection_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_integration_connection_by_id(uuid) from public;
grant execute on function app.get_integration_connection_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_integration_connection_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_integration_connection_by_id(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.list_integration_health_checks -- replaces server/queries/
--    integration-hub.ts:60 (listIntegrationHealthChecks)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("integration_health_checks").select("*")
-- .eq("connection_id", connectionId).order("checked_at", { ascending: false }).limit(limit)`.
create function app.list_integration_health_checks(p_connection_id uuid, p_limit integer default 25)
returns setof app.integration_health_checks
language sql
stable
as $$
  select * from app.integration_health_checks
  where connection_id = p_connection_id
  order by checked_at desc
  limit greatest(coalesce(p_limit, 25), 0);
$$;

comment on function app.list_integration_health_checks(uuid, integer) is
  'IAE-008/O1 remediation: health-check history for one connection, newest first, replacing server/queries/integration-hub.ts:60''s broken .from("integration_health_checks").select("*").eq("connection_id", connectionId).order("checked_at", { ascending: false }).limit(limit) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of integration_health_checks_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): an EXISTS join back to app.integration_connections requiring the same has_active_tenant_membership/actor_holds_customer_user_layer predicate against the PARENT row''s own tenant_id -- reproduced live by the RLS engine, never re-implemented in this function''s own SQL body. p_limit passed straight through, matching the original call''s own caller-supplied, unclamped limit.';

create function public.list_integration_health_checks(p_connection_id uuid, p_limit integer default 25)
returns setof app.integration_health_checks
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_integration_health_checks(p_connection_id, p_limit);
$wrap$;

comment on function public.list_integration_health_checks(uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_integration_health_checks with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_integration_health_checks(uuid, integer) from public;
grant execute on function app.list_integration_health_checks(uuid, integer) to authenticated, service_role;

revoke execute on function public.list_integration_health_checks(uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_integration_health_checks(uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.get_third_party_provider_connection -- replaces server/queries/
--    third-party-provider-adapter.ts:35 (getThirdPartyProviderConnection)
-- ---------------------------------------------------------------------------
-- Replaces: an explicit 14-column select on app.third_party_provider_connections
-- filtered by tenant_id/provider_code, via maybeSingle(). See this migration's
-- own SHAPE 3 section above for the full column-restriction/schema-evolution
-- rationale (webhook_secret_value_encrypted cast to null, never selected).
create function app.get_third_party_provider_connection(p_tenant_id uuid, p_provider_code text)
returns setof app.third_party_provider_connections
language sql
stable
as $$
  select id, tenant_id, provider_code, integration_mode, poll_cursor, status,
    consecutive_failure_count, last_successful_ingest_at, record_version, created_by,
    created_at, updated_at, auto_disabled_at, disabled_reason, null::bytea as webhook_secret_value_encrypted
  from app.third_party_provider_connections
  where tenant_id = p_tenant_id and provider_code = p_provider_code;
$$;

comment on function app.get_third_party_provider_connection(uuid, text) is
  'ATW-226E/O1 remediation: one tenant''s own connection to one provider_code, or a genuinely empty result if never registered, replacing server/queries/third-party-provider-adapter.ts:35''s broken 14-column .from("third_party_provider_connections") read (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of third_party_provider_connections_select_scoped, CURRENT text (RULE B): `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()`. `webhook_secret_value_encrypted` is explicitly cast to null (never selected) -- authenticated''s own grant on this table has never covered it (added after the table''s own column-restriction migration, confirmed via a full grant/revoke history grep); a bare `select *` would fail with permission denied under this function''s deliberate SECURITY INVOKER mode, and the original `webhook_secret_value` column it once excluded no longer exists at all (dropped, encrypted-at-rest replacement added). `returns setof app.third_party_provider_connections`, never a bare composite. server/queries/third-party-provider-adapter.ts:29''s own getThirdPartyProviderConnection has zero real production callers today (only a unit test) -- this wrapper is added regardless, per this series'' own explicit closure scope.';

create function public.get_third_party_provider_connection(p_tenant_id uuid, p_provider_code text)
returns setof app.third_party_provider_connections
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_third_party_provider_connection(p_tenant_id, p_provider_code);
$wrap$;

comment on function public.get_third_party_provider_connection(uuid, text) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_third_party_provider_connection with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_third_party_provider_connection(uuid, text) from public;
grant execute on function app.get_third_party_provider_connection(uuid, text) to authenticated, service_role;

revoke execute on function public.get_third_party_provider_connection(uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.get_third_party_provider_connection(uuid, text) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/integration-hub.ts.
--
-- 1) listIntegrationAdapters(client) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_integration_adapters");
--      if (error) throw new IntegrationHubQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationAdapter(row));
--
-- 2) listIntegrationConnections(client, tenantId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_integration_connections", { p_tenant_id: tenantId });
--      if (error) throw new IntegrationHubQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationConnection(row));
--
-- 3) getIntegrationConnectionById(client, connectionId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("get_integration_connection_by_id", { p_connection_id: connectionId });
--      if (error) throw new IntegrationHubQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseIntegrationConnection(row as Record<string, unknown>);
--
-- 4) listIntegrationHealthChecks(client, connectionId, limit=25) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_integration_health_checks", { p_connection_id: connectionId, p_limit: limit });
--      if (error) throw new IntegrationHubQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationHealthCheck(row));
--
--    IntegrationHubQueryClient (line 18) changes from `Pick<SupabaseClient, "from">`
--    to `Pick<SupabaseClient, "rpc">` -- every function in this file converts here.
--
-- File: server/queries/third-party-provider-adapter.ts.
--
-- 5) getThirdPartyProviderConnection(client, tenantId, providerCode) -- signature
--    unchanged. New body:
--      const { data, error } = await client.rpc("get_third_party_provider_connection", { p_tenant_id: tenantId, p_provider_code: providerCode });
--      if (error) throw new ThirdPartyProviderAdapterQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      return row ? parseThirdPartyProviderConnection(row as Record<string, unknown>) : null;
--
--    ThirdPartyProviderAdapterQueryClient (line 19) already carries "rpc" alongside
--    "from" -- narrows from `Pick<SupabaseClient, "from" | "rpc">` to
--    `Pick<SupabaseClient, "rpc">` -- this was the file''s only "from" usage
--    (listThirdPartyTelemetryReports already used "rpc" exclusively).
