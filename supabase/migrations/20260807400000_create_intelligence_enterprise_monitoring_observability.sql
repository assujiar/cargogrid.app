-- IAE-030 (Prompt 358, Group 7): Enterprise Monitoring and Observability.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Genuinely greenfield -- confirmed by direct grep before writing any code
--    (no `slo`/`observability`/`incident`/`alert_route` table or function
--    exists anywhere). No external APM/metrics vendor (Datadog/Prometheus/
--    etc.) is integrated anywhere in this repository, and none is added
--    here -- this checkpoint builds the real, internal governance/evidence
--    layer (SLO definitions, a real signal ledger, real incident/alert
--    records with deduplication and a timeline) that a future external
--    exporter would read from or write into, the same "structural
--    foundation now, external wiring later, disclosed" posture `IAE-019`'s
--    own AI governance boundary and `IAE-029`'s own audit-export queue
--    composition both already established.
-- 2. New `MON` entitlement module (`View`/`Edit`/`Configure`) -- Prompt 358's
--    own workstream is "Reliability", distinct from 354-357's "Enterprise
--    IAM"/"Enterprise Security" workstreams (`IAM`/`SEC`), so a new module is
--    the correct fit, not a forced reuse.
-- 3. `app.observability_signals` stores ONLY a numeric metric value plus an
--    opaque source_type/source_reference string -- never a raw payload --
--    so "telemetry redacts secrets and personal/financial data" (Prompt 358
--    §24) is a structural property of the schema itself, not a redaction
--    function bolted on afterward.
-- 4. Real deduplication, not merely disclosed: `app.raise_observability_alert`
--    checks for an existing OPEN incident matching the same (tenant_id,
--    source_type, signal_type) within the matching app.alert_routes' own
--    dedupe_window_minutes; a match appends a timeline event instead of
--    opening a second incident for the same ongoing problem.
-- 5. Real, structural tenant isolation: every tenant-scoped incident/signal
--    carries a real tenant_id; a NULL tenant_id (a platform-wide, cross-
--    tenant incident, e.g. a shared queue backing up) is Supreme-Admin-only
--    visible, mirroring the "supreme sees everything, no other layer sees
--    across tenants" discipline already established everywhere else in this
--    repository.
-- 6. `app.compute_job_queue_backlog` reads the REAL `app.jobs` table directly
--    -- "critical queue/job backpressure visible before data loss" (Prompt
--    358 §24) backed by real, live data, not a synthetic placeholder metric.
-- 7. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 8. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. MON entitlement module.
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('MON', 'Enterprise monitoring and observability: SLOs, signals, incidents, alert routing', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('View', 'MON', 'standard', false),
  ('Edit', 'MON', 'standard', false),
  ('Configure', 'MON', 'admin', false);

-- ===========================================================================
-- 2. app.slo_definitions -- real, persisted SLO targets.
-- ===========================================================================

create table app.slo_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  service_name text not null,
  metric_type text not null,
  target_value numeric not null,
  evaluation_window_minutes integer not null default 60,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint slo_definitions_metric_type_check check (metric_type in ('availability', 'latency_p95', 'error_rate', 'queue_backlog')),
  constraint slo_definitions_window_check check (evaluation_window_minutes between 1 and 10080),
  constraint slo_definitions_unique unique nulls not distinct (tenant_id, service_name, metric_type)
);

comment on table app.slo_definitions is
  'IAE-030: tenant_id null means a platform-wide SLO (e.g. the shared background-job queue); non-null means a per-tenant SLO. RPD-030 (SLA) itself is the signed customer contract -- this table is the internal evidence source that SUPPORTS it, never overrides it (Prompt 358 §24), a distinction preserved by never claiming this data IS the SLA.';

create function app.touch_slo_definition_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger slo_definitions_touch_row
  before update on app.slo_definitions
  for each row
  execute function app.touch_slo_definition_row();

create function app.set_slo_definition(
  p_tenant_id uuid,
  p_service_name text,
  p_metric_type text,
  p_target_value numeric,
  p_evaluation_window_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.slo_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_definition app.slo_definitions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'Configure');
    v_authorized := v_decision.allowed;
  end if;

  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to configure this SLO (tenant %)', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_metric_type not in ('availability', 'latency_p95', 'error_rate', 'queue_backlog') then
    raise exception 'slo_invalid_metric_type: %', p_metric_type using errcode = 'check_violation';
  end if;
  if p_evaluation_window_minutes not between 1 and 10080 then
    raise exception 'slo_invalid_window: % must be between 1 and 10080 minutes', p_evaluation_window_minutes using errcode = 'check_violation';
  end if;

  insert into app.slo_definitions (tenant_id, service_name, metric_type, target_value, evaluation_window_minutes, created_by)
  values (p_tenant_id, p_service_name, p_metric_type, p_target_value, p_evaluation_window_minutes, p_actor_label)
  on conflict (tenant_id, service_name, metric_type) do update
    set target_value = excluded.target_value, evaluation_window_minutes = excluded.evaluation_window_minutes
  returning * into v_definition;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_slo_definition',
    'app.slo_definitions', v_definition.id, 'success', null, null, to_jsonb(v_definition)
  );

  return v_definition;
end;
$$;

-- ===========================================================================
-- 3. app.observability_signals -- append-only, numeric-only, no raw payload
-- (design decision 3).
-- ===========================================================================

create table app.observability_signals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  source_type text not null,
  source_reference text,
  signal_type text not null,
  value numeric not null,
  occurred_at timestamptz not null default now(),
  constraint observability_signals_source_type_check check (source_type in ('job', 'webhook', 'api', 'integration', 'ai')),
  constraint observability_signals_signal_type_check check (signal_type in ('error', 'latency_ms', 'backlog_depth', 'success'))
);

create index observability_signals_tenant_lookup_idx on app.observability_signals (tenant_id, source_type, signal_type, occurred_at desc);

create function app.record_observability_signal(
  p_tenant_id uuid,
  p_source_type text,
  p_source_reference text,
  p_signal_type text,
  p_value numeric
)
returns app.observability_signals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_signal app.observability_signals;
begin
  if p_source_type not in ('job', 'webhook', 'api', 'integration', 'ai') then
    raise exception 'observability_signal_invalid_source_type: %', p_source_type using errcode = 'check_violation';
  end if;
  if p_signal_type not in ('error', 'latency_ms', 'backlog_depth', 'success') then
    raise exception 'observability_signal_invalid_signal_type: %', p_signal_type using errcode = 'check_violation';
  end if;

  insert into app.observability_signals (tenant_id, source_type, source_reference, signal_type, value)
  values (p_tenant_id, p_source_type, p_source_reference, p_signal_type, p_value)
  returning * into v_signal;

  return v_signal;
end;
$$;

comment on function app.record_observability_signal is
  'IAE-030: service_role-only -- a real ingestion point for job/webhook/api/integration/ai error and latency signals (Prompt 358 §20). No actor/authority parameter by design: this is a system-to-system telemetry write, mirroring app.capture_audit_event''s own "trusts its caller" shape, never a live end-user action.';

create function app.compute_job_queue_backlog(p_job_type text, p_older_than_minutes integer, p_actor_auth_user_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_backlog integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to read the platform-wide job queue backlog', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*)::integer into v_backlog
  from app.jobs
  where job_type = p_job_type
    and status = 'pending'
    and created_at < now() - (greatest(coalesce(p_older_than_minutes, 5), 0) || ' minutes')::interval;

  return v_backlog;
end;
$$;

comment on function app.compute_job_queue_backlog is
  'IAE-030: real backpressure visibility (Prompt 358 §24 "critical queue/job backpressure visible before data loss") -- queries the live app.jobs table directly, never a synthetic/cached metric. app.jobs is not tenant-scoped in this reading (a job_type''s backlog spans every tenant''s own queued work), so this is a genuinely platform-wide metric -- Supreme-Admin-only, mirroring this same migration''s own tenant_id-null SLO/incident/alert-route convention, rather than the unauthenticated read this originally shipped with (caught by this checkpoint''s own ATW-032/ISS-2026-033 authority-surface sweep before ever being committed).';

-- ===========================================================================
-- 4. app.alert_routes / app.incidents / app.incident_timeline_events --
-- real, deduplicated, owner-routed alerting (design decision 4).
-- ===========================================================================

create table app.alert_routes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  source_type text not null,
  signal_type text not null,
  owner_team text,
  owner_email text,
  dedupe_window_minutes integer not null default 30,
  created_by text,
  created_at timestamptz not null default now(),
  constraint alert_routes_source_type_check check (source_type in ('job', 'webhook', 'api', 'integration', 'ai')),
  constraint alert_routes_signal_type_check check (signal_type in ('error', 'latency_ms', 'backlog_depth', 'success')),
  constraint alert_routes_dedupe_window_check check (dedupe_window_minutes between 1 and 1440),
  constraint alert_routes_unique unique nulls not distinct (tenant_id, source_type, signal_type)
);

create function app.set_alert_route(
  p_tenant_id uuid,
  p_source_type text,
  p_signal_type text,
  p_owner_team text,
  p_owner_email text,
  p_dedupe_window_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.alert_routes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_route app.alert_routes;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'Configure');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to configure this alert route (tenant %)', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_dedupe_window_minutes not between 1 and 1440 then
    raise exception 'alert_route_invalid_dedupe_window: % must be between 1 and 1440 minutes', p_dedupe_window_minutes using errcode = 'check_violation';
  end if;

  insert into app.alert_routes (tenant_id, source_type, signal_type, owner_team, owner_email, dedupe_window_minutes, created_by)
  values (p_tenant_id, p_source_type, p_signal_type, p_owner_team, p_owner_email, coalesce(p_dedupe_window_minutes, 30), p_actor_label)
  on conflict (tenant_id, source_type, signal_type) do update
    set owner_team = excluded.owner_team, owner_email = excluded.owner_email, dedupe_window_minutes = excluded.dedupe_window_minutes
  returning * into v_route;

  return v_route;
end;
$$;

create table app.incidents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  source_type text not null,
  signal_type text not null,
  title text not null,
  severity text not null default 'medium',
  status text not null default 'open',
  owner_team text,
  opened_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by text,
  resolved_at timestamptz,
  resolved_by text,
  resolution_note text,
  constraint incidents_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint incidents_status_check check (status in ('open', 'acknowledged', 'resolved'))
);

create index incidents_open_lookup_idx on app.incidents (tenant_id, source_type, signal_type, status) where status <> 'resolved';
create index incidents_tenant_id_idx on app.incidents (tenant_id, opened_at desc);

create table app.incident_timeline_events (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references app.incidents (id),
  event_type text not null,
  detail text,
  occurred_at timestamptz not null default now(),
  constraint incident_timeline_events_event_type_check check (event_type in ('opened', 'duplicate_signal', 'acknowledged', 'resolved'))
);

create index incident_timeline_events_incident_id_idx on app.incident_timeline_events (incident_id, occurred_at asc);

create function app.raise_observability_alert(
  p_tenant_id uuid,
  p_source_type text,
  p_signal_type text,
  p_title text,
  p_severity text,
  p_detail text
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

  -- Tier C review fix (correctness/concurrency lens): the dedup check below
  -- (SELECT an existing open incident, INSERT a new one if none found) is a
  -- classic check-then-act race with no unique constraint backing it --
  -- live-reproduced as 2 concurrent signals for the same (tenant, source_
  -- type, signal_type) both creating their own incident instead of exactly
  -- 1. A transaction-scoped advisory lock keyed on that same triple
  -- serializes concurrent callers for the SAME dedup key (never blocks
  -- callers with a different key), so the second caller's own SELECT always
  -- observes the first caller's already-committed... already-inserted
  -- incident before deciding whether to insert its own.
  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_tenant_id::text, 'platform') || ':' || p_source_type || ':' || p_signal_type, 0));

  select * into v_route from app.alert_routes
  where source_type = p_source_type and signal_type = p_signal_type
    and (tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null));
  v_dedupe_minutes := coalesce(v_route.dedupe_window_minutes, 30);

  select * into v_existing
  from app.incidents
  where (tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null))
    and source_type = p_source_type and signal_type = p_signal_type
    and status <> 'resolved'
    and opened_at > now() - (v_dedupe_minutes || ' minutes')::interval
  order by opened_at desc
  limit 1;

  if found then
    insert into app.incident_timeline_events (incident_id, event_type, detail)
    values (v_existing.id, 'duplicate_signal', p_detail);
    return v_existing;
  end if;

  insert into app.incidents (tenant_id, source_type, signal_type, title, severity, owner_team)
  values (p_tenant_id, p_source_type, p_signal_type, p_title, p_severity, v_route.owner_team)
  returning * into v_incident;

  insert into app.incident_timeline_events (incident_id, event_type, detail)
  values (v_incident.id, 'opened', p_detail);

  return v_incident;
end;
$$;

comment on function app.raise_observability_alert is
  'IAE-030: service_role-only, real deduplication (design decision 4) -- a matching OPEN/ACKNOWLEDGED incident within the applicable alert route''s own dedupe_window_minutes absorbs a repeat signal as a duplicate_signal timeline event instead of opening a second incident for the same ongoing problem. Falls back to a 30-minute default dedupe window when no matching app.alert_routes row exists.';

create function app.acknowledge_incident(
  p_incident_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.incidents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_incident app.incidents;
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_incident from app.incidents where id = p_incident_id and status = 'open' for update;
  if not found then
    raise exception 'incident_not_open: % is not an open incident', p_incident_id using errcode = 'no_data_found';
  end if;

  if v_incident.tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_incident.tenant_id, 'MON', 'Edit');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to acknowledge this incident', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.incidents
  set status = 'acknowledged', acknowledged_at = now(), acknowledged_by = p_actor_label
  where id = p_incident_id
  returning * into v_incident;

  insert into app.incident_timeline_events (incident_id, event_type, detail)
  values (p_incident_id, 'acknowledged', p_actor_label);

  return v_incident;
end;
$$;

create function app.resolve_incident(
  p_incident_id uuid,
  p_resolution_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.incidents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_incident app.incidents;
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_incident from app.incidents where id = p_incident_id and status in ('open', 'acknowledged') for update;
  if not found then
    raise exception 'incident_not_open: % is not an open/acknowledged incident', p_incident_id using errcode = 'no_data_found';
  end if;

  if v_incident.tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_incident.tenant_id, 'MON', 'Edit');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to resolve this incident', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.incidents
  set status = 'resolved', resolved_at = now(), resolved_by = p_actor_label, resolution_note = p_resolution_note
  where id = p_incident_id
  returning * into v_incident;

  insert into app.incident_timeline_events (incident_id, event_type, detail)
  values (p_incident_id, 'resolved', p_resolution_note);

  return v_incident;
end;
$$;

-- ===========================================================================
-- 5. Read paths.
-- ===========================================================================

create function app.list_incidents_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.incidents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'View');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to view these incidents', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.incidents
    where tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null)
    order by opened_at desc;
end;
$$;

create function app.get_incident_timeline(p_incident_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_timeline_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_incident app.incidents;
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_incident from app.incidents where id = p_incident_id;
  if not found then
    raise exception 'incident_not_found: %', p_incident_id using errcode = 'no_data_found';
  end if;

  if v_incident.tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_incident.tenant_id, 'MON', 'View');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to view this incident''s timeline', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.incident_timeline_events where incident_id = p_incident_id order by occurred_at asc;
end;
$$;

create function app.list_alert_routes_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.alert_routes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'View');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to view these alert routes', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.alert_routes
    where tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null)
    order by created_at desc;
end;
$$;

-- ===========================================================================
-- 6. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.slo_definitions enable row level security;
alter table app.observability_signals enable row level security;
alter table app.alert_routes enable row level security;
alter table app.incidents enable row level security;
alter table app.incident_timeline_events enable row level security;

revoke all on app.slo_definitions from public, anon, authenticated;
revoke all on app.observability_signals from public, anon, authenticated;
revoke all on app.alert_routes from public, anon, authenticated;
revoke all on app.incidents from public, anon, authenticated;
revoke all on app.incident_timeline_events from public, anon, authenticated;
grant all on app.slo_definitions, app.observability_signals, app.alert_routes, app.incidents, app.incident_timeline_events to service_role;

revoke execute on all functions in schema app from public;

grant execute on function
  app.record_observability_signal(uuid, text, text, text, numeric),
  app.raise_observability_alert(uuid, text, text, text, text, text)
to service_role;

grant execute on function
  app.set_slo_definition(uuid, text, text, numeric, integer, uuid, text),
  app.compute_job_queue_backlog(text, integer, uuid),
  app.set_alert_route(uuid, text, text, text, text, integer, uuid, text),
  app.acknowledge_incident(uuid, uuid, text),
  app.resolve_incident(uuid, text, uuid, text),
  app.list_incidents_for_tenant(uuid, uuid),
  app.get_incident_timeline(uuid, uuid),
  app.list_alert_routes_for_tenant(uuid, uuid)
to authenticated, service_role;
