-- Real, executable test evidence for IAE-034 (Scale-Up Architecture, Prompt
-- 362) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260808200000_create_intelligence_scale_up_architecture.sql),
-- plus its own real composition with IAE-030's own observability/alerting
-- (supabase/migrations/20260807400000_create_intelligence_enterprise_monitoring_observability.sql)
-- and IAE-032's own dedicated-deployment lifecycle
-- (supabase/migrations/20260808000000_create_intelligence_dedicated_enterprise_deployment.sql).
-- Fresh, distinctive tenant fixture (iaescale), fixture id range
-- 00000000-0000-0000-0000-000037xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaescale with admin1 (tenant_admin + MON:Configure/View), viewer1 (MON:View only), rep1 (plain org_user, no MON grants); a second tenant iaescale2 with admin2 (tenant_admin + MON:Configure/View) for cross-tenant isolation; a platform-wide supreme admin'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000037000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000037000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000037000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000037000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000037000004';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaescale.test'),
    (v_admin1, 'admin@iaescale.test'),
    (v_viewer1, 'viewer@iaescale.test'),
    (v_rep1, 'rep@iaescale.test'),
    (v_admin2, 'admin@iaescale2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaescale', 'IaeScale Co', 'idem-iaescale', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaescale');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaescale2', 'IaeScale2 Co', 'idem-iaescale2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaescale2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaescale.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaescale.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaescale.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaescale.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaescale.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaescale.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaescale2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaescale2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeScale Admin', 'MON:Configure/View plus DEPLOY:Configure/Approve/View -- the latter needed only to drive IAE-032''s own dedicated-deployment lifecycle for this checkpoint''s own composition test', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(
    select id from app.permissions
    where (resource_module_code = 'MON' and action in ('Configure', 'View'))
       or (resource_module_code = 'DEPLOY' and action in ('Configure', 'Approve', 'View'))
  ), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeScale Viewer', 'MON:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'MON' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeScale2 Admin', 'MON:Configure/View -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'MON' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.resolve_workload_budget: NULL (not an error) when neither a tenant override nor a platform default exists'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
begin
  if app.resolve_workload_budget(v_tenant1, 'analytics') is not null then
    raise exception 'assertion failed: expected NULL with zero capacity profiles configured, got %', app.resolve_workload_budget(v_tenant1, 'analytics');
  end if;
end;
$$;

\echo '>> app.set_workload_capacity_profile: rep1 (no MON:Configure) rejected; viewer1 (View only) rejected; admin1 (Configure) succeeds for tenant-scoped analytics; invalid workload_type/budget/window rejected; a second call upserts the SAME row (record_version increments)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_admin1 uuid := '00000000-0000-0000-0000-000037000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000037000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000037000003';
  v_first app.workload_capacity_profiles;
  v_second app.workload_capacity_profiles;
begin
  begin
    perform app.set_workload_capacity_profile(v_tenant1, 'analytics', 100, 60, v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_workload_capacity_profile(v_tenant1, 'analytics', 100, 60, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_first := app.set_workload_capacity_profile(v_tenant1, 'analytics', 100, 60, v_admin1, 'admin1');
  if v_first.budget_value <> 100 or v_first.record_version <> 1 then
    raise exception 'assertion failed: expected budget_value=100 record_version=1, got budget=% version=%', v_first.budget_value, v_first.record_version;
  end if;

  begin
    perform app.set_workload_capacity_profile(v_tenant1, 'not-a-real-workload', 100, 60, v_admin1, 'admin1');
    raise exception 'assertion failed: expected workload_invalid_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_workload_capacity_profile(v_tenant1, 'analytics', 0, 60, v_admin1, 'admin1');
    raise exception 'assertion failed: expected workload_invalid_budget, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_workload_capacity_profile(v_tenant1, 'analytics', 100, 0, v_admin1, 'admin1');
    raise exception 'assertion failed: expected workload_invalid_window, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_second := app.set_workload_capacity_profile(v_tenant1, 'analytics', 150, 60, v_admin1, 'admin1');
  if v_second.id <> v_first.id or v_second.budget_value <> 150 or v_second.record_version <> 2 then
    raise exception 'assertion failed: expected the SAME row upserted to budget_value=150 record_version=2, got id=% budget=% version=%', v_second.id, v_second.budget_value, v_second.record_version;
  end if;

  if app.resolve_workload_budget(v_tenant1, 'analytics') <> 150 then
    raise exception 'assertion failed: expected resolve_workload_budget to reflect the tenant override (150), got %', app.resolve_workload_budget(v_tenant1, 'analytics');
  end if;
end;
$$;

\echo '>> app.set_workload_capacity_profile platform-wide (tenant_id null): admin1 (tenant_admin, not supreme) rejected; supreme succeeds and the platform default applies to a tenant with no override of its own'
do $$
declare
  v_admin1 uuid := '00000000-0000-0000-0000-000037000001';
  v_supreme uuid := '00000000-0000-0000-0000-000037000000';
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaescale2');
  v_platform app.workload_capacity_profiles;
begin
  begin
    perform app.set_workload_capacity_profile(null, 'oltp', 500, 60, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 configuring a platform-wide profile, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_platform := app.set_workload_capacity_profile(null, 'oltp', 500, 60, v_supreme, 'supreme');
  if v_platform.tenant_id is not null then
    raise exception 'assertion failed: expected a real platform-wide (tenant_id null) profile row, got tenant_id=%', v_platform.tenant_id;
  end if;

  if app.resolve_workload_budget(v_tenant2, 'oltp') <> 500 then
    raise exception 'assertion failed: expected tenant2 (no override of its own) to inherit the platform default (500), got %', app.resolve_workload_budget(v_tenant2, 'oltp');
  end if;
end;
$$;

\echo '>> app.evaluate_workload_budget: invalid workload_type rejected; no_budget_configured for a workload with zero profiles; within_budget for an observed value under the tenant override, zero incident created; backpressure_applied for a breach, composing a REAL app.incidents row via app.raise_observability_alert (IAE-030)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_event app.workload_backpressure_events;
  v_incident_count integer;
begin
  begin
    perform app.evaluate_workload_budget(v_tenant1, 'not-a-real-workload', 10);
    raise exception 'assertion failed: expected workload_invalid_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_event := app.evaluate_workload_budget(v_tenant1, 'reports', 999);
  if v_event.action_taken <> 'no_budget_configured' or v_event.alert_incident_id is not null then
    raise exception 'assertion failed: expected no_budget_configured with no incident, got action=% incident=%', v_event.action_taken, v_event.alert_incident_id;
  end if;

  v_event := app.evaluate_workload_budget(v_tenant1, 'analytics', 50);
  if v_event.action_taken <> 'within_budget' or v_event.alert_incident_id is not null then
    raise exception 'assertion failed: expected within_budget with no incident for 50 against a 150 budget, got action=% incident=%', v_event.action_taken, v_event.alert_incident_id;
  end if;

  v_event := app.evaluate_workload_budget(v_tenant1, 'analytics', 200);
  if v_event.action_taken <> 'backpressure_applied' or v_event.alert_incident_id is null then
    raise exception 'assertion failed: expected backpressure_applied WITH a real incident for 200 against a 150 budget, got action=% incident=%', v_event.action_taken, v_event.alert_incident_id;
  end if;

  select count(*) into v_incident_count from app.incidents where id = v_event.alert_incident_id and source_type = 'job' and signal_type = 'backlog_depth' and severity = 'high';
  if v_incident_count <> 1 then
    raise exception 'assertion failed: expected a real app.incidents row (source_type=job, signal_type=backlog_depth, severity=high) for the analytics breach, found %', v_incident_count;
  end if;
end;
$$;

\echo '>> app.evaluate_workload_budget workload_type -> source_type mapping and dedup composition: webhooks maps to source_type=webhook; a second breach for the SAME workload within the dedupe window reuses the SAME incident (composing IAE-030''s own dedup, not a second parallel path)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_first app.workload_backpressure_events;
  v_second app.workload_backpressure_events;
  v_incident_count integer;
begin
  perform app.set_workload_capacity_profile(v_tenant1, 'webhooks', 10, 60, '00000000-0000-0000-0000-000037000001', 'admin1');

  v_first := app.evaluate_workload_budget(v_tenant1, 'webhooks', 20);
  if v_first.action_taken <> 'backpressure_applied' then
    raise exception 'assertion failed: expected backpressure_applied for webhooks, got %', v_first.action_taken;
  end if;
  select count(*) into v_incident_count from app.incidents where id = v_first.alert_incident_id and source_type = 'webhook';
  if v_incident_count <> 1 then
    raise exception 'assertion failed: expected the webhooks breach to map to source_type=webhook, found %', v_incident_count;
  end if;

  v_second := app.evaluate_workload_budget(v_tenant1, 'webhooks', 25);
  if v_second.alert_incident_id <> v_first.alert_incident_id then
    raise exception 'assertion failed: expected the SECOND webhooks breach within the dedupe window to reuse the SAME incident %, got %', v_first.alert_incident_id, v_second.alert_incident_id;
  end if;

  select count(*) into v_incident_count from app.incidents where tenant_id = v_tenant1 and source_type = 'webhook' and signal_type = 'backlog_depth';
  if v_incident_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 real incident row across both webhooks breaches (deduplicated), found %', v_incident_count;
  end if;
end;
$$;

\echo '>> app.generate_scaling_recommendation: rep1 (no MON:Configure) rejected; empty rationale rejected; invalid workload_type/recommendation_type rejected; admin1 succeeds for read_model; a dedicated_deployment recommendation succeeds while the tenant has no active dedicated deployment yet'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_admin1 uuid := '00000000-0000-0000-0000-000037000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000037000003';
  v_read_model app.scaling_recommendations;
  v_dedicated app.scaling_recommendations;
begin
  begin
    perform app.generate_scaling_recommendation(v_tenant1, 'analytics', 'read_model', 'repeated backpressure on analytics reads', v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.generate_scaling_recommendation(v_tenant1, 'analytics', 'read_model', '', v_admin1, 'admin1');
    raise exception 'assertion failed: expected scaling_recommendation_rationale_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.generate_scaling_recommendation(v_tenant1, 'not-a-real-workload', 'read_model', 'x', v_admin1, 'admin1');
    raise exception 'assertion failed: expected workload_invalid_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.generate_scaling_recommendation(v_tenant1, 'analytics', 'not-a-real-type', 'x', v_admin1, 'admin1');
    raise exception 'assertion failed: expected scaling_recommendation_invalid_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_read_model := app.generate_scaling_recommendation(v_tenant1, 'analytics', 'read_model', 'repeated backpressure on analytics reads', v_admin1, 'admin1');
  if v_read_model.status <> 'open' then
    raise exception 'assertion failed: expected status=open, got %', v_read_model.status;
  end if;

  v_dedicated := app.generate_scaling_recommendation(v_tenant1, 'analytics', 'dedicated_deployment', 'sustained analytics load may need a dedicated instance', v_admin1, 'admin1');
  if v_dedicated.status <> 'open' then
    raise exception 'assertion failed: expected status=open for the dedicated_deployment recommendation, got %', v_dedicated.status;
  end if;
end;
$$;

\echo '>> composing IAE-032''s own dedicated-deployment lifecycle end to end so tenant1 genuinely reaches an active dedicated deployment, then a SECOND dedicated_deployment recommendation is rejected as redundant'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_admin1 uuid := '00000000-0000-0000-0000-000037000001';
  v_deployment_id uuid;
begin
  perform app.request_dedicated_deployment_qualification(v_tenant1, 'dedicated instance required for sustained analytics load', 'MSA-2026-005', v_admin1, 'admin1');
  select id into v_deployment_id from app.tenant_deployment_records where tenant_id = v_tenant1;
  perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_admin1, 'admin1');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'provisioning', v_admin1, 'admin1');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'active', v_admin1, 'admin1');

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'dedicated' then
    raise exception 'assertion failed: expected tenant1 to now have an active dedicated deployment, got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;

  begin
    perform app.generate_scaling_recommendation(v_tenant1, 'analytics', 'dedicated_deployment', 'should be redundant now', v_admin1, 'admin1');
    raise exception 'assertion failed: expected scaling_recommendation_already_dedicated now that tenant1 genuinely has an active dedicated deployment, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_scaling_recommendation_status: the real, ordered transition graph -- open cannot skip straight to implemented; viewer1 (View only) rejected; the read_model recommendation is driven open->acknowledged->implemented; the earlier dedicated_deployment recommendation is driven open->dismissed with a real reason (empty reason rejected first)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_admin1 uuid := '00000000-0000-0000-0000-000037000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000037000002';
  v_read_model_id uuid;
  v_dedicated_id uuid;
  v_updated app.scaling_recommendations;
begin
  select id into v_read_model_id from app.scaling_recommendations where tenant_id = v_tenant1 and recommendation_type = 'read_model';
  select id into v_dedicated_id from app.scaling_recommendations where tenant_id = v_tenant1 and recommendation_type = 'dedicated_deployment';

  begin
    perform app.set_scaling_recommendation_status(v_read_model_id, 'implemented', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected scaling_recommendation_invalid_transition for open->implemented (skipping acknowledged), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_scaling_recommendation_status(v_read_model_id, 'acknowledged', null, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_updated := app.set_scaling_recommendation_status(v_read_model_id, 'acknowledged', null, v_admin1, 'admin1');
  if v_updated.status <> 'acknowledged' or v_updated.acknowledged_by <> 'admin1' then
    raise exception 'assertion failed: expected status=acknowledged acknowledged_by=admin1, got status=% acknowledged_by=%', v_updated.status, v_updated.acknowledged_by;
  end if;

  v_updated := app.set_scaling_recommendation_status(v_read_model_id, 'implemented', null, v_admin1, 'admin1');
  if v_updated.status <> 'implemented' then
    raise exception 'assertion failed: expected status=implemented, got %', v_updated.status;
  end if;

  begin
    perform app.set_scaling_recommendation_status(v_dedicated_id, 'dismissed', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected scaling_recommendation_dismissed_reason_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_updated := app.set_scaling_recommendation_status(v_dedicated_id, 'dismissed', 'dedicated deployment already provisioned via a separate approved request', v_admin1, 'admin1');
  if v_updated.status <> 'dismissed' or v_updated.dismissed_reason is null then
    raise exception 'assertion failed: expected status=dismissed with a real dismissed_reason, got status=% reason=%', v_updated.status, v_updated.dismissed_reason;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaescale2, its own MON:Configure/View) cannot configure tenant1''s own capacity profile, generate/change a recommendation, or read tenant1''s own profile/events/recommendations'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_admin2 uuid := '00000000-0000-0000-0000-000037000004';
  v_recommendation_id uuid;
begin
  select id into v_recommendation_id from app.scaling_recommendations where tenant_id = v_tenant1 and recommendation_type = 'read_model';

  begin
    perform app.set_workload_capacity_profile(v_tenant1, 'analytics', 999, 60, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 configuring tenant1''s own capacity profile, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.generate_scaling_recommendation(v_tenant1, 'analytics', 'read_model', 'hijacked recommendation', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 generating a recommendation for tenant1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_scaling_recommendation_status(v_recommendation_id, 'acknowledged', null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 changing tenant1''s own recommendation status, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.get_workload_capacity_profile(v_tenant1, 'analytics', v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own capacity profile, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_backpressure_events_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own backpressure events, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_scaling_recommendations_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own scaling recommendations, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.get_workload_capacity_profile / app.list_backpressure_events_for_tenant / app.list_scaling_recommendations_for_tenant: rep1 (no MON:View) rejected; viewer1 (View) succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaescale');
  v_viewer1 uuid := '00000000-0000-0000-0000-000037000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000037000003';
  v_profile app.workload_capacity_profiles;
  v_count integer;
begin
  begin
    perform app.get_workload_capacity_profile(v_tenant1, 'analytics', v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no MON:View), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_profile := app.get_workload_capacity_profile(v_tenant1, 'analytics', v_viewer1);
  if v_profile.budget_value <> 150 then
    raise exception 'assertion failed: expected viewer1 to see the real analytics budget_value=150, got %', v_profile.budget_value;
  end if;

  select count(*) into v_count from app.list_backpressure_events_for_tenant(v_tenant1, v_viewer1);
  if v_count < 4 then
    raise exception 'assertion failed: expected viewer1 to see at least 4 backpressure events for tenant1, got %', v_count;
  end if;

  select count(*) into v_count from app.list_scaling_recommendations_for_tenant(v_tenant1, v_viewer1);
  if v_count <> 2 then
    raise exception 'assertion failed: expected viewer1 to see exactly 2 scaling recommendations for tenant1, got %', v_count;
  end if;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000037000001", "role": "authenticated"}';

  begin
    perform count(*) from app.workload_capacity_profiles;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.workload_capacity_profiles, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.workload_backpressure_events;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.workload_backpressure_events, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.scaling_recommendations;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.scaling_recommendations, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function; authenticated holds zero EXECUTE on app.resolve_workload_budget/app.evaluate_workload_budget specifically (both service_role-only) while service_role does'
do $$
declare
  v_anon_grant_count integer;
  v_authenticated_on_resolve boolean;
  v_authenticated_on_evaluate boolean;
  v_service_role_on_resolve boolean;
  v_service_role_on_evaluate boolean;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'set_workload_capacity_profile', 'resolve_workload_budget', 'evaluate_workload_budget',
      'generate_scaling_recommendation', 'set_scaling_recommendation_status',
      'get_workload_capacity_profile', 'list_backpressure_events_for_tenant', 'list_scaling_recommendations_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 8 functions, found %', v_anon_grant_count;
  end if;

  select has_function_privilege('authenticated', 'app.resolve_workload_budget(uuid, text)', 'EXECUTE') into v_authenticated_on_resolve;
  select has_function_privilege('authenticated', 'app.evaluate_workload_budget(uuid, text, numeric)', 'EXECUTE') into v_authenticated_on_evaluate;
  if v_authenticated_on_resolve or v_authenticated_on_evaluate then
    raise exception 'assertion failed: expected authenticated to hold ZERO EXECUTE on either service_role-only function, found resolve=% evaluate=%', v_authenticated_on_resolve, v_authenticated_on_evaluate;
  end if;

  select has_function_privilege('service_role', 'app.resolve_workload_budget(uuid, text)', 'EXECUTE') into v_service_role_on_resolve;
  select has_function_privilege('service_role', 'app.evaluate_workload_budget(uuid, text, numeric)', 'EXECUTE') into v_service_role_on_evaluate;
  if not v_service_role_on_resolve or not v_service_role_on_evaluate then
    raise exception 'assertion failed: expected service_role to hold EXECUTE on both, found resolve=% evaluate=%', v_service_role_on_resolve, v_service_role_on_evaluate;
  end if;
end;
$$;

\echo 'ALL IAE-034 (Scale-Up Architecture) ASSERTIONS PASSED'
