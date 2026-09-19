-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 6
-- (platform-intelligence-reports) batch 1 of N.
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table in server/queries/*.ts has NEVER worked in production. Closes 9
-- broken `.from()` call sites across 2 files:
--
--   server/queries/analytics.ts:31         listAnalyticsViews
--   server/queries/analytics.ts:41         getLatestAnalyticsRefreshRun
--   server/queries/analytics.ts:59         listAnalyticsRefreshRuns
--   server/queries/automation-rule.ts:29   listAutomationRules
--   server/queries/automation-rule.ts:38   getAutomationRuleById
--   server/queries/automation-rule.ts:50   listAutomationRuleVersions
--   server/queries/automation-rule.ts:60   listAutomationRuleExecutions
--   server/queries/automation-rule.ts:96   getLatestAutomationRulePublishApprovalRequest
--   server/queries/automation-rule.ts:116  listApprovalRequestSteps
--
-- 9 new app.*/public.* Option-2 wrapper pairs (18 functions), ALL SECURITY
-- INVOKER with ZERO actor parameter -- every real call site of all 9 TS
-- functions (`app/(tenant)/[tenantSlug]/analytics/page.tsx`,
-- `app/(tenant)/[tenantSlug]/automation-rules/page.tsx`,
-- `app/(tenant)/[tenantSlug]/automation-rules/[ruleId]/page.tsx`) uses
-- `createSupabaseServerClient()` only -- never `createSupabaseServiceRoleClient()`
-- to claim a decoupled actor -- this series' own decisive INVOKER-vs-DEFINER
-- test.
--
-- ===========================================================================
-- SECURITY POSTURE -- three distinct grant/RLS shapes, none of them can be
-- satisfied by a bare `select *`
-- ===========================================================================
--
-- SHAPE 1 (no RLS at all, full-row grant): app.analytics_view_registry
-- (`create table` at 20260802040000_create_intelligence_analytics_materialized_
-- views.sql:72; `relrowsecurity` never enabled anywhere in supabase/migrations,
-- confirmed by repo-wide grep). `grant select on app.analytics_view_registry ...
-- to authenticated, service_role` (same file, line 314) was never revoked or
-- narrowed (confirmed: `grep -rn "revoke.*analytics_view_registry"
-- supabase/migrations/*.sql` -- zero hits). `select *` is safe here.
--
-- SHAPE 2 (no RLS, COLUMN-restricted grant -- a live, adversarially-caught
-- correction of the recon manifest's own stale claim): app.analytics_
-- refresh_runs. The recon manifest that scoped this batch claimed
-- "ZERO grant to authenticated" for this table, citing only the ORIGINAL
-- migration's own full-row grant; that claim is stale. A LATER migration,
-- `20260827030000_harden_analytics_refresh_runs_grant.sql` (ISS-2026-174, Track
-- B Batch 1), revoked the full-row grant and re-granted a NARROWER column list:
--   revoke select on app.analytics_refresh_runs from authenticated;
--   grant select (id, view_code, status, row_count_after, reconciled,
--     error_reason, started_at, completed_at) on app.analytics_refresh_runs
--     to authenticated;
-- (confirmed as the current, only-ever grant on this table for `authenticated`
-- via `grep -rn "grant select.*analytics_refresh_runs\|revoke select.*
-- analytics_refresh_runs" supabase/migrations/*.sql` -- exactly these two
-- statements, in this order). `row_count_before`/`triggered_by_auth_user_id`/
-- `triggered_by_label` were dropped from the grant (a platform-wide-visible
-- admin-identity leak, per that migration's own disclosed rationale) -- but
-- `AnalyticsRefreshRunSchema` (server/contracts/analytics/analytics.ts) still
-- declares all 3 as required-but-nullable fields. Both new functions below
-- therefore select EXACTLY the 8 granted columns (never `select *`, which
-- would fail with `permission denied for table analytics_refresh_runs` under
-- SECURITY INVOKER for the real `authenticated` role), and the TS integration
-- below synthesizes the 3 missing fields as explicit `null` before parsing --
-- the exact same pattern this file's sibling call site
-- (getLatestAutomationRulePublishApprovalRequest, SHAPE 3 below) already
-- established for `ended_reason`. Confirmed zero UI regression: a repo-wide
-- grep of `triggeredByLabel`/`triggeredByAuthUserId`/`rowCountBefore` across
-- `app/**/*.tsx` returns zero hits -- these 3 fields were never rendered
-- anywhere, matching the harden migration's own "row_count_before (unused,
-- redundant)" and "an admin's real identity, previously exposed platform-wide"
-- language exactly. This call path has therefore been DOUBLY broken in
-- production until this migration: unexposed schema AND (had the schema ever
-- been exposed) a column-privilege denial on a bare `select *`.
--
-- SHAPE 3 (RLS-scoped, tenant-membership predicate; app.approval_requests
-- additionally COLUMN-restricted): app.automation_rules/app.automation_rule_
-- versions/app.automation_rule_executions/app.approval_requests/app.approval_
-- request_steps. RULE B (RLS predicate currency), independently re-derived via
-- a fresh grep of both `create policy` and any later `alter policy` (bare
-- policy name, sorted by filename):
--   automation_rules_select_scoped (20260803010000_create_intelligence_
--   automation_rule_engine.sql:1068-1073, the ONLY hit -- no later alter):
--     using (app.has_active_tenant_membership(tenant_id, (select auth.uid()))
--            and not app.actor_holds_customer_user_layer(tenant_id, (select auth.uid())));
--   automation_rule_versions_select_scoped (same file, 1075-1082, the ONLY
--   hit): an EXISTS join back to app.automation_rules, same two-conjunct
--   predicate evaluated against the parent row's own tenant_id.
--   automation_rule_executions_select_scoped (same file, 1086-1090, the ONLY
--   hit): identical two-conjunct predicate, direct on this table's own
--   tenant_id column (no join needed).
--   Deliberately NO explicit `OR is_supreme_admin()` disjunct at the policy
--   level for any of these 3 -- unlike several sibling tables closed earlier
--   in this series. This is NOT a functional gap: `app.has_active_tenant_
--   membership`'s own CURRENT body (re-confirmed via `grep -n "create or
--   replace function app.has_active_tenant_membership"
--   supabase/migrations/*.sql`, most recent hit
--   20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64-81) already
--   returns true via its own internal `or app.is_supreme_admin(p_auth_user_id)
--   or app.has_active_support_grant(...)` branch -- so a Supreme Admin with
--   zero explicit tenant membership row still passes these 3 policies. The 3
--   new functions below call `app.has_active_tenant_membership(...)` itself
--   (never re-implementing its internal logic inline), so this bypass carries
--   through automatically -- verified live in this pass's own db-test, not
--   merely asserted.
--   approval_requests_select_scoped (`app.get_latest_automation_rule_publish_
--   approval_request`'s own table): current text (RULE B re-confirmed, same
--   grep discipline this whole series uses) is `(app.has_active_tenant_
--   membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id))
--   OR app.is_supreme_admin()` -- this one DOES carry the explicit disjunct at
--   the policy level (20260730560000_harden_customer_user_layer_default_
--   deny.sql:81-82 is the current, final text). Also COLUMN-restricted:
--   `ended_reason` was revoked from `authenticated`'s grant at
--   20260731210000_harden_ticketing_escalation_linked_records_hris_batch_291_
--   293_review_fixes.sql:693-697 (Finding 5 CRITICAL) and never re-granted
--   (confirmed: that revoke/grant pair is the only ever grant-shaping
--   statement on this table). The new function selects the SAME explicit
--   15-column list server/queries/automation-rule.ts:97-99's own TS code
--   already uses (id, tenant_id, config_version_id, entity_type, entity_id,
--   pattern, status, idempotency_key, requested_by_auth_user_id, requested_by,
--   started_at, ended_at, record_version, created_at, updated_at) -- never
--   `select *`, which would fail identically to SHAPE 2 above.
--   approval_request_steps_select_scoped: current text (RULE B, only 2 hits --
--   the original `create policy` at 20260719090000_create_approval_engine.sql:
--   883-887 and the later `alter policy` at 20260730560000_harden_customer_
--   user_layer_default_deny.sql:82-83, which is the current, final version) is
--   an EXISTS join to app.approval_requests requiring `(has_active_tenant_
--   membership(r.tenant_id) AND NOT actor_holds_customer_user_layer(r.tenant_id))
--   OR is_supreme_admin()`. This table's own grant to `authenticated` is a
--   full-row grant, all 11 columns (confirmed via information_schema.column_
--   privileges parity with the table's own column count) -- `select *` is
--   safe here.
--
-- Every 0-or-1-row lookup (`app.get_latest_analytics_refresh_run`,
-- `app.get_automation_rule_by_id`, `app.get_latest_automation_rule_publish_
-- approval_request`) is declared `returns setof app.<table>`, never a bare
-- composite -- the standing defect-class check this series has run on every
-- batch since it first surfaced.
--
-- RULE A does not apply to any of the 9 functions in this batch: none takes an
-- actor parameter (every authority check is left to the calling role's own
-- live RLS evaluation, or -- for the 2 no-RLS tables -- there is no per-row
-- authority to check at all), so there is no identity claim for
-- `app.assert_actor_is_session_identity` to cross-check.

-- ---------------------------------------------------------------------------
-- 1. app.list_analytics_view_registry -- replaces server/queries/analytics.ts:31
--    (listAnalyticsViews)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("analytics_view_registry").select("*").order("view_code", { ascending: true })`.
create function app.list_analytics_view_registry()
returns setof app.analytics_view_registry
language sql
stable
as $$
  select * from app.analytics_view_registry order by view_code asc;
$$;

comment on function app.list_analytics_view_registry() is
  'IAE-005/O1 remediation: the full, code-shipped analytics-view registry, view_code ascending, replacing server/queries/analytics.ts:31''s broken .from("analytics_view_registry").select("*").order("view_code", { ascending: true }) (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- this table carries no RLS at all (never enabled) and a plain, never-narrowed `grant select ... to authenticated, service_role`. Deliberately `security invoker` (the unmarked default), matching this codebase''s own established shape for a zero-actor-param, no-RLS global reference table (app.list_active_procurement_metric_definitions, app.list_milestone_codes).';

create function public.list_analytics_view_registry()
returns setof app.analytics_view_registry
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_analytics_view_registry();
$wrap$;

comment on function public.list_analytics_view_registry() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_analytics_view_registry with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_analytics_view_registry() from public;
grant execute on function app.list_analytics_view_registry() to authenticated, service_role;

revoke execute on function public.list_analytics_view_registry() from anon, authenticated, service_role, public;
grant execute on function public.list_analytics_view_registry() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.get_latest_analytics_refresh_run -- replaces server/queries/
--    analytics.ts:41 (getLatestAnalyticsRefreshRun)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("analytics_refresh_runs").select("*").eq("view_code",
-- viewCode).order("started_at", { ascending: false }).limit(1).maybeSingle()`.
-- Explicit 8-column select -- see this migration's own SHAPE 2 section above
-- for why `select *` is unsafe here.
create function app.get_latest_analytics_refresh_run(p_view_code text)
returns setof app.analytics_refresh_runs
language sql
stable
as $$
  select id, view_code, status, null::integer as row_count_before, row_count_after,
    reconciled, error_reason, null::uuid as triggered_by_auth_user_id, null::text as triggered_by_label,
    started_at, completed_at
  from app.analytics_refresh_runs
  where view_code = p_view_code
  order by started_at desc
  limit 1;
$$;

comment on function app.get_latest_analytics_refresh_run(text) is
  'IAE-005/O1 remediation: the most recent refresh run for one analytics view, or a genuinely empty result if it has never been refreshed, replacing server/queries/analytics.ts:41''s broken .from("analytics_refresh_runs").select("*").eq("view_code", viewCode).order("started_at", { ascending: false }).limit(1).maybeSingle() (app is not exposed to PostgREST). Zero parameters beyond p_view_code, zero in-function authority check -- this table carries no RLS at all, but (ISS-2026-174, 20260827030000) authenticated''s own grant is COLUMN-restricted to (id, view_code, status, row_count_after, reconciled, error_reason, started_at, completed_at); row_count_before/triggered_by_auth_user_id/triggered_by_label are explicitly cast to null in this function''s own SELECT list rather than read (a bare `select *` would fail with permission denied for the real authenticated role under this function''s deliberate SECURITY INVOKER mode). Confirmed zero UI regression: none of the 3 nulled columns is rendered anywhere in app/**/*.tsx. `returns setof app.analytics_refresh_runs`, never a bare composite, so a view with no refresh history yet returns a genuinely empty result (count=0), never one row of all-NULL columns.';

create function public.get_latest_analytics_refresh_run(p_view_code text)
returns setof app.analytics_refresh_runs
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_latest_analytics_refresh_run(p_view_code);
$wrap$;

comment on function public.get_latest_analytics_refresh_run(text) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_latest_analytics_refresh_run with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_latest_analytics_refresh_run(text) from public;
grant execute on function app.get_latest_analytics_refresh_run(text) to authenticated, service_role;

revoke execute on function public.get_latest_analytics_refresh_run(text) from anon, authenticated, service_role, public;
grant execute on function public.get_latest_analytics_refresh_run(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_analytics_refresh_runs -- replaces server/queries/analytics.ts:59
--    (listAnalyticsRefreshRuns)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("analytics_refresh_runs").select("*").eq("view_code",
-- viewCode).order("started_at", { ascending: false }).limit(limit)`.
create function app.list_analytics_refresh_runs(p_view_code text, p_limit integer default 25)
returns setof app.analytics_refresh_runs
language sql
stable
as $$
  select id, view_code, status, null::integer as row_count_before, row_count_after,
    reconciled, error_reason, null::uuid as triggered_by_auth_user_id, null::text as triggered_by_label,
    started_at, completed_at
  from app.analytics_refresh_runs
  where view_code = p_view_code
  order by started_at desc
  limit greatest(coalesce(p_limit, 25), 0);
$$;

comment on function app.list_analytics_refresh_runs(text, integer) is
  'IAE-005/O1 remediation: the full refresh-run history for one analytics view, newest first, replacing server/queries/analytics.ts:59''s broken .from("analytics_refresh_runs").select("*").eq("view_code", viewCode).order("started_at", { ascending: false }).limit(limit) (app is not exposed to PostgREST). Same column-restriction rationale as app.get_latest_analytics_refresh_run above (row_count_before/triggered_by_auth_user_id/triggered_by_label explicitly nulled, never selected). p_limit is passed straight through (`limit greatest(coalesce(p_limit, 25), 0)`, matching the original call''s own caller-supplied, unclamped limit exactly -- no new server-side cap added, since the original TS default is already 25 and no caller passes an unbounded value today).';

create function public.list_analytics_refresh_runs(p_view_code text, p_limit integer default 25)
returns setof app.analytics_refresh_runs
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_analytics_refresh_runs(p_view_code, p_limit);
$wrap$;

comment on function public.list_analytics_refresh_runs(text, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_analytics_refresh_runs with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_analytics_refresh_runs(text, integer) from public;
grant execute on function app.list_analytics_refresh_runs(text, integer) to authenticated, service_role;

revoke execute on function public.list_analytics_refresh_runs(text, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_analytics_refresh_runs(text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.list_automation_rules -- replaces server/queries/automation-rule.ts:29
--    (listAutomationRules)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("automation_rules").select("*").eq("tenant_id",
-- tenantId).order("updated_at", { ascending: false })`.
create function app.list_automation_rules(p_tenant_id uuid)
returns setof app.automation_rules
language sql
stable
as $$
  select * from app.automation_rules
  where tenant_id = p_tenant_id
  order by updated_at desc;
$$;

comment on function app.list_automation_rules(uuid) is
  'IAE-007/O1 remediation: every automation rule for one tenant, most recently updated first, replacing server/queries/automation-rule.ts:29''s broken .from("automation_rules").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies entirely on the calling role''s own live RLS evaluation of automation_rules_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY, no later alter): `has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)` -- no separate is_supreme_admin() disjunct at the policy level, but has_active_tenant_membership''s own current body already admits a Supreme Admin internally (see this migration''s own header). `returns setof app.automation_rules`, matching the original call''s own unbounded-list, no-single-row-shortcut TS signature (Promise<AutomationRule[]>).';

create function public.list_automation_rules(p_tenant_id uuid)
returns setof app.automation_rules
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_automation_rules(p_tenant_id);
$wrap$;

comment on function public.list_automation_rules(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_automation_rules with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_automation_rules(uuid) from public;
grant execute on function app.list_automation_rules(uuid) to authenticated, service_role;

revoke execute on function public.list_automation_rules(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_automation_rules(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.get_automation_rule_by_id -- replaces server/queries/
--    automation-rule.ts:38 (getAutomationRuleById)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("automation_rules").select("*").eq("id", ruleId).maybeSingle()`.
create function app.get_automation_rule_by_id(p_rule_id uuid)
returns setof app.automation_rules
language sql
stable
as $$
  select * from app.automation_rules where id = p_rule_id;
$$;

comment on function app.get_automation_rule_by_id(uuid) is
  'IAE-007/O1 remediation: one automation rule by id, replacing server/queries/automation-rule.ts:38''s broken .from("automation_rules").select("*").eq("id", ruleId).maybeSingle() (app is not exposed to PostgREST). Same security posture as app.list_automation_rules above (invoker, zero actor param, same RLS predicate, keyed by id instead of tenant_id -- tenant scoping is implicit via the row''s own tenant_id, not a caller-supplied filter, exactly matching the original .from() call''s own shape). `returns setof app.automation_rules`, never a bare composite -- the standing defect-class check -- so a nonexistent id or an RLS-hidden row both return a GENUINELY EMPTY result, matching the original .maybeSingle() -> null contract exactly.';

create function public.get_automation_rule_by_id(p_rule_id uuid)
returns setof app.automation_rules
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_automation_rule_by_id(p_rule_id);
$wrap$;

comment on function public.get_automation_rule_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_automation_rule_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_automation_rule_by_id(uuid) from public;
grant execute on function app.get_automation_rule_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_automation_rule_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_automation_rule_by_id(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. app.list_automation_rule_versions -- replaces server/queries/
--    automation-rule.ts:50 (listAutomationRuleVersions)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("automation_rule_versions").select("*")
-- .eq("automation_rule_id", ruleId).order("version_number", { ascending: false })`.
create function app.list_automation_rule_versions(p_automation_rule_id uuid)
returns setof app.automation_rule_versions
language sql
stable
as $$
  select * from app.automation_rule_versions
  where automation_rule_id = p_automation_rule_id
  order by version_number desc;
$$;

comment on function app.list_automation_rule_versions(uuid) is
  'IAE-007/O1 remediation: every version of one automation rule, newest first (the currently-open draft is version_number = max), replacing server/queries/automation-rule.ts:50''s broken .from("automation_rule_versions").select("*").eq("automation_rule_id", ruleId).order("version_number", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of automation_rule_versions_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): an EXISTS join back to app.automation_rules requiring the same has_active_tenant_membership/actor_holds_customer_user_layer predicate against the PARENT row''s own tenant_id -- reproduced live by the RLS engine, never re-implemented in this function''s own SQL body (no join written here at all).';

create function public.list_automation_rule_versions(p_automation_rule_id uuid)
returns setof app.automation_rule_versions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_automation_rule_versions(p_automation_rule_id);
$wrap$;

comment on function public.list_automation_rule_versions(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_automation_rule_versions with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_automation_rule_versions(uuid) from public;
grant execute on function app.list_automation_rule_versions(uuid) to authenticated, service_role;

revoke execute on function public.list_automation_rule_versions(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_automation_rule_versions(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. app.list_automation_rule_executions -- replaces server/queries/
--    automation-rule.ts:60 (listAutomationRuleExecutions)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("automation_rule_executions").select("*")
-- .eq("automation_rule_id", ruleId).order("executed_at", { ascending: false }).limit(limit)`.
create function app.list_automation_rule_executions(p_automation_rule_id uuid, p_limit integer default 25)
returns setof app.automation_rule_executions
language sql
stable
as $$
  select * from app.automation_rule_executions
  where automation_rule_id = p_automation_rule_id
  order by executed_at desc
  limit greatest(coalesce(p_limit, 25), 0);
$$;

comment on function app.list_automation_rule_executions(uuid, integer) is
  'IAE-007/O1 remediation: execution history (completed/suppressed/failed) for one automation rule, newest first, replacing server/queries/automation-rule.ts:60''s broken .from("automation_rule_executions").select("*").eq("automation_rule_id", ruleId).order("executed_at", { ascending: false }).limit(limit) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of automation_rule_executions_select_scoped, CURRENT text (RULE B, only ever one CREATE POLICY): a direct `has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)` on this table''s own tenant_id column (no join needed -- this table stores tenant_id directly, unlike automation_rule_versions above). p_limit passed straight through, matching the original call''s own caller-supplied, unclamped limit.';

create function public.list_automation_rule_executions(p_automation_rule_id uuid, p_limit integer default 25)
returns setof app.automation_rule_executions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_automation_rule_executions(p_automation_rule_id, p_limit);
$wrap$;

comment on function public.list_automation_rule_executions(uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_automation_rule_executions with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_automation_rule_executions(uuid, integer) from public;
grant execute on function app.list_automation_rule_executions(uuid, integer) to authenticated, service_role;

revoke execute on function public.list_automation_rule_executions(uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_automation_rule_executions(uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. app.get_latest_automation_rule_publish_approval_request -- replaces
--    server/queries/automation-rule.ts:96
--    (getLatestAutomationRulePublishApprovalRequest)
-- ---------------------------------------------------------------------------
-- Replaces: an explicit 15-column select on app.approval_requests filtered by
-- entity_type='automation_rule_version' and entity_id=automationRuleVersionId,
-- ordered by started_at desc, limit 1, via maybeSingle(). See this migration's
-- own SHAPE 3 section above for the column-restriction rationale (ended_reason
-- excluded, never selected).
create function app.get_latest_automation_rule_publish_approval_request(p_automation_rule_version_id uuid)
returns setof app.approval_requests
language sql
stable
as $$
  select id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key,
    requested_by_auth_user_id, requested_by, started_at, ended_at, null::text as ended_reason,
    record_version, created_at, updated_at
  from app.approval_requests
  where entity_type = 'automation_rule_version' and entity_id = p_automation_rule_version_id
  order by started_at desc
  limit 1;
$$;

comment on function app.get_latest_automation_rule_publish_approval_request(uuid) is
  'IAE-007/O1 remediation: the most recent app.approval_requests row opened for one specific automation_rule_version, or a genuinely empty result if this exact draft has never had a publish approval requested, replacing server/queries/automation-rule.ts:96''s broken 15-column .from("approval_requests") read (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of approval_requests_select_scoped, CURRENT text (RULE B): `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()` -- this table''s RLS DOES carry the explicit supreme-admin disjunct at the policy level, unlike automation_rules/automation_rule_versions/automation_rule_executions above. `ended_reason` is explicitly cast to null (never selected) -- authenticated''s own grant on this table has excluded it since 20260731210000 (Finding 5 CRITICAL, a free-text cancellation/rejection narrative readable by any active tenant member with zero permission); a bare `select *` would fail with permission denied under this function''s deliberate SECURITY INVOKER mode. `returns setof app.approval_requests`, never a bare composite.';

create function public.get_latest_automation_rule_publish_approval_request(p_automation_rule_version_id uuid)
returns setof app.approval_requests
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_latest_automation_rule_publish_approval_request(p_automation_rule_version_id);
$wrap$;

comment on function public.get_latest_automation_rule_publish_approval_request(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_latest_automation_rule_publish_approval_request with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_latest_automation_rule_publish_approval_request(uuid) from public;
grant execute on function app.get_latest_automation_rule_publish_approval_request(uuid) to authenticated, service_role;

revoke execute on function public.get_latest_automation_rule_publish_approval_request(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_latest_automation_rule_publish_approval_request(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9. app.list_approval_request_steps -- replaces server/queries/
--    automation-rule.ts:116 (listApprovalRequestSteps)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("approval_request_steps").select("*").eq("request_id",
-- requestId).order("step_order", { ascending: true })`.
create function app.list_approval_request_steps(p_request_id uuid)
returns setof app.approval_request_steps
language sql
stable
as $$
  select * from app.approval_request_steps
  where request_id = p_request_id
  order by step_order asc;
$$;

comment on function app.list_approval_request_steps(uuid) is
  'IAE-007/O1 remediation: every step of one approval request, in order, replacing server/queries/automation-rule.ts:116''s broken .from("approval_request_steps").select("*").eq("request_id", requestId).order("step_order", { ascending: true }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of approval_request_steps_select_scoped, CURRENT text (RULE B: 2 hits total, the original CREATE POLICY at 20260719090000_create_approval_engine.sql:883 and the later ALTER POLICY at 20260730560000_harden_customer_user_layer_default_deny.sql:82, which is current): an EXISTS join to app.approval_requests requiring `(has_active_tenant_membership(r.tenant_id) AND NOT actor_holds_customer_user_layer(r.tenant_id)) OR is_supreme_admin()`. This table''s own grant to authenticated is full-row (all 11 columns, confirmed via information_schema.column_privileges parity with the table''s own column count) -- `select *` is safe here, unlike app.approval_requests itself.';

create function public.list_approval_request_steps(p_request_id uuid)
returns setof app.approval_request_steps
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_approval_request_steps(p_request_id);
$wrap$;

comment on function public.list_approval_request_steps(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_approval_request_steps with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_approval_request_steps(uuid) from public;
grant execute on function app.list_approval_request_steps(uuid) to authenticated, service_role;

revoke execute on function public.list_approval_request_steps(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_approval_request_steps(uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/analytics.ts.
--
-- 1) listAnalyticsViews(client) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_analytics_view_registry");
--      if (error) throw new AnalyticsQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseAnalyticsViewRegistry(row));
--
-- 2) getLatestAnalyticsRefreshRun(client, viewCode) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("get_latest_analytics_refresh_run", { p_view_code: viewCode });
--      if (error) throw new AnalyticsQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseAnalyticsRefreshRun(row as Record<string, unknown>);
--    (The function''s own SQL already nulls row_count_before/triggered_by_auth_user_id/
--    triggered_by_label -- no client-side synthesis needed, unlike
--    getLatestAutomationRulePublishApprovalRequest below, since the DB-side cast
--    already produces those keys with a null value.)
--
-- 3) listAnalyticsRefreshRuns(client, viewCode, limit=25) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_analytics_refresh_runs", { p_view_code: viewCode, p_limit: limit });
--      if (error) throw new AnalyticsQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseAnalyticsRefreshRun(row));
--
--    AnalyticsQueryClient (line 20) narrows from `Pick<SupabaseClient, "from" | "rpc">`
--    to `Pick<SupabaseClient, "rpc">` -- these 3 were the file''s only "from" usages.
--
-- File: server/queries/automation-rule.ts.
--
-- 4) listAutomationRules(client, tenantId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_automation_rules", { p_tenant_id: tenantId });
--      if (error) throw new AutomationRuleQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseAutomationRule(row));
--
-- 5) getAutomationRuleById(client, ruleId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("get_automation_rule_by_id", { p_rule_id: ruleId });
--      if (error) throw new AutomationRuleQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseAutomationRule(row as Record<string, unknown>);
--
-- 6) listAutomationRuleVersions(client, ruleId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_automation_rule_versions", { p_automation_rule_id: ruleId });
--      if (error) throw new AutomationRuleQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseAutomationRuleVersion(row));
--
-- 7) listAutomationRuleExecutions(client, ruleId, limit=25) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_automation_rule_executions", { p_automation_rule_id: ruleId, p_limit: limit });
--      if (error) throw new AutomationRuleQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseAutomationRuleExecution(row));
--
-- 8) getLatestAutomationRulePublishApprovalRequest(client, automationRuleVersionId)
--    -- signature unchanged. New body:
--      const { data, error } = await client.rpc("get_latest_automation_rule_publish_approval_request", { p_automation_rule_version_id: automationRuleVersionId });
--      if (error) throw new AutomationRuleQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseApprovalRequest(row as Record<string, unknown>);
--    (ended_reason is already nulled by the function''s own SQL, so the
--    `{ ...(data as Record<string, unknown>), ended_reason: null }` spread this
--    call site used against `.from()` is no longer needed -- the RPC row
--    already carries the key.)
--
-- 9) listApprovalRequestSteps(client, requestId) -- signature unchanged. New body:
--      const { data, error } = await client.rpc("list_approval_request_steps", { p_request_id: requestId });
--      if (error) throw new AutomationRuleQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseApprovalRequestStep(row));
--
--    AutomationRuleQueryClient (line 18) changes from `Pick<SupabaseClient, "from">`
--    to `Pick<SupabaseClient, "rpc">` -- every function in this file converts here,
--    leaving no "from" usage at all.
