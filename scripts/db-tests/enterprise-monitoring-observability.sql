-- Real, executable test evidence for IAE-030 (Enterprise Monitoring and
-- Observability, Prompt 358) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/20260807400000_create_intelligence_enterprise_monitoring_observability.sql).
-- Fresh, distinctive tenant fixture (iaemon), fixture id range
-- 00000000-0000-0000-0000-000033xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaemon with admin1 (tenant_admin + MON:Configure/Edit/View), viewer1 (MON:View only), rep1 (plain org_user, no MON grants); a second tenant iaemon2 with admin2 (tenant_admin + MON:Configure/Edit/View) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000033000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000033000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000033000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000033000004';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaemon.test'),
    (v_admin1, 'admin@iaemon.test'),
    (v_viewer1, 'viewer@iaemon.test'),
    (v_rep1, 'rep@iaemon.test'),
    (v_admin2, 'admin@iaemon2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaemon', 'IaeMon Co', 'idem-iaemon', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaemon');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaemon2', 'IaeMon2 Co', 'idem-iaemon2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaemon2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaemon.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemon.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaemon.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaemon.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaemon.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaemon.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaemon2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemon2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeMon Admin', 'MON:Configure/Edit/View', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'MON' and action in ('Configure', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeMon Viewer', 'MON:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'MON' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeMon2 Admin', 'MON:Configure/Edit/View -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'MON' and action in ('Configure', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.set_slo_definition: viewer1 (View only) rejected; admin1 (Configure) creates a new SLO; a second call with a different target upserts the SAME row (record_version increments, not a duplicate); invalid metric_type/window rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000033000002';
  v_first app.slo_definitions;
  v_second app.slo_definitions;
  v_count integer;
begin
  begin
    perform app.set_slo_definition(v_tenant1, 'dispatch-api', 'latency_p95', 500, 60, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_first := app.set_slo_definition(v_tenant1, 'dispatch-api', 'latency_p95', 500, 60, v_admin1, 'admin1');
  if v_first.target_value <> 500 or v_first.record_version <> 1 then
    raise exception 'assertion failed: expected target_value=500 record_version=1, got target_value=% record_version=%', v_first.target_value, v_first.record_version;
  end if;

  v_second := app.set_slo_definition(v_tenant1, 'dispatch-api', 'latency_p95', 750, 30, v_admin1, 'admin1');
  if v_second.id <> v_first.id or v_second.target_value <> 750 or v_second.evaluation_window_minutes <> 30 or v_second.record_version <> 2 then
    raise exception 'assertion failed: expected the SAME row upserted to target_value=750 window=30 record_version=2, got id=% target_value=% window=% record_version=%', v_second.id, v_second.target_value, v_second.evaluation_window_minutes, v_second.record_version;
  end if;

  select count(*) into v_count from app.slo_definitions where tenant_id = v_tenant1 and service_name = 'dispatch-api' and metric_type = 'latency_p95';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row after upsert, got %', v_count;
  end if;

  begin
    perform app.set_slo_definition(v_tenant1, 'dispatch-api', 'not-a-real-metric', 500, 60, v_admin1, 'admin1');
    raise exception 'assertion failed: expected slo_invalid_metric_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_slo_definition(v_tenant1, 'dispatch-api', 'availability', 99, 20000, v_admin1, 'admin1');
    raise exception 'assertion failed: expected slo_invalid_window, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_slo_definition platform-wide (tenant_id null): admin1 (tenant_admin, not supreme) rejected; supreme succeeds'
do $$
declare
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_supreme uuid := '00000000-0000-0000-0000-000033000000';
  v_platform app.slo_definitions;
begin
  begin
    perform app.set_slo_definition(null, 'shared-job-queue', 'queue_backlog', 100, 15, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 configuring a platform-wide SLO, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_platform := app.set_slo_definition(null, 'shared-job-queue', 'queue_backlog', 100, 15, v_supreme, 'supreme');
  if v_platform.tenant_id is not null then
    raise exception 'assertion failed: expected a real platform-wide (tenant_id null) SLO row, got tenant_id=%', v_platform.tenant_id;
  end if;
end;
$$;

\echo '>> app.record_observability_signal: valid source_type/signal_type combinations persist a numeric-only row; invalid ones are rejected, never silently coerced'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_signal app.observability_signals;
begin
  v_signal := app.record_observability_signal(v_tenant1, 'job', 'audit_export:abc123', 'latency_ms', 842);
  if v_signal.value <> 842 or v_signal.source_type <> 'job' or v_signal.signal_type <> 'latency_ms' then
    raise exception 'assertion failed: expected a real persisted signal row, got %', v_signal;
  end if;

  begin
    perform app.record_observability_signal(v_tenant1, 'not-a-real-source', null, 'error', 1);
    raise exception 'assertion failed: expected observability_signal_invalid_source_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_observability_signal(v_tenant1, 'webhook', null, 'not-a-real-signal', 1);
    raise exception 'assertion failed: expected observability_signal_invalid_signal_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.compute_job_queue_backlog: Supreme-Admin-only (it is a genuinely platform-wide metric, not tenant-scoped); reads the REAL app.jobs table -- counts only pending, past-threshold-age rows of the requested job_type; a completed old row and a different job_type do not leak into the count'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_supreme uuid := '00000000-0000-0000-0000-000033000000';
  v_backlog integer;
begin
  insert into app.jobs (tenant_id, job_type, status, created_at, requested_by_auth_user_id) values
    (v_tenant1, 'webhook_retry', 'pending', now() - interval '10 minutes', v_admin1),
    (v_tenant1, 'webhook_retry', 'pending', now(), v_admin1),
    (v_tenant1, 'webhook_retry', 'completed', now() - interval '20 minutes', v_admin1),
    (v_tenant1, 'notification_batch', 'pending', now() - interval '20 minutes', v_admin1);

  begin
    perform app.compute_job_queue_backlog('webhook_retry', 5, v_admin1);
    raise exception 'assertion failed: expected insufficient_authority for admin1 (tenant_admin, not Supreme Admin) reading the platform-wide job queue backlog, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_backlog := app.compute_job_queue_backlog('webhook_retry', 5, v_supreme);
  if v_backlog <> 1 then
    raise exception 'assertion failed: expected exactly 1 stale pending webhook_retry job, got %', v_backlog;
  end if;
end;
$$;

\echo '>> app.set_alert_route: viewer1 rejected; admin1 succeeds; invalid dedupe window rejected; a second call upserts the SAME route (owner_team/email/window change in place)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000033000002';
  v_first app.alert_routes;
  v_second app.alert_routes;
  v_count integer;
begin
  begin
    perform app.set_alert_route(v_tenant1, 'job', 'backlog_depth', 'ops-team', 'ops@iaemon.test', 5, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_first := app.set_alert_route(v_tenant1, 'job', 'backlog_depth', 'ops-team', 'ops@iaemon.test', 5, v_admin1, 'admin1');
  if v_first.dedupe_window_minutes <> 5 then
    raise exception 'assertion failed: expected dedupe_window_minutes=5, got %', v_first.dedupe_window_minutes;
  end if;

  v_second := app.set_alert_route(v_tenant1, 'job', 'backlog_depth', 'sre-team', 'sre@iaemon.test', 10, v_admin1, 'admin1');
  if v_second.id <> v_first.id or v_second.owner_team <> 'sre-team' or v_second.dedupe_window_minutes <> 10 then
    raise exception 'assertion failed: expected the SAME route upserted to owner_team=sre-team window=10, got id=% owner_team=% window=%', v_second.id, v_second.owner_team, v_second.dedupe_window_minutes;
  end if;

  select count(*) into v_count from app.alert_routes where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'backlog_depth';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 route row after upsert, got %', v_count;
  end if;

  begin
    perform app.set_alert_route(v_tenant1, 'api', 'error', 'ops-team', null, 5000, v_admin1, 'admin1');
    raise exception 'assertion failed: expected alert_route_invalid_dedupe_window, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_alert_route(null, 'job', 'backlog_depth', 'platform-sre', null, 15, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 configuring a platform-wide alert route, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.raise_observability_alert: first signal opens a real new incident using the matching route''s dedupe window and owner_team; a repeat signal within the window is absorbed as a duplicate_signal timeline event on the SAME incident, never a second incident'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_incident1 app.incidents;
  v_incident2 app.incidents;
  v_count integer;
  v_event_count integer;
begin
  v_incident1 := app.raise_observability_alert(v_tenant1, 'job', 'backlog_depth', 'Dispatch queue backlog rising', 'high', 'depth=120');
  if v_incident1.status <> 'open' or v_incident1.owner_team <> 'sre-team' then
    raise exception 'assertion failed: expected a real open incident with owner_team=sre-team (from the route), got status=% owner_team=%', v_incident1.status, v_incident1.owner_team;
  end if;

  v_incident2 := app.raise_observability_alert(v_tenant1, 'job', 'backlog_depth', 'Dispatch queue backlog rising', 'high', 'depth=140');
  if v_incident2.id <> v_incident1.id then
    raise exception 'assertion failed: expected the SAME incident id % to be returned for a repeat signal within the dedupe window, got %', v_incident1.id, v_incident2.id;
  end if;

  select count(*) into v_count from app.incidents where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'backlog_depth';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 incident row (deduplicated), got %', v_count;
  end if;

  select count(*) into v_event_count from app.incident_timeline_events where incident_id = v_incident1.id;
  if v_event_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 timeline events (opened, duplicate_signal), got %', v_event_count;
  end if;

  if not exists (select 1 from app.incident_timeline_events where incident_id = v_incident1.id and event_type = 'duplicate_signal' and detail = 'depth=140') then
    raise exception 'assertion failed: expected a duplicate_signal timeline event carrying the second signal''s own detail';
  end if;
end;
$$;

\echo '>> app.raise_observability_alert: once the existing incident''s own opened_at falls outside the route''s dedupe window, a repeat signal opens a genuinely NEW incident rather than deduplicating forever'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_existing_id uuid;
  v_new app.incidents;
  v_count integer;
begin
  select id into v_existing_id from app.incidents where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'backlog_depth';
  update app.incidents set opened_at = now() - interval '1 hour' where id = v_existing_id;

  v_new := app.raise_observability_alert(v_tenant1, 'job', 'backlog_depth', 'Dispatch queue backlog rising again', 'high', 'depth=200');
  if v_new.id = v_existing_id then
    raise exception 'assertion failed: expected a genuinely new incident once the prior one aged out of the dedupe window, got the same id %', v_existing_id;
  end if;

  select count(*) into v_count from app.incidents where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'backlog_depth';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 incident rows now, got %', v_count;
  end if;
end;
$$;

\echo '>> app.raise_observability_alert: a RESOLVED incident is never matched for dedup, even seconds later; and with no matching alert route at all the function falls back to its own 30-minute default dedupe window'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_open_id uuid;
  v_after_resolve app.incidents;
  v_dedup app.incidents;
  v_no_route_1 app.incidents;
  v_no_route_2 app.incidents;
  v_count integer;
begin
  -- Resolve every currently-open backlog_depth incident for this tenant first --
  -- the prior test block deliberately left one aged-out-of-window incident
  -- still open (to prove the window boundary), alongside the one just
  -- deduplicated against. Both must be resolved before this block can prove
  -- "a resolved incident is never matched" in isolation.
  for v_open_id in select id from app.incidents where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'backlog_depth' and status <> 'resolved'
  loop
    perform app.resolve_incident(v_open_id, 'test cleanup', v_admin1, 'admin1');
  end loop;

  v_after_resolve := app.raise_observability_alert(v_tenant1, 'job', 'backlog_depth', 'Dispatch queue backlog rising a third time', 'medium', 'depth=90');
  if v_after_resolve.status <> 'open' then
    raise exception 'assertion failed: expected a genuinely new, open incident once every prior one was resolved, got status %', v_after_resolve.status;
  end if;

  select count(*) into v_count from app.incidents where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'backlog_depth' and status <> 'resolved';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 non-resolved incident after resolving every prior one and re-raising, got %', v_count;
  end if;

  v_dedup := app.raise_observability_alert(v_tenant1, 'job', 'backlog_depth', 'Dispatch queue backlog rising a third time (again)', 'medium', 'depth=95');
  if v_dedup.id <> v_after_resolve.id then
    raise exception 'assertion failed: expected the fresh incident % to absorb an immediate repeat signal via dedup, got a different id %', v_after_resolve.id, v_dedup.id;
  end if;

  -- No app.alert_routes row exists at all for (job, error) in this tenant --
  -- the function still deduplicates, using its own disclosed 30-minute default.
  v_no_route_1 := app.raise_observability_alert(v_tenant1, 'job', 'error', 'Job execution errors spiking', 'critical', 'count=5');
  if v_no_route_1.owner_team is not null then
    raise exception 'assertion failed: expected owner_team null with no matching route, got %', v_no_route_1.owner_team;
  end if;
  v_no_route_2 := app.raise_observability_alert(v_tenant1, 'job', 'error', 'Job execution errors spiking', 'critical', 'count=9');
  if v_no_route_2.id <> v_no_route_1.id then
    raise exception 'assertion failed: expected the default 30-minute dedupe window to absorb the repeat signal into the same incident %, got %', v_no_route_1.id, v_no_route_2.id;
  end if;

  begin
    perform app.raise_observability_alert(v_tenant1, 'job', 'error', 'bad severity', 'not-a-real-severity', null);
    raise exception 'assertion failed: expected incident_invalid_severity, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.acknowledge_incident / app.resolve_incident: viewer1 (View only) rejected for both; admin1 (Edit) succeeds; a resolved incident cannot be acknowledged or resolved again'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000033000002';
  v_incident_id uuid;
  v_ack app.incidents;
  v_resolved app.incidents;
  v_event_types text[];
begin
  select id into v_incident_id from app.incidents where tenant_id = v_tenant1 and source_type = 'job' and signal_type = 'error' order by opened_at desc limit 1;

  begin
    perform app.acknowledge_incident(v_incident_id, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 acknowledging, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_ack := app.acknowledge_incident(v_incident_id, v_admin1, 'admin1');
  if v_ack.status <> 'acknowledged' or v_ack.acknowledged_by <> 'admin1' then
    raise exception 'assertion failed: expected status acknowledged with acknowledged_by=admin1, got status=% acknowledged_by=%', v_ack.status, v_ack.acknowledged_by;
  end if;

  begin
    perform app.acknowledge_incident(v_incident_id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected incident_not_open on a re-acknowledge, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;

  begin
    perform app.resolve_incident(v_incident_id, 'closing', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 resolving, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_resolved := app.resolve_incident(v_incident_id, 'errors stopped after redeploy', v_admin1, 'admin1');
  if v_resolved.status <> 'resolved' or v_resolved.resolution_note <> 'errors stopped after redeploy' then
    raise exception 'assertion failed: expected status resolved with the real resolution_note, got status=% note=%', v_resolved.status, v_resolved.resolution_note;
  end if;

  begin
    perform app.resolve_incident(v_incident_id, 'again', v_admin1, 'admin1');
    raise exception 'assertion failed: expected incident_not_open on a re-resolve, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;

  -- This incident already carries one duplicate_signal event from the prior
  -- test block's own no-route dedup proof (v_no_route_1/v_no_route_2), so the
  -- full chronological timeline is [opened, duplicate_signal, acknowledged, resolved].
  select array_agg(event_type order by occurred_at asc) into v_event_types from app.incident_timeline_events where incident_id = v_incident_id;
  if v_event_types <> array['opened', 'duplicate_signal', 'acknowledged', 'resolved'] then
    raise exception 'assertion failed: expected timeline [opened, duplicate_signal, acknowledged, resolved] in chronological order, got %', v_event_types;
  end if;
end;
$$;

\echo '>> platform-wide incidents (tenant_id null): only Supreme Admin can raise-authorize-visible actions; a tenant_admin (admin1) is rejected even for acknowledge/resolve/list'
do $$
declare
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_supreme uuid := '00000000-0000-0000-0000-000033000000';
  v_platform_incident app.incidents;
  v_count integer;
begin
  v_platform_incident := app.raise_observability_alert(null, 'integration', 'error', 'Shared webhook dispatcher erroring', 'critical', 'rate=0.4');
  if v_platform_incident.tenant_id is not null then
    raise exception 'assertion failed: expected a real platform-wide (tenant_id null) incident, got tenant_id=%', v_platform_incident.tenant_id;
  end if;

  begin
    perform app.acknowledge_incident(v_platform_incident.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 acknowledging a platform-wide incident, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_incidents_for_tenant(null, v_admin1);
    raise exception 'assertion failed: expected insufficient_authority for admin1 listing platform-wide incidents, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  perform app.acknowledge_incident(v_platform_incident.id, v_supreme, 'supreme');
  perform app.resolve_incident(v_platform_incident.id, 'dispatcher redeployed', v_supreme, 'supreme');

  select count(*) into v_count from app.list_incidents_for_tenant(null, v_supreme) where id = v_platform_incident.id and status = 'resolved';
  if v_count <> 1 then
    raise exception 'assertion failed: expected supreme to see the resolved platform-wide incident, got count=%', v_count;
  end if;
end;
$$;

\echo '>> app.list_incidents_for_tenant / app.get_incident_timeline / app.list_alert_routes_for_tenant: rep1 (no MON grant) rejected; viewer1/admin1 (View) succeed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000033000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000033000003';
  v_count integer;
  v_incident_id uuid;
begin
  begin
    perform count(*) from app.list_incidents_for_tenant(v_tenant1, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no MON grant) listing incidents, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select count(*) into v_count from app.list_incidents_for_tenant(v_tenant1, v_viewer1);
  if v_count < 1 then
    raise exception 'assertion failed: expected viewer1 to see at least 1 incident for tenant1, got %', v_count;
  end if;

  select id into v_incident_id from app.incidents where tenant_id = v_tenant1 order by opened_at desc limit 1;
  select count(*) into v_count from app.get_incident_timeline(v_incident_id, v_viewer1);
  if v_count < 1 then
    raise exception 'assertion failed: expected viewer1 to see at least 1 timeline event, got %', v_count;
  end if;

  select count(*) into v_count from app.list_alert_routes_for_tenant(v_tenant1, v_admin1);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 alert route for tenant1, got %', v_count;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaemon2) cannot configure/act on/read tenant1''s own SLOs, alert routes, incidents or timelines'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin2 uuid := '00000000-0000-0000-0000-000033000004';
  v_incident_id uuid;
begin
  begin
    perform app.set_slo_definition(v_tenant1, 'dispatch-api', 'latency_p95', 999, 60, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 configuring tenant1''s own SLO, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_alert_route(v_tenant1, 'job', 'success', 'hijacked', null, 5, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 configuring tenant1''s own alert route, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_incidents_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own incidents, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_alert_routes_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own alert routes, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select id into v_incident_id from app.incidents where tenant_id = v_tenant1 order by opened_at desc limit 1;

  begin
    perform app.acknowledge_incident(v_incident_id, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 acknowledging tenant1''s own incident, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.get_incident_timeline(v_incident_id, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own incident timeline, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000033000001", "role": "authenticated"}';

  begin
    perform count(*) from app.slo_definitions;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.slo_definitions, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.observability_signals;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.observability_signals, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.alert_routes;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.alert_routes, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.incidents;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.incidents, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.incident_timeline_events;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.incident_timeline_events, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function -- including the two service_role-only ingestion/alerting entry points'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'set_slo_definition', 'record_observability_signal', 'compute_job_queue_backlog',
      'set_alert_route', 'raise_observability_alert', 'acknowledge_incident', 'resolve_incident',
      'list_incidents_for_tenant', 'get_incident_timeline', 'list_alert_routes_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 10 functions, found %', v_anon_grant_count;
  end if;
end;
$$;

\echo '>> HDN-382 (Observability Audit): app.ping() -- the /api/ready DB-connectivity probe -- returns true, is anon-inaccessible, and touches no application table (a readiness probe is not itself a tenant-data-leak surface)'
do $$
declare
  v_result boolean;
  v_anon_grant boolean;
begin
  v_result := app.ping();
  if v_result is distinct from true then
    raise exception 'assertion failed: expected app.ping() to return true, got %', v_result;
  end if;

  select has_function_privilege('anon', 'app.ping()'::regprocedure, 'EXECUTE') into v_anon_grant;
  if v_anon_grant then
    raise exception 'assertion failed: expected anon to hold no EXECUTE grant on app.ping()';
  end if;
end;
$$;

\echo 'ALL IAE-030 (Enterprise Monitoring and Observability) ASSERTIONS PASSED'

-- ===========================================================================
-- ISS-2026-258 -- incident communication: who was told, in what order, what was
-- said, and what is provably recorded afterwards.
-- ===========================================================================

\echo '>> ISS-2026-258: the notification order is data, ordered, and readable without authority (a responder needs it before they have looked anything up)'
do $$
declare
  v_codes text[];
begin
  select array_agg(code order by dispatch_order) into v_codes from app.list_incident_communication_audiences();
  if v_codes is distinct from array['internal', 'tenant_admins', 'customer_portal'] then
    raise exception 'assertion failed: expected the dispatch order internal -> tenant_admins -> customer_portal, got %', v_codes;
  end if;
  -- The order must be enforced by the schema, not merely happen to be right today: two
  -- audiences sharing a position would make "who is told first" ambiguous again.
  begin
    insert into app.incident_communication_audiences (code, name, dispatch_order, description)
    values ('duplicate_order', 'Duplicate order probe', 1, 'probe');
    raise exception 'assertion failed: expected a unique constraint to prevent two audiences claiming the same dispatch position';
  exception when unique_violation then
    null;
  end;
end $$;

\echo '>> ISS-2026-258: broadcasting is MON:Edit-gated exactly like acknowledging; it records the exact words sent, the real resolved recipients, a timeline event on the incident itself, and is idempotent -- and a key reused for DIFFERENT words is refused rather than silently re-sending'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemon');
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000033000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000033000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000033000004';
  v_incident app.incidents;
  v_comm app.incident_communications;
  v_replay app.incident_communications;
  v_count integer;
begin
  v_incident := app.raise_observability_alert(v_tenant1, 'integration', 'error', 'Carrier API returning 500s', 'critical', 'error_rate=0.42');

  -- MON:View alone cannot speak on an incident's behalf. Speaking is not a lesser act than
  -- acknowledging, so it does not get a lesser gate.
  begin
    perform app.broadcast_incident_communication(v_incident.id, 'internal', 'Subject', 'Body', null, null, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for a MON:View-only actor broadcasting';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform app.broadcast_incident_communication(v_incident.id, 'internal', 'Subject', 'Body', null, null, v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for an actor with no MON grant at all';
  exception when insufficient_privilege then
    null;
  end;
  -- A tenant_admin of a DIFFERENT tenant must not be able to speak on this tenant's incident.
  begin
    perform app.broadcast_incident_communication(v_incident.id, 'internal', 'Subject', 'Body', null, null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected cross-tenant broadcast to be refused';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.broadcast_incident_communication(v_incident.id, 'internal', '   ', 'Body', null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected an empty subject to be refused';
  exception when check_violation then
    null;
  end;
  begin
    perform app.broadcast_incident_communication(v_incident.id, 'not_an_audience', 'Subject', 'Body', null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected an unregistered audience to be refused';
  exception when check_violation then
    null;
  end;

  v_comm := app.broadcast_incident_communication(
    v_incident.id, 'internal',
    'Carrier API degraded -- investigating',
    'We are seeing elevated errors from the carrier API since 09:12 UTC. Shipment booking may fail intermittently. Next update within 30 minutes.',
    null, 'idem-iaemon-comm-1', v_admin1, 'admin1'
  );
  if v_comm.audience_code <> 'internal' or v_comm.severity <> 'critical' then
    raise exception 'assertion failed: expected the communication to inherit the incident''s own severity, got %', v_comm;
  end if;
  -- The exact words are stored, not a template reference that could later be edited to
  -- change what history says was said.
  if v_comm.body not like '%since 09:12 UTC%' then
    raise exception 'assertion failed: expected the body to be stored verbatim';
  end if;
  -- Real recipients, resolved from real membership rows: admin1 is an active tenant_admin.
  if v_comm.recipient_count < 1 then
    raise exception 'assertion failed: expected at least one resolved recipient (the tenant''s own admin), got %', v_comm.recipient_count;
  end if;
  select count(*) into v_count from app.incident_communication_recipients where communication_id = v_comm.id;
  if v_count <> v_comm.recipient_count then
    raise exception 'assertion failed: expected one recipient row per counted recipient -- the "to whom" record must match the count, got % rows for count %', v_count, v_comm.recipient_count;
  end if;

  -- The incident's own timeline carries it, so the whole story is in one place.
  if not exists (
    select 1 from app.incident_timeline_events
    where incident_id = v_incident.id and event_type = 'communicated' and detail like '%Carrier API degraded%'
  ) then
    raise exception 'assertion failed: expected a communicated event on the incident''s own timeline';
  end if;

  -- Idempotent: a retry returns the original and sends nothing further.
  v_replay := app.broadcast_incident_communication(
    v_incident.id, 'internal',
    'Carrier API degraded -- investigating',
    'We are seeing elevated errors from the carrier API since 09:12 UTC. Shipment booking may fail intermittently. Next update within 30 minutes.',
    null, 'idem-iaemon-comm-1', v_admin1, 'admin1'
  );
  if v_replay.id <> v_comm.id then
    raise exception 'assertion failed: expected an idempotent retry to return the original communication';
  end if;
  select count(*) into v_count from app.incident_communications where incident_id = v_incident.id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the retry to create no second communication, found %', v_count;
  end if;

  -- ...but the same key reused for DIFFERENT words is a conflict, not a quiet no-op. A
  -- second, different update silently discarded is the failure mode that matters here.
  begin
    perform app.broadcast_incident_communication(
      v_incident.id, 'internal', 'Carrier API degraded -- investigating',
      'Actually everything is fine.', null, 'idem-iaemon-comm-1', v_admin1, 'admin1'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict when the same key carries different words';
  exception when unique_violation then
    if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- The record is readable, MON:View-gated, newest first.
  select count(*) into v_count from app.list_incident_communications(v_incident.id, v_viewer1);
  if v_count <> 1 then
    raise exception 'assertion failed: expected MON:View to read the communication history, got % rows', v_count;
  end if;
  begin
    perform app.list_incident_communications(v_incident.id, v_rep1);
    raise exception 'assertion failed: expected an actor with no MON grant to be refused the communication history';
  exception when insufficient_privilege then
    null;
  end;
end $$;

\echo '>> ISS-2026-258: a platform-scoped incident is Supreme-Admin-only and cannot address a tenant audience that does not exist; a zero-recipient broadcast is recorded as zero rather than reported as sent'
do $$
declare
  v_admin1 uuid := '00000000-0000-0000-0000-000033000001';
  v_supreme uuid := '00000000-0000-0000-0000-000033000000';
  v_incident app.incidents;
  v_comm app.incident_communications;
begin
  v_incident := app.raise_observability_alert(null, 'api', 'latency_ms', 'Platform-wide API latency', 'high', 'p95=4200');

  begin
    perform app.broadcast_incident_communication(v_incident.id, 'internal', 'Subject', 'Body', null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected a tenant_admin to be refused on a PLATFORM-scoped incident (Supreme Admin only)';
  exception when insufficient_privilege then
    null;
  end;

  -- Addressing "tenant administrators" on an incident with no tenant is refused outright.
  -- Silently sending to nobody would read as done in the record, which is the whole failure
  -- this table exists to prevent.
  begin
    perform app.broadcast_incident_communication(v_incident.id, 'tenant_admins', 'Subject', 'Body', null, null, v_supreme, 'supreme');
    raise exception 'assertion failed: expected a tenant audience to be refused on a platform-scoped incident';
  exception when check_violation then
    null;
  end;

  -- A platform-scoped internal broadcast with no matching alert route resolves to zero
  -- recipients. That is recorded as zero -- visible, not hidden.
  v_comm := app.broadcast_incident_communication(v_incident.id, 'internal',
    'Platform latency elevated', 'p95 latency is 4200ms across the API tier.', null, null, v_supreme, 'supreme');
  if v_comm.recipient_count <> 0 then
    raise exception 'assertion failed: expected a zero-recipient broadcast to be recorded with recipient_count = 0, got %', v_comm.recipient_count;
  end if;
  if not exists (select 1 from app.incident_communications where id = v_comm.id) then
    raise exception 'assertion failed: a zero-recipient broadcast must still be recorded -- knowing nobody was reached is the point';
  end if;
end $$;

\echo '>> ISS-2026-258: neither anon nor authenticated holds direct table access to the communication record'
do $$
declare
  v_has boolean;
  v_tbl text;
begin
  foreach v_tbl in array array['app.incident_communications', 'app.incident_communication_recipients', 'app.incident_communication_audiences'] loop
    select has_table_privilege('anon', v_tbl, 'SELECT') into v_has;
    if v_has then raise exception 'assertion failed: anon must hold no SELECT on %', v_tbl; end if;
    select has_table_privilege('authenticated', v_tbl, 'SELECT') into v_has;
    if v_has then raise exception 'assertion failed: authenticated must hold no direct SELECT on % -- the RPCs are the only sanctioned path', v_tbl; end if;
    select relrowsecurity into v_has from pg_class where oid = v_tbl::regclass;
    if not v_has then raise exception 'assertion failed: expected RLS enabled on %', v_tbl; end if;
  end loop;
end $$;
