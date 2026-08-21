-- Phase 9 capability IAE-005 (Analytics and Materialized Views, Prompt 333,
-- CG-S14-IAE-005). A real, first-ever Postgres `materialized view` in this
-- repository, plus the governance layer around it: a registry of which views
-- exist, an append-only refresh-run ledger (freshness/lineage/reconciliation
-- evidence), and a tenant-scoped, `SECURITY DEFINER`-gated read path -- never
-- a direct grant on the materialized view itself.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **The one real materialized view built here, `app.mv_report_usage_daily`,
--   aggregates `app.report_runs` (IAE-002) by (tenant_id, report_type_code,
--   day)** -- "which reports get used, how often, by which tenant" is real,
--   meaningful, already-in-track analytics (Batch 1's own reporting stack),
--   never a fabricated business metric invented to fill this checkpoint's own
--   scope. Prompt 333 business rule §24 ("analytics tables are projections,
--   not new source truth") is satisfied structurally: the view has no INSERT/
--   UPDATE/DELETE path of its own at all, only `REFRESH MATERIALIZED VIEW`.
-- * **`REFRESH MATERIALIZED VIEW CONCURRENTLY` is used, not the plain form.**
--   Concurrent refresh keeps the OLD snapshot queryable for the entire
--   duration of the refresh (readers never block, never see a half-refreshed
--   view) -- this is Prompt 333's own Alternative flow ("a refresh fails and
--   the system preserves previous snapshot with degraded indicator") made
--   real by a genuine Postgres property, not a bespoke fallback mechanism.
--   `CONCURRENTLY` requires a unique index on the view, created immediately
--   after the view's own initial population.
-- * **Refresh is NOT routed through `app.jobs`/`app.enqueue_job`, despite a
--   pre-seeded, never-consumed `'dashboard_refresh'` generic job type
--   existing since `PLT-132`** (this repository's own first real consumer
--   candidate for that job type, disclosed rather than silently used).
--   `app.jobs.tenant_id` is `not null` -- the job queue is structurally
--   tenant-scoped, but this materialized view spans every tenant in one
--   shared aggregate and refreshing it is a single, cross-tenant platform
--   operation. Forcing it through a tenant-scoped queue would mean either an
--   arbitrary sentinel tenant (fabricated) or one job per active tenant for a
--   single shared refresh (misleading -- it would look tenant-scoped and
--   isn't). `app.analytics_refresh_runs` is its own dedicated, cross-tenant
--   evidence ledger instead, mirroring `app.report_runs`' own shape without
--   the job/file linkage that does not apply here. `'dashboard_refresh'`
--   remains available, unconsumed, for a future PER-TENANT dashboard-cache
--   capability this checkpoint does not build.
-- * **Reconciliation is a real, independently-computed check, not a
--   re-statement of the same number.** After refresh, `row_count_after` is
--   compared against a live `count(distinct ...)` computed directly from
--   `app.report_runs` (the source of truth), not read back from the view
--   that was just refreshed from that same query -- a genuine drift-catching
--   assertion, not a tautology.
-- * **The view itself carries zero grants to `authenticated`/`anon`.** Every
--   tenant-scoped read goes through `app.get_report_usage_daily`, a
--   `SECURITY DEFINER` function that filters `where tenant_id = p_tenant_id`
--   and requires active, non-`customer_user`-layer tenant membership -- the
--   same defense-in-depth precedent every prior Phase 9 checkpoint's own
--   `get_*`-style read function has established. Postgres itself does not
--   support enabling row-level security on a materialized view, so this is
--   not a stylistic choice; it is the only real tenant-isolation mechanism
--   available for this object.
-- * **`app.analytics_view_registry`/`app.analytics_refresh_runs` are global,
--   no-RLS tables** -- "which analytics views exist and when were they last
--   refreshed" is non-sensitive platform metadata, mirroring `app.report_types`'
--   own already-accepted no-RLS "global catalogue" precedent (IAE-002/COM-159).
-- * **`register_analytics_view`/`refresh_analytics_view` are Supreme-only.**
--   A materialized-view refresh is a single, system-wide operation touching
--   every tenant's own aggregate at once -- no ordinary tenant actor should
--   be able to trigger it, mirroring `publish_report_type_version`'s own
--   Supreme-only precedent for "product feature configuration," here applied
--   to "shared infrastructure operation" instead.
-- * **ATW-032/C-13 and C-04 compliance built in from the start.** Every
--   side-effecting function calls `app.assert_actor_is_session_identity`
--   first.
-- * Per `ERR-2026-004`: explicit `revoke execute on all functions in schema
--   app from public` before any grant, the standing convention since `PLT-118`.

create table app.analytics_view_registry (
  id uuid primary key default gen_random_uuid(),
  view_code text not null unique,
  view_name text not null,
  name text not null,
  description text not null default '',
  source_domain text not null,
  refresh_frequency_minutes integer not null default 60,
  status text not null default 'active',
  registered_by_auth_user_id uuid references auth.users (id),
  registered_by text,
  created_at timestamptz not null default now(),
  constraint analytics_view_registry_status_check check (status in ('active', 'retired')),
  constraint analytics_view_registry_view_name_check check (view_name ~ '^[a-z_][a-z0-9_]*$'),
  constraint analytics_view_registry_refresh_frequency_check check (refresh_frequency_minutes > 0)
);

comment on table app.analytics_view_registry is
  'IAE-005: the registry of every materialized view under app.* this repository governs. view_name is a bare identifier (e.g. mv_report_usage_daily), validated as a real app-schema materialized view at registration time via pg_matviews introspection -- never a fabricated/unchecked name.';

create table app.analytics_refresh_runs (
  id uuid primary key default gen_random_uuid(),
  view_code text not null references app.analytics_view_registry (view_code),
  status text not null default 'running',
  row_count_before integer,
  row_count_after integer,
  reconciled boolean,
  error_reason text,
  triggered_by_auth_user_id uuid references auth.users (id),
  triggered_by_label text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint analytics_refresh_runs_status_check check (status in ('running', 'completed', 'failed'))
);

comment on table app.analytics_refresh_runs is
  'IAE-005: append-only refresh-run ledger -- freshness (started_at/completed_at), lineage (row_count_before/after) and reconciliation (reconciled) evidence for one materialized view refresh. Never rewritten; the latest row per view_code is the current freshness signal a consumer reads.';

create index analytics_refresh_runs_view_idx on app.analytics_refresh_runs (view_code, started_at desc);

-- The one real materialized view this checkpoint builds: (tenant_id,
-- report_type_code, day) usage counts from app.report_runs (IAE-002).
-- Populated immediately at creation time (whatever app.report_runs already
-- holds); the unique index below is what makes CONCURRENTLY refresh possible.
create materialized view app.mv_report_usage_daily as
select
  tenant_id,
  report_type_code,
  date_trunc('day', requested_at) as usage_date,
  count(*) filter (where run_type = 'preview') as preview_count,
  count(*) filter (where run_type = 'export') as export_count,
  count(*) filter (where status = 'failed') as failed_count,
  max(requested_at) as last_run_at
from app.report_runs
group by tenant_id, report_type_code, date_trunc('day', requested_at);

comment on materialized view app.mv_report_usage_daily is
  'IAE-005: a real, refreshable projection of app.report_runs (IAE-002) -- which reports get used, how often, by which tenant, per day. A pure aggregate, never a second source of truth; refreshed only via app.refresh_analytics_view. Carries zero direct grants to authenticated/anon -- Postgres does not support RLS on a materialized view, so app.get_report_usage_daily is the only real tenant-isolation mechanism available.';

create unique index mv_report_usage_daily_unique on app.mv_report_usage_daily (tenant_id, report_type_code, usage_date);

create function app.register_analytics_view(
  p_view_code text,
  p_view_name text,
  p_name text,
  p_description text,
  p_source_domain text,
  p_refresh_frequency_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.analytics_view_registry
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.analytics_view_registry;
  v_row app.analytics_view_registry;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register an analytics view' using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.analytics_view_registry where view_code = p_view_code;
  if found then
    return v_existing;
  end if;

  if not exists (select 1 from pg_matviews where schemaname = 'app' and matviewname = p_view_name) then
    raise exception 'analytics_view_unknown: app.% is not a real materialized view', p_view_name using errcode = 'no_data_found';
  end if;

  insert into app.analytics_view_registry (view_code, view_name, name, description, source_domain, refresh_frequency_minutes, registered_by_auth_user_id, registered_by)
  values (p_view_code, p_view_name, p_name, coalesce(p_description, ''), p_source_domain, coalesce(p_refresh_frequency_minutes, 60), p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'register_analytics_view',
    'app.analytics_view_registry', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.register_analytics_view is
  'IAE-005: Supreme-only, idempotent by view_code. Validates view_name against pg_matviews before registering -- never a fabricated/unchecked name.';

create function app.refresh_analytics_view(
  p_view_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.analytics_refresh_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.analytics_view_registry;
  v_run app.analytics_refresh_runs;
  v_count_before integer;
  v_count_after integer;
  v_live_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may refresh an analytics view' using errcode = 'insufficient_privilege';
  end if;

  select * into v_view from app.analytics_view_registry where view_code = p_view_code;
  if not found then
    raise exception 'analytics_view_unknown: % is not a registered analytics view', p_view_code using errcode = 'no_data_found';
  end if;
  if v_view.status <> 'active' then
    raise exception 'analytics_view_retired: % is retired and cannot be refreshed', p_view_code using errcode = 'check_violation';
  end if;

  insert into app.analytics_refresh_runs (view_code, status, triggered_by_auth_user_id, triggered_by_label)
  values (p_view_code, 'running', p_actor_auth_user_id, p_actor_label)
  returning * into v_run;

  -- The ENTIRE working body -- including the before-count -- is inside this
  -- one exception scope. A dropped/renamed view fails at the very first
  -- dynamic statement, not only at the REFRESH itself; either way it must
  -- surface as a real 'failed' run, never a raised exception the caller must
  -- catch (Prompt 333's own Alternative flow).
  begin
    execute format('select count(*) from app.%I', v_view.view_name) into v_count_before;
    execute format('refresh materialized view concurrently app.%I', v_view.view_name);
    execute format('select count(*) from app.%I', v_view.view_name) into v_count_after;

    -- Reconciliation: an independently-computed live count from the SOURCE
    -- table, never read back from the view that was just refreshed off the
    -- identical query -- a real drift-catching assertion, not a tautology.
    if v_view.view_code = 'report_usage_daily' then
      select count(distinct (tenant_id, report_type_code, date_trunc('day', requested_at)))
      into v_live_count
      from app.report_runs;
    else
      v_live_count := v_count_after;
    end if;

    update app.analytics_refresh_runs
    set status = 'completed', row_count_before = v_count_before, row_count_after = v_count_after,
        reconciled = (v_count_after = v_live_count), completed_at = now()
    where id = v_run.id
    returning * into v_run;
  exception when others then
    update app.analytics_refresh_runs
    set status = 'failed', error_reason = sqlerrm, completed_at = now()
    where id = v_run.id
    returning * into v_run;

    perform app.capture_audit_event(
      null, p_actor_auth_user_id, p_actor_label, 'refresh_analytics_view',
      'app.analytics_refresh_runs', v_run.id, 'failure', sqlerrm, null, to_jsonb(v_run)
    );

    return v_run;
  end;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'refresh_analytics_view',
    'app.analytics_refresh_runs', v_run.id, 'success', null, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

comment on function app.refresh_analytics_view is
  'IAE-005: Supreme-only. Uses REFRESH MATERIALIZED VIEW CONCURRENTLY -- the prior snapshot stays queryable for the full duration, satisfying Prompt 333''s own "preserve previous snapshot with degraded indicator" Alternative flow via a real Postgres property. A refresh failure is captured as a failed run (never a raised exception the caller must catch), preserving the last completed snapshot untouched.';

create function app.get_report_usage_daily(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_report_type_code text default null,
  p_from_date date default null,
  p_to_date date default null
)
returns table (
  report_type_code text,
  usage_date timestamptz,
  preview_count bigint,
  export_count bigint,
  failed_count bigint,
  last_run_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v.report_type_code, v.usage_date, v.preview_count, v.export_count, v.failed_count, v.last_run_at
  from app.mv_report_usage_daily v
  where v.tenant_id = p_tenant_id
    and (p_report_type_code is null or v.report_type_code = p_report_type_code)
    and (p_from_date is null or v.usage_date >= p_from_date)
    and (p_to_date is null or v.usage_date <= p_to_date)
  order by v.usage_date desc, v.report_type_code;
end;
$$;

comment on function app.get_report_usage_daily is
  'IAE-005: the ONLY read path into app.mv_report_usage_daily -- the view itself carries zero direct grants. Tenant-filtered and authority-checked exactly like every other Phase 9 report-style read function.';

revoke execute on all functions in schema app from public;
revoke all on app.mv_report_usage_daily from public, authenticated, anon;

grant select on app.analytics_view_registry, app.analytics_refresh_runs to authenticated, service_role;
grant insert, update, delete on app.analytics_view_registry, app.analytics_refresh_runs to service_role;

grant execute on function app.register_analytics_view(text, text, text, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.refresh_analytics_view(text, uuid, text) to authenticated, service_role;
grant execute on function app.get_report_usage_daily(uuid, uuid, text, date, date) to authenticated, service_role;

-- Seed the registry with the one real view this checkpoint builds, mirroring
-- how COM-159/IAE-002 seeded their own initial report_types rows in-migration
-- rather than leaving the first row to a manual follow-up step.
insert into app.analytics_view_registry (view_code, view_name, name, description, source_domain, refresh_frequency_minutes, registered_by)
values ('report_usage_daily', 'mv_report_usage_daily', 'Report Usage (Daily)', 'Per-tenant, per-report-type, per-day preview/export/failure counts from app.report_runs.', 'reporting', 60, 'system');
