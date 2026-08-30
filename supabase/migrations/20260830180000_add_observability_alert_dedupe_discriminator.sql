-- Closes ISS-2026-155 (docs/runtime/KNOWN_ISSUES.md).
--
-- WHAT WAS WRONG
--
--   `app.raise_observability_alert` deduplicates on `(tenant_id, source_type, signal_type)`.
--   `app.evaluate_workload_budget` (IAE-034) maps seven workload types onto four source types
--   before calling it:
--
--       webhooks -> webhook,  ai -> ai,  oltp -> api,  everything else -> job
--
--   So `analytics`, `reports`, `import_export` and `notifications` all arrive as `'job'`. A
--   tenant breaching its analytics budget AND its reports budget inside the dedup window opens
--   ONE incident: the second breach is filed as a `duplicate_signal` timeline event on the
--   first. Both are detected and neither is silent — but an operator reading the incident sees
--   one workload named in the title and has no way to learn the other also breached.
--
-- WHY IT WAS DEFERRED THREE TIMES, AND WHAT CHANGES HERE
--
--   Every prior look concluded the same two options and rejected both, correctly:
--     (a) widen `source_type`/`signal_type` — they are closed CHECK enums shared with seven
--         other live producers (job dead-letter, three webhook-ingestion functions,
--         webhook-delivery replay, integration health-check, AI governed-action outcome), so
--         this is shared-infra surgery on already-verified code; or
--     (b) have IAE-034 raise its own alert outside the dedup mechanism — which breaks
--         `raise_observability_alert`'s own documented "never a second parallel alerting path".
--
--   There is a third shape neither considered: leave both enums alone and give the dedup key an
--   OPTIONAL extra dimension. A nullable column, a seventh parameter defaulting to null, and one
--   caller that passes something. Every existing producer keeps byte-identical behaviour by
--   construction — they cannot pass a discriminator, so their key is unchanged — and there is
--   still exactly one alerting path.
--
--   This is the same additive-optional-parameter shape this repository already uses for
--   `p_effective_date` (20260731310000) and `p_client_ip` (20260826190000), both chosen for the
--   same reason: a default-null parameter cannot regress a caller that does not know about it.
--
-- IMPLEMENTATION NOTE
--
--   `CREATE OR REPLACE FUNCTION` cannot add a parameter, and dropping the 6-argument function
--   would mean dropping its `public.*` wrapper first and recreating both. Overloading avoids
--   that entirely: the 7-argument form carries the real body, and the 6-argument form becomes a
--   one-line delegation passing null. One implementation, two entry points, no DROP, and no
--   dependency churn on already-applied objects.
--
-- Additive only. No column, constraint, grant or policy is dropped or narrowed.

-- ===========================================================================
-- 1. The extra dedup dimension
-- ===========================================================================
-- Nullable and unconstrained on purpose: it is an opaque discriminator, not a second
-- classification to keep in sync with anything. `app.incidents` is `service_role`-only
-- (`revoke all ... from public, anon, authenticated` at 20260807400000), so adding a column
-- widens no end-user grant.
alter table app.incidents add column if not exists dedupe_discriminator text;

comment on column app.incidents.dedupe_discriminator is
  'ISS-2026-155: an optional extra dimension on the (tenant_id, source_type, signal_type) dedup key, for a producer whose own distinctions are finer than source_type can express -- IAE-034 maps seven workload types onto four source types, so analytics and reports both arrive as ''job'' and collapsed into one incident. Null for every producer that does not need it, which is all of them but one; a null discriminator dedups exactly as before.';

-- The dedup lookup filters on this column, so the partial index that serves it should carry it.
drop index if exists app.incidents_open_lookup_idx;
create index incidents_open_lookup_idx
  on app.incidents (tenant_id, source_type, signal_type, dedupe_discriminator, status)
  where status <> 'resolved';

-- ===========================================================================
-- 2. app.raise_observability_alert -- the 7-argument form carries the body
-- ===========================================================================
-- Body reproduced from the current, live-effective definition
-- (20260807400000_create_intelligence_enterprise_monitoring_observability.sql, never redefined
-- since -- grep-confirmed), with exactly three changes, all of them the discriminator:
-- it joins the advisory-lock key, it joins the existing-incident lookup, and it is stored on
-- the row. Every other line, branch and order is identical.
create function app.raise_observability_alert(
  p_tenant_id uuid,
  p_source_type text,
  p_signal_type text,
  p_title text,
  p_severity text,
  p_detail text,
  p_dedupe_discriminator text
)
returns app.incidents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_route app.alert_routes;
  v_dedupe_minutes integer;
  v_existing app.incidents;
  v_incident app.incidents;
begin
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'incident_invalid_severity: %', p_severity using errcode = 'check_violation';
  end if;

  -- The lock must be keyed on exactly what the lookup below filters on, or two callers with
  -- different discriminators would serialize against each other for no reason -- and, worse,
  -- two callers with the SAME discriminator could stop serializing, which is the check-then-act
  -- race the lock exists to close. `coalesce` keeps a null discriminator's key byte-identical
  -- to the key this function used before this migration, so an existing producer's
  -- serialization behaviour is unchanged.
  perform pg_advisory_xact_lock(hashtextextended(
    coalesce(p_tenant_id::text, 'platform') || ':' || p_source_type || ':' || p_signal_type
      || ':' || coalesce(p_dedupe_discriminator, ''), 0));

  select * into v_route from app.alert_routes
  where source_type = p_source_type and signal_type = p_signal_type
    and (tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null));
  v_dedupe_minutes := coalesce(v_route.dedupe_window_minutes, 30);

  select * into v_existing
  from app.incidents
  where (tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null))
    and source_type = p_source_type and signal_type = p_signal_type
    -- `is not distinct from` rather than `=`, so a null discriminator matches a null one. With
    -- `=` every null-discriminator producer would stop deduplicating entirely and open a fresh
    -- incident per signal -- the exact opposite of this function's purpose, and a silent
    -- regression for all seven of them.
    and dedupe_discriminator is not distinct from p_dedupe_discriminator
    and status <> 'resolved'
    and opened_at > now() - (v_dedupe_minutes || ' minutes')::interval
  order by opened_at desc
  limit 1;

  if found then
    insert into app.incident_timeline_events (incident_id, event_type, detail)
    values (v_existing.id, 'duplicate_signal', p_detail);
    return v_existing;
  end if;

  insert into app.incidents (tenant_id, source_type, signal_type, title, severity, owner_team, dedupe_discriminator)
  values (p_tenant_id, p_source_type, p_signal_type, p_title, p_severity, v_route.owner_team, p_dedupe_discriminator)
  returning * into v_incident;

  insert into app.incident_timeline_events (incident_id, event_type, detail)
  values (v_incident.id, 'opened', p_detail);

  return v_incident;
end;
$$;

comment on function app.raise_observability_alert(uuid, text, text, text, text, text, text) is
  'IAE-030, extended by ISS-2026-155: service_role-only, real deduplication -- a matching OPEN/ACKNOWLEDGED incident within the applicable alert route''s own dedupe_window_minutes absorbs a repeat signal as a duplicate_signal timeline event instead of opening a second incident for the same ongoing problem. Falls back to a 30-minute default dedupe window when no matching app.alert_routes row exists. p_dedupe_discriminator adds an OPTIONAL extra dimension to that key for a producer whose own distinctions are finer than source_type can express; null reproduces the pre-ISS-2026-155 key exactly, and every producer but IAE-034''s workload-budget path passes null.';

-- ===========================================================================
-- 3. The 6-argument form delegates -- one implementation, two entry points
-- ===========================================================================
-- Every existing caller resolves here and is unaffected by construction: it cannot supply a
-- discriminator, so its dedup key is what it always was.
create or replace function app.raise_observability_alert(
  p_tenant_id uuid,
  p_source_type text,
  p_signal_type text,
  p_title text,
  p_severity text,
  p_detail text
)
returns app.incidents
language sql
volatile
security definer
set search_path = app, pg_temp
as $$
  select app.raise_observability_alert(p_tenant_id, p_source_type, p_signal_type, p_title, p_severity, p_detail, null);
$$;

comment on function app.raise_observability_alert(uuid, text, text, text, text, text) is
  'IAE-030: the original six-argument entry point, kept so every already-applied producer (job dead-letter, the three webhook-ingestion functions, webhook-delivery replay, integration health-check, AI governed-action outcome, IP-access denial) is untouched by ISS-2026-155. Delegates to the seven-argument form with a null discriminator, which reproduces the original dedup key exactly. Not a second alerting path -- there is one implementation, above.';

-- ===========================================================================
-- 4. IAE-034 passes what it actually knows
-- ===========================================================================
-- Verbatim current body from 20260808200000_create_intelligence_scale_up_architecture.sql, with
-- one changed call: the workload type joins the dedup key. `v_source_type` is deliberately NOT
-- changed -- the coarse mapping is what routes the incident to the right owner team via
-- app.alert_routes, and re-pointing it would silently re-route every workload alert.
create or replace function app.evaluate_workload_budget(
  p_tenant_id uuid,
  p_workload_type text,
  p_observed_value numeric
)
returns app.workload_backpressure_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_budget numeric;
  v_action text;
  v_source_type text;
  v_incident app.incidents;
  v_event app.workload_backpressure_events;
begin
  if p_workload_type not in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications') then
    raise exception 'workload_invalid_type: %', p_workload_type using errcode = 'check_violation';
  end if;

  v_budget := app.resolve_workload_budget(p_tenant_id, p_workload_type);

  if v_budget is null then
    v_action := 'no_budget_configured';
  elsif p_observed_value > v_budget then
    v_action := 'backpressure_applied';
  else
    v_action := 'within_budget';
  end if;

  if v_action = 'backpressure_applied' then
    v_source_type := case p_workload_type
      when 'webhooks' then 'webhook'
      when 'ai' then 'ai'
      when 'oltp' then 'api'
      else 'job'
    end;

    v_incident := app.raise_observability_alert(
      p_tenant_id, v_source_type, 'backlog_depth',
      format('%s workload exceeded its capacity budget', p_workload_type), 'high',
      format('observed %s exceeds budget %s', p_observed_value, v_budget),
      -- ISS-2026-155: without this, analytics and reports both arrive as source_type 'job' and
      -- the second breach disappears into the first incident as a duplicate_signal.
      p_workload_type
    );
  end if;

  insert into app.workload_backpressure_events (tenant_id, workload_type, observed_value, budget_value, action_taken, alert_incident_id)
  values (p_tenant_id, p_workload_type, p_observed_value, v_budget, v_action, v_incident.id)
  returning * into v_event;

  return v_event;
end;
$$;

comment on function app.evaluate_workload_budget is
  'IAE-034: service_role-only, no actor parameter -- system-to-system telemetry evaluation, mirroring app.record_observability_signal''s own shape exactly (design decision 4). Composes app.raise_observability_alert (IAE-030) on a genuine breach, never a second parallel alerting path. ISS-2026-155 fix: passes p_workload_type as the dedup discriminator, so two different workload types breaching for the same tenant inside the dedup window open two incidents rather than collapsing into one -- v_source_type stays coarse deliberately, because that is what routes the incident to an owner team via app.alert_routes.';

-- ===========================================================================
-- 5. Grants and the public.* wrapper
-- ===========================================================================
revoke execute on function app.raise_observability_alert(uuid, text, text, text, text, text, text) from public;
grant execute on function app.raise_observability_alert(uuid, text, text, text, text, text, text) to service_role;

-- Mirrors public.raise_observability_alert's 6-argument wrapper exactly: security definer
-- (matching the app function), service_role-only, a pass-through and never a reimplementation.
-- scripts/db-tests/public-api-wrapper-regression.sql enforces both halves exhaustively.
create function public.raise_observability_alert(p_tenant_id uuid, p_source_type text, p_signal_type text, p_title text, p_severity text, p_detail text, p_dedupe_discriminator text)
returns app.incidents
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.raise_observability_alert(p_tenant_id, p_source_type, p_signal_type, p_title, p_severity, p_detail, p_dedupe_discriminator);
$wrap$;

comment on function public.raise_observability_alert(uuid, text, text, text, text, text, text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.raise_observability_alert with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.raise_observability_alert(uuid, text, text, text, text, text, text) from public;
grant execute on function public.raise_observability_alert(uuid, text, text, text, text, text, text) to service_role;
