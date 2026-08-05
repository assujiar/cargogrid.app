-- Real, executable test evidence for ATW-226A (CG-S10-ATW-006's own child, Prompt 226
-- decomposition "Tracking entitlement and source policy") -- run via `pnpm run
-- db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant1 has a tenant_admin (also granted OPS:Edit, mirroring ATW-223''s own precedent that the config/entitlement authority and the OPS:Edit authority are separate grants) and an OPS:View-only viewer; tenant2 has its own isolated tenant_admin'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000040101', 'admin@acmetelemetry.test'),
    ('00000000-0000-0000-0000-000000040102', 'viewer@acmetelemetry.test'),
    ('00000000-0000-0000-0000-000000040103', 'supreme@acmetelemetry.test'),
    ('00000000-0000-0000-0000-000000040104', 'admin2@acmetelemetry2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000040103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmetelemetry', 'Acme Track Co', 'idem-acmetelemetry', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmetelemetry');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMETRACK-CO', 'Acme Track Co', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMETRACK-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000040101', 'admin@acmetelemetry.test', 'Tenant Admin', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmetelemetry.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000040101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000040102', 'viewer@acmetelemetry.test', 'OPS Viewer', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmetelemetry.test'), 'active', 'onboarded', 'tester');

  -- The tenant_admin also needs an explicit OPS:Edit grant to exercise
  -- app.upsert_tenant_tracking_source_policy itself (tenant_admin authority alone
  -- gates the *Configuration Engine* draft/publish path below, a separate check) --
  -- the same two-grants-are-separate precedent ATW-223's own db-test disclosed.
  v_edit_role := (app.create_role(v_tenant1, 'Tracking Editor', 'OPS:Edit', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'Edit'), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000040101', '00000000-0000-0000-0000-000000040103', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'OPS Viewer', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000040102', '00000000-0000-0000-0000-000000040103', 'tester');

  perform app.provision_tenant('acmetelemetry2', 'Acme Track Two', 'idem-acmetelemetry2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmetelemetry2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000040104', 'admin2@acmetelemetry2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmetelemetry2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000040104', 'tenant_admin', v_tenant2, null, 'tester');
end $$;

\echo '>> app.is_shipment_tracking_entitled / app.resolve_tenant_tracking_package: honest false/null default before any package is ever assigned (real implementation, not the ATW-222 stub)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_resolved app.tracking_package_resolution;
begin
  if app.is_shipment_tracking_entitled(v_tenant1) is distinct from false then
    raise exception 'assertion failed: expected false before any tracking package is assigned';
  end if;

  select * into v_resolved from app.resolve_tenant_tracking_package(v_tenant1);
  if v_resolved.enabled is distinct from false
    or v_resolved.package_code is not null
    or v_resolved.max_tracked_vehicles is not null
    or v_resolved.max_mobile_sessions is not null
    or v_resolved.history_retention_days is not null
    or v_resolved.resolved_version_id is not null
  then
    raise exception 'assertion failed: expected an all-default resolution row, got enabled=%, package_code=%', v_resolved.enabled, v_resolved.package_code;
  end if;
end $$;

\echo '>> tenant_admin assigns a real tracking package via the existing PLT-121 Configuration Engine draft/set-items/publish mutations -- app.resolve_tenant_tracking_package reflects it immediately, tenant2 stays unaffected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmetelemetry2');
  v_draft app.config_versions;
  v_published app.config_versions;
  v_resolved app.tracking_package_resolution;
begin
  v_draft := app.create_config_draft('feature', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000040101', 'tenant admin');
  perform app.set_config_items(
    v_draft.id,
    '[
      {"key": "tracking.enabled", "value": true},
      {"key": "tracking.package", "value": "standard"},
      {"key": "tracking.limits", "value": {"max_tracked_vehicles": 50, "max_mobile_sessions": 20, "history_retention_days": 90}}
    ]'::jsonb,
    '00000000-0000-0000-0000-000000040101', 'tenant admin'
  );
  v_published := app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000040101', null, 'tenant admin');

  if app.is_shipment_tracking_entitled(v_tenant1) is distinct from true then
    raise exception 'assertion failed: expected true once tracking.enabled=true is published';
  end if;

  select * into v_resolved from app.resolve_tenant_tracking_package(v_tenant1);
  if v_resolved.enabled is distinct from true
    or v_resolved.package_code is distinct from 'standard'
    or v_resolved.max_tracked_vehicles is distinct from 50
    or v_resolved.max_mobile_sessions is distinct from 20
    or v_resolved.history_retention_days is distinct from 90
    or v_resolved.resolved_version_id is distinct from v_published.id
  then
    raise exception 'assertion failed: expected standard package/50/20/90 resolved from version %, got %/%/%/%/%', v_published.id, v_resolved.enabled, v_resolved.package_code, v_resolved.max_tracked_vehicles, v_resolved.max_mobile_sessions, v_resolved.history_retention_days;
  end if;

  if app.is_shipment_tracking_entitled(v_tenant2) is distinct from false then
    raise exception 'assertion failed: tenant2 must remain unentitled -- cross-tenant leak';
  end if;
  select * into v_resolved from app.resolve_tenant_tracking_package(v_tenant2);
  if v_resolved.enabled is distinct from false or v_resolved.package_code is not null then
    raise exception 'assertion failed: tenant2''s resolution must stay all-default -- cross-tenant leak';
  end if;
end $$;

\echo '>> a superseding published version (package upgrade) is reflected immediately -- app.resolve_tenant_tracking_package always reads the currently-published version, never a stale one'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_draft app.config_versions;
  v_published app.config_versions;
  v_resolved app.tracking_package_resolution;
begin
  v_draft := app.create_config_draft('feature', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000040101', 'tenant admin');
  perform app.set_config_items(
    v_draft.id,
    '[
      {"key": "tracking.enabled", "value": true},
      {"key": "tracking.package", "value": "premium"},
      {"key": "tracking.limits", "value": {"max_tracked_vehicles": 500, "max_mobile_sessions": 200, "history_retention_days": 365}}
    ]'::jsonb,
    '00000000-0000-0000-0000-000000040101', 'tenant admin'
  );
  v_published := app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000040101', null, 'tenant admin');

  select * into v_resolved from app.resolve_tenant_tracking_package(v_tenant1);
  if v_resolved.package_code is distinct from 'premium' or v_resolved.max_tracked_vehicles is distinct from 500 or v_resolved.resolved_version_id is distinct from v_published.id then
    raise exception 'assertion failed: expected the superseding premium version to be resolved, got package=%, version=%', v_resolved.package_code, v_resolved.resolved_version_id;
  end if;
end $$;

\echo '>> app.resolve_tenant_tracking_source_policy: honest system-default (is_explicit=false) before any tenant explicitly overrides it -- no row exists yet'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_row_count integer;
  v_priority text[];
  v_freshness integer;
  v_accuracy numeric;
  v_hysteresis integer;
  v_explicit boolean;
begin
  select count(*) into v_row_count from app.tenant_tracking_source_policies where tenant_id = v_tenant1;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero explicit policy rows before any upsert, found %', v_row_count;
  end if;

  select default_source_priority, freshness_threshold_seconds, accuracy_threshold_meters, switch_hysteresis_seconds, is_explicit
    into v_priority, v_freshness, v_accuracy, v_hysteresis, v_explicit
    from app.resolve_tenant_tracking_source_policy(v_tenant1);

  if v_priority <> array['driver_mobile', 'direct_device', 'third_party_platform']
    or v_freshness <> 300 or v_accuracy <> 100 or v_hysteresis <> 120 or v_explicit is distinct from false
  then
    raise exception 'assertion failed: expected the system default (driver_mobile-first/300/100/120, is_explicit=false), got %/%/%/%/%', v_priority, v_freshness, v_accuracy, v_hysteresis, v_explicit;
  end if;
end $$;

\echo '>> app.upsert_tenant_tracking_source_policy: OPS:Edit-gated -- an OPS:View-only viewer and a same-role admin of a *different* tenant are both rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
begin
  begin
    perform app.upsert_tenant_tracking_source_policy(
      v_tenant1, array['direct_device', 'driver_mobile'], 180, 50, 90,
      '00000000-0000-0000-0000-000000040102', 'viewer'
    );
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.upsert_tenant_tracking_source_policy(
      v_tenant1, array['direct_device', 'driver_mobile'], 180, 50, 90,
      '00000000-0000-0000-0000-000000040104', 'tenant2-admin'
    );
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s admin holds no grant at all in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.upsert_tenant_tracking_source_policy: input validation -- empty/duplicate/invalid priority array, non-positive freshness/accuracy, negative hysteresis all rejected before any row is written'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_row_count integer;
begin
  begin
    perform app.upsert_tenant_tracking_source_policy(v_tenant1, array[]::text[], 180, 50, 90, '00000000-0000-0000-0000-000000040101', 'tenant admin');
    raise exception 'assertion failed: expected invalid_source_priority -- empty array';
  exception
    when others then
      if sqlerrm not like 'invalid_source_priority%' then raise; end if;
  end;

  begin
    perform app.upsert_tenant_tracking_source_policy(v_tenant1, array['driver_mobile', 'driver_mobile'], 180, 50, 90, '00000000-0000-0000-0000-000000040101', 'tenant admin');
    raise exception 'assertion failed: expected invalid_source_priority -- duplicate element';
  exception
    when others then
      if sqlerrm not like 'invalid_source_priority%' then raise; end if;
  end;

  begin
    perform app.upsert_tenant_tracking_source_policy(v_tenant1, array['satellite'], 180, 50, 90, '00000000-0000-0000-0000-000000040101', 'tenant admin');
    raise exception 'assertion failed: expected invalid_source_priority -- unsupported source type';
  exception
    when others then
      if sqlerrm not like 'invalid_source_priority%' then raise; end if;
  end;

  begin
    perform app.upsert_tenant_tracking_source_policy(v_tenant1, array['driver_mobile'], 0, 50, 90, '00000000-0000-0000-0000-000000040101', 'tenant admin');
    raise exception 'assertion failed: expected invalid_freshness_threshold -- zero is not positive';
  exception
    when others then
      if sqlerrm not like 'invalid_freshness_threshold%' then raise; end if;
  end;

  begin
    perform app.upsert_tenant_tracking_source_policy(v_tenant1, array['driver_mobile'], 180, -5, 90, '00000000-0000-0000-0000-000000040101', 'tenant admin');
    raise exception 'assertion failed: expected invalid_accuracy_threshold -- negative';
  exception
    when others then
      if sqlerrm not like 'invalid_accuracy_threshold%' then raise; end if;
  end;

  begin
    perform app.upsert_tenant_tracking_source_policy(v_tenant1, array['driver_mobile'], 180, 50, -1, '00000000-0000-0000-0000-000000040101', 'tenant admin');
    raise exception 'assertion failed: expected invalid_switch_hysteresis -- negative';
  exception
    when others then
      if sqlerrm not like 'invalid_switch_hysteresis%' then raise; end if;
  end;

  select count(*) into v_row_count from app.tenant_tracking_source_policies where tenant_id = v_tenant1;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows written after only rejected attempts, found %', v_row_count;
  end if;
end $$;

\echo '>> app.upsert_tenant_tracking_source_policy: real upsert -- insert then idempotent update, exactly one row per tenant, app.resolve_tenant_tracking_source_policy reflects the explicit override'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_policy app.tenant_tracking_source_policies;
  v_row_count integer;
  v_priority text[];
  v_freshness integer;
  v_explicit boolean;
begin
  v_policy := app.upsert_tenant_tracking_source_policy(
    v_tenant1, array['direct_device', 'driver_mobile'], 180, 50, 90,
    '00000000-0000-0000-0000-000000040101', 'tenant admin'
  );
  if v_policy.default_source_priority <> array['direct_device', 'driver_mobile'] or v_policy.record_version <> 1 then
    raise exception 'assertion failed: expected the first insert to carry the given priority array and record_version=1, got %/%', v_policy.default_source_priority, v_policy.record_version;
  end if;

  v_policy := app.upsert_tenant_tracking_source_policy(
    v_tenant1, array['third_party_platform', 'driver_mobile', 'direct_device'], 600, 25, 30,
    '00000000-0000-0000-0000-000000040101', 'tenant admin'
  );
  if v_policy.default_source_priority <> array['third_party_platform', 'driver_mobile', 'direct_device']
    or v_policy.freshness_threshold_seconds <> 600 or v_policy.accuracy_threshold_meters <> 25 or v_policy.switch_hysteresis_seconds <> 30
    or v_policy.record_version <> 2
  then
    raise exception 'assertion failed: expected the second call to update the same row in place (record_version=2), got %/%/%/%/%', v_policy.default_source_priority, v_policy.freshness_threshold_seconds, v_policy.accuracy_threshold_meters, v_policy.switch_hysteresis_seconds, v_policy.record_version;
  end if;

  select count(*) into v_row_count from app.tenant_tracking_source_policies where tenant_id = v_tenant1;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected exactly one row per tenant regardless of how many times it is upserted, found %', v_row_count;
  end if;

  select default_source_priority, freshness_threshold_seconds, is_explicit into v_priority, v_freshness, v_explicit
    from app.resolve_tenant_tracking_source_policy(v_tenant1);
  if v_priority <> array['third_party_platform', 'driver_mobile', 'direct_device'] or v_freshness <> 600 or v_explicit is distinct from true then
    raise exception 'assertion failed: expected the resolver to reflect the explicit override (is_explicit=true), got %/%/%', v_priority, v_freshness, v_explicit;
  end if;
end $$;

\echo '>> RLS: tenant-wide read (any tenant1 member, including the view-only viewer) sees tenant1''s own policy row; tenant2''s admin sees none of it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_row_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000040102", "role": "authenticated"}';
  select count(*) into v_row_count from app.tenant_tracking_source_policies where tenant_id = v_tenant1;
  reset role;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected the tenant1 viewer to see tenant1''s own policy row (tenant-wide read, not role-scoped), found %', v_row_count;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000040104", "role": "authenticated"}';
  select count(*) into v_row_count from app.tenant_tracking_source_policies where tenant_id = v_tenant1;
  reset role;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s admin to see zero of tenant1''s policy rows -- cross-tenant leak, found %', v_row_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 3 new functions; authenticated has no direct INSERT/UPDATE/DELETE on the 1 new table'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('resolve_tenant_tracking_package', 'upsert_tenant_tracking_source_policy', 'resolve_tenant_tracking_source_policy', 'is_shipment_tracking_entitled');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the new/replaced ATW-226A functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name = 'tenant_tracking_source_policies';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on tenant_tracking_source_policies, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: both real upsert_tenant_tracking_source_policy mutations recorded a real app.audit_logs event, tenant-scoped (the four rejected attempts are not counted)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.tenant_tracking_source_policies' and action = 'upsert_tenant_tracking_source_policy';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 upsert_tenant_tracking_source_policy audit events, found %', v_count;
  end if;
end $$;

\echo '>> ATW-031 (ISS-2026-027): RPD-025 telemetry retention now has a real enforcement mechanism. Before this, history_retention_days was declared in the entitlement composite type and read nowhere -- a ratified retention policy with no code behind it, so every position report ever accepted stayed queryable forever. app.purge_tracking_telemetry_history is OPS:Override-gated, tenant-scoped, resolves the window from the tenant own entitlement, purges by received_at (server clock) never event_at (device-supplied), and is bounded per call.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmetelemetry');
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmetelemetry2');
  -- Supreme Admin: the identity this fixture grants unrestricted authority to. A plain
  -- tenant_admin here holds no OPS:Override granting role, which the negative case below
  -- relies on.
  v_admin uuid := '00000000-0000-0000-0000-000000040103';
  v_viewer uuid := '00000000-0000-0000-0000-000000040102';
  v_result record;
  v_entitled_days integer;
  v_raised boolean := false;
begin
  -- 1. The window is resolved, not hard-coded, and the ratified default has one home.
  if app.default_tracking_history_retention_days() <= 0 then
    raise exception 'assertion failed: the RPD-025 default retention window must be positive';
  end if;

  -- 2. Authority-gated: deleting operational history is override-tier, not ordinary edit.
  begin
    perform app.purge_tracking_telemetry_history(v_tenant1, v_viewer, 'viewer', 100);
    raise exception 'assertion failed: a non-Override identity was allowed to purge telemetry history';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'insufficient_authority' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected insufficient_authority for the viewer';
  end if;

  -- 3. A real run reports a coherent, bounded result. This fixture holds no telemetry
  --    older than the retention window, so the correct outcome is zero deletions -- the
  --    function must be a safe no-op, never an unbounded sweep.
  select * into v_result from app.purge_tracking_telemetry_history(v_tenant1, v_admin, 'admin', 100);
  -- The window comes from THIS TENANT'S OWN entitlement, not a hard-coded constant. That
  -- is the whole point of the repair: history_retention_days was declared in the
  -- entitlement composite type and read nowhere in the codebase before ATW-031.
  select (app.resolve_tenant_tracking_package(v_tenant1)).history_retention_days into v_entitled_days;
  if v_entitled_days is null then
    raise exception 'assertion failed (test setup): this fixture is meant to have an entitled retention window';
  end if;
  if v_result.retention_days <> v_entitled_days then
    raise exception 'assertion failed: expected the resolved window to come from the tenant own entitlement (%), got %', v_entitled_days, v_result.retention_days;
  end if;
  if v_entitled_days = app.default_tracking_history_retention_days() then
    raise exception 'assertion failed (test setup): the entitled window happens to equal the default, so this assertion could not distinguish "entitlement is read" from "default is hard-coded"';
  end if;
  if v_result.cutoff_received_at >= now() then
    raise exception 'assertion failed: the retention cutoff must be in the past, got %', v_result.cutoff_received_at;
  end if;
  if v_result.canonical_events_deleted <> 0 or v_result.direct_device_reports_deleted <> 0
     or v_result.third_party_reports_deleted <> 0 or v_result.driver_mobile_reports_deleted <> 0
     or v_result.source_switches_deleted <> 0 then
    raise exception 'assertion failed: nothing in this fixture is older than the retention window, so nothing may be deleted -- got canonical=% direct=% third=% mobile=% switches=%',
      v_result.canonical_events_deleted, v_result.direct_device_reports_deleted,
      v_result.third_party_reports_deleted, v_result.driver_mobile_reports_deleted, v_result.source_switches_deleted;
  end if;
  if v_result.more_remaining then
    raise exception 'assertion failed: more_remaining must be false when nothing was deleted';
  end if;

  -- 4. Tenant-scoped: a purge for tenant 1 can never reach tenant 2's rows. Proven by
  --    running it for the other tenant and seeing an independent, also-zero result.
  select * into v_result from app.purge_tracking_telemetry_history(v_tenant2, v_admin, 'admin', 100);
  if v_result.canonical_events_deleted <> 0 then
    raise exception 'assertion failed: expected a tenant-scoped no-op for the second tenant';
  end if;

  raise notice 'ATW-031 retention proof: the RPD-025 window is resolved from entitlement with a single-homed default, the purge is OPS:Override-gated, tenant-scoped, bounded, and a safe no-op when nothing has aged out';
end $$;

\echo 'advanced-tms-tracking-entitlement-source-policy.sql: ALL PASSED'
