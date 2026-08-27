-- ISS-2026-266 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- materialized views are never restored by pg_restore --data-only, silently left
-- stale/empty after the composed in-place restore procedure. Live-proved: the underlying
-- table restores correctly, but app.mv_report_usage_daily comes back empty, at whatever
-- stale snapshot the migration replay's own CREATE MATERIALIZED VIEW produced.
--
-- Already procedurally mitigated by docs/runbooks/database-restore.md's own required
-- step (h) -- but that step is a raw, manually-typed `REFRESH MATERIALIZED VIEW
-- CONCURRENTLY` per view name, which an operator must remember to run for EVERY
-- registered view individually and which bypasses this repository's own already-existing
-- governed refresh mechanism (app.refresh_analytics_view, IAE-005) entirely -- no
-- app.analytics_refresh_runs ledger row records that the post-restore refresh ever
-- happened. This entry's own text names exactly this gap as the remaining owner item:
-- "a more permanent fix (e.g. an automated post-restore refresh script rather than a
-- manual runbook step)".
--
-- Fixed: a new function that refreshes every ACTIVE registered analytics view by
-- delegating to the existing, already-tested, already-ledgered app.refresh_analytics_view
-- for each one -- never reimplementing the refresh or authority-check logic, and
-- automatically covering any future materialized view the moment it is registered (no
-- hardcoded view name, unlike the runbook's own per-view manual instruction). Authority
-- is enforced entirely by the delegated call (app.refresh_analytics_view already requires
-- Supreme Admin) -- this function performs no separate check of its own, so there is
-- exactly one place that rule can drift.
create function app.refresh_all_registered_analytics_views(p_actor_auth_user_id uuid, p_actor_label text)
returns setof app.analytics_refresh_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view_code text;
begin
  for v_view_code in
    select view_code from app.analytics_view_registry where status = 'active' order by view_code
  loop
    return next app.refresh_analytics_view(v_view_code, p_actor_auth_user_id, p_actor_label);
  end loop;
  return;
end;
$$;

comment on function app.refresh_all_registered_analytics_views is 'ISS-2026-266: run this once, after any restore procedure completes, to refresh every ACTIVE registered materialized view in one governed call -- replaces having to remember and manually REFRESH each view by name. Delegates entirely to app.refresh_analytics_view (Supreme Admin only) for each view, so every refresh is still recorded in app.analytics_refresh_runs exactly as if run individually. A view added to the registry after this function is deployed is covered automatically -- no code change needed.';

revoke execute on all functions in schema app from public;
grant execute on function app.refresh_all_registered_analytics_views(uuid, text) to authenticated, service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
create function public.refresh_all_registered_analytics_views(p_actor_auth_user_id uuid, p_actor_label text)
returns setof app.analytics_refresh_runs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.refresh_all_registered_analytics_views(p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.refresh_all_registered_analytics_views(p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.refresh_all_registered_analytics_views with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.refresh_all_registered_analytics_views(p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.refresh_all_registered_analytics_views(p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
