-- Real, executable test evidence for ATW-226I (CG-S10-ATW-007's family, Prompt 226's
-- closing decomposition child, "Deployment, observability, load, security, outage, and
-- recovery verification") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Two parts, mirroring this repository's own PLT-137 (integrated verification)/PLT-138
-- (hardening) precedent compressed into this one closing checkpoint (disclosed in
-- docs/build-log/phase-05/ATW-226I.md §2):
--
-- Part A (own tenant `acmerecovery`): regression evidence for this checkpoint's own new
-- repair -- app.ingest_third_party_provider_webhook_event's widened 10-consecutive-
-- signature-failure auto-disable (ADR-0011's exact threshold/pattern) plus the two new
-- app.disable_third_party_provider_connection/app.reenable_third_party_provider_
-- connection recovery RPCs.
--
-- Part B (own tenant `acmeintegrated`): representative cross-capability composition
-- evidence, not exhaustive re-implementation of any single `226` child's own
-- already-proven scope (the identical scope decision PLT-137 itself made) -- proves a
-- third_party_platform-sourced report (not direct_device, the only source `226G`'s own
-- file exercised through the geofence evaluator) still composes correctly through
-- arbitration (`226F`) -> geofence dwell -> milestone candidate (`226G`) -> confirm ->
-- tenant-wide read (`226H`) -> the widened public tracking projection (`226H`), plus a
-- combined cross-tenant isolation sweep spanning both this file's own two tenants and a
-- final repository-wide anon-grant-count tally (unchanged at 7 through every `226A`-`I`
-- widening).

\set ON_ERROR_STOP on

-- =============================================================================
-- Part A: app.disable_third_party_provider_connection / app.reenable_third_party_
-- provider_connection / the widened auto-disable branch of app.ingest_third_party_
-- provider_webhook_event.
-- =============================================================================

\echo '>> Part A setup: one tenant, an OPS:Edit admin, an OPS:View-only viewer, a foreign tenant''s own OPS:Edit admin, and one webhook-mode third-party connection mapped to one vehicle'
create temporary table recovery_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_view_role uuid;
  v_view_draft app.role_versions;
  v_vehicle_master uuid;
  v_conn record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000048101', 'admin@acmerecovery.test'),
    ('00000000-0000-0000-0000-000000048102', 'viewer@acmerecovery.test'),
    ('00000000-0000-0000-0000-000000048103', 'supreme@acmerecovery.test'),
    ('00000000-0000-0000-0000-000000048104', 'admin@acmerecoverytwo.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000048103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmerecovery', 'Acme Recovery Co', 'idem-acmerecovery', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmerecovery');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('acmerecoverytwo', 'Acme Recovery Co Two', 'idem-acmerecoverytwo', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmerecoverytwo');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000048101', 'admin@acmerecovery.test', 'Recovery Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmerecovery.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000048101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000048102', 'viewer@acmerecovery.test', 'Recovery Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmerecovery.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000048104', 'admin@acmerecoverytwo.test', 'Recovery Two Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmerecoverytwo.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000048104', 'tenant_admin', v_tenant2, null, 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Recovery Editor', 'OPS:Edit/Create', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'Create')), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000048101', '00000000-0000-0000-0000-000000048103', 'tester');

  v_view_role := (app.create_role(v_tenant1, 'Recovery Viewer', 'OPS:View only', 'tester')).id;
  v_view_draft := app.create_role_version(v_view_role, 'tester');
  perform app.set_role_version_permissions(v_view_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_view_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_view_role and status = 'published'), '00000000-0000-0000-0000-000000048102', '00000000-0000-0000-0000-000000048103', 'tester');

  v_edit_role := (app.create_role(v_tenant2, 'Recovery Two Editor', 'OPS:Edit/Create', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'Create')), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000048104', '00000000-0000-0000-0000-000000048103', 'tester');

  perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-RECOVERY-001', 'Recovery Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000048101', 'admin');
  v_vehicle_master := (select id from app.master_records where tenant_id = v_tenant1 and code = 'VEH-RECOVERY-001');
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle_master, 'acmerecoverygps', 'EXT-VEH-RECOVERY-001', '00000000-0000-0000-0000-000000048101', 'admin');

  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmerecoverygps', 'webhook', '00000000-0000-0000-0000-000000048101', 'admin');

  insert into recovery_test_state (key, value) values
    ('tenant1_id', v_tenant1::text),
    ('tenant2_id', v_tenant2::text),
    ('vehicle_master_id', v_vehicle_master::text),
    ('connection_id', v_conn.connection_id::text),
    ('webhook_secret', v_conn.raw_webhook_secret),
    ('admin_actor_id', '00000000-0000-0000-0000-000000048101'),
    ('viewer_actor_id', '00000000-0000-0000-0000-000000048102'),
    ('tenant2_admin_actor_id', '00000000-0000-0000-0000-000000048104');
end $$;

\echo '>> widened app.ingest_third_party_provider_webhook_event: exactly 10 consecutive signature-verification failures auto-disable the connection at the 10th (ADR-0011''s own exact threshold), never before it; a well-signed request against the now-disabled connection is rejected as connection_not_active, never silently accepted'
do $$
declare
  v_connection_id uuid := (select value::uuid from recovery_test_state where key = 'connection_id');
  v_secret text := (select value from recovery_test_state where key = 'webhook_secret');
  v_ts bigint;
  v_bad_signature text := 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
  v_payload text;
  v_result record;
  v_conn app.third_party_provider_connections;
  v_correct_signature text;
  i integer;
begin
  v_payload := jsonb_build_object('event_id', 'recovery-evt-bad', 'vehicle_id', 'EXT-VEH-RECOVERY-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;

  for i in 1..10 loop
    v_ts := extract(epoch from now())::bigint;
    select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'recovery-bad-client', v_payload, v_ts, v_bad_signature);
    if v_result.ingest_status <> 'invalid' then
      raise exception 'assertion failed: expected attempt % to be invalid (bad signature), got %', i, v_result.ingest_status;
    end if;
  end loop;

  select * into v_conn from app.third_party_provider_connections where id = v_connection_id;
  if v_conn.status <> 'disabled' or v_conn.consecutive_failure_count <> 10 or v_conn.auto_disabled_at is null or v_conn.disabled_reason <> 'consecutive_failure_threshold_exceeded' then
    raise exception 'assertion failed: expected auto-disable at exactly 10 consecutive signature failures, got status=% count=% auto_disabled_at=% reason=%',
      v_conn.status, v_conn.consecutive_failure_count, v_conn.auto_disabled_at, v_conn.disabled_reason;
  end if;

  -- CG-S10-ATW-027 (Finding 4 fix pass) note: the rate-limit count is now bound to
  -- connection_id, not just client_key (see that migration's own header) -- the 10
  -- consecutive signature failures immediately above already also pushed this exact
  -- connection_id's own rate-limit count to its own threshold. Backdating those rows
  -- out of the 15-minute rate-limit window isolates this test's own real subject (the
  -- connection-status check specifically, immediately below) from an unrelated,
  -- already-covered concern (rate limiting has its own dedicated regression coverage in
  -- scripts/db-tests/advanced-tms-third-party-provider-adapter.sql) -- the identical
  -- "simulate time passing via direct SQL, since no RPC exists to backdate a real
  -- clock, nor should one" technique this repository's own test suite already uses
  -- throughout (e.g. advanced-tms-canonical-telemetry-arbitration.sql's own
  -- received_at/switched_at backdating).
  update app.third_party_provider_ingestion_attempts set occurred_at = now() - interval '20 minutes' where connection_id = v_connection_id;

  -- A fresh client_key, bypassing the unrelated per-client_key rate limiter, with a
  -- CORRECT signature -- proves the connection's own disabled status blocks ingestion
  -- at the connection-status check, not merely that bad signatures keep failing.
  v_ts := extract(epoch from now())::bigint;
  v_correct_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'recovery-good-client', v_payload, v_ts, v_correct_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected a well-signed request against a disabled connection to be rejected (connection_not_active), got %', v_result.ingest_status;
  end if;
  if not exists (
    select 1 from app.third_party_provider_ingestion_attempts
    where connection_id = v_connection_id and client_key = 'recovery-good-client' and result = 'invalid' and reason = 'connection_not_active'
  ) then
    raise exception 'assertion failed: expected the well-signed rejection to be recorded with reason=connection_not_active';
  end if;
end $$;

\echo '>> app.reenable_third_party_provider_connection: unauthorized (OPS:View-only) rejected; authorized reset clears auto_disabled_at/disabled_reason and consecutive_failure_count, captures a real audit event, and ingestion succeeds again'
do $$
declare
  v_connection_id uuid := (select value::uuid from recovery_test_state where key = 'connection_id');
  v_tenant1 uuid := (select value::uuid from recovery_test_state where key = 'tenant1_id');
  v_admin uuid := (select value::uuid from recovery_test_state where key = 'admin_actor_id');
  v_viewer uuid := (select value::uuid from recovery_test_state where key = 'viewer_actor_id');
  v_secret text := (select value from recovery_test_state where key = 'webhook_secret');
  v_rejected boolean := false;
  v_updated app.third_party_provider_connections;
  v_audit_count integer;
  v_ts bigint;
  v_payload text;
  v_signature text;
  v_result record;
begin
  begin
    perform app.reenable_third_party_provider_connection(v_connection_id, v_viewer, 'viewer');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected an OPS:View-only actor to be rejected reenabling a connection';
  end if;

  select * into v_updated from app.reenable_third_party_provider_connection(v_connection_id, v_admin, 'admin');
  if v_updated.status <> 'active' or v_updated.consecutive_failure_count <> 0 or v_updated.auto_disabled_at is not null or v_updated.disabled_reason is not null then
    raise exception 'assertion failed: expected a fully reset connection after reenable, got status=% count=% auto_disabled_at=% reason=%',
      v_updated.status, v_updated.consecutive_failure_count, v_updated.auto_disabled_at, v_updated.disabled_reason;
  end if;

  select count(*) into v_audit_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.third_party_provider_connections' and action = 'reenable_third_party_provider_connection';
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 reenable audit event (a real human-actor mutation, unlike the automated auto-disable path), found %', v_audit_count;
  end if;

  v_ts := extract(epoch from now())::bigint;
  v_payload := jsonb_build_object('event_id', 'recovery-evt-after-reenable', 'vehicle_id', 'EXT-VEH-RECOVERY-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'recovery-post-reenable-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected ingestion to succeed again after reenable, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.disable_third_party_provider_connection: unauthorized rejected; a manual disable while healthy is idempotent-safe on a second call (no duplicate audit event); cross-tenant isolation -- a foreign tenant''s own OPS:Edit admin cannot disable/reenable this tenant''s own connection'
do $$
declare
  v_connection_id uuid := (select value::uuid from recovery_test_state where key = 'connection_id');
  v_tenant1 uuid := (select value::uuid from recovery_test_state where key = 'tenant1_id');
  v_admin uuid := (select value::uuid from recovery_test_state where key = 'admin_actor_id');
  v_viewer uuid := (select value::uuid from recovery_test_state where key = 'viewer_actor_id');
  v_tenant2_admin uuid := (select value::uuid from recovery_test_state where key = 'tenant2_admin_actor_id');
  v_rejected boolean := false;
  v_updated app.third_party_provider_connections;
  v_repeat app.third_party_provider_connections;
  v_audit_count integer;
begin
  begin
    perform app.disable_third_party_provider_connection(v_connection_id, 'suspected compromise', v_viewer, 'viewer');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected an OPS:View-only actor to be rejected disabling a connection';
  end if;

  select * into v_updated from app.disable_third_party_provider_connection(v_connection_id, 'suspected compromise', v_admin, 'admin');
  if v_updated.status <> 'disabled' or v_updated.disabled_reason <> 'suspected compromise' then
    raise exception 'assertion failed: expected a manual disable to set status=disabled and the caller-supplied reason, got status=% reason=%', v_updated.status, v_updated.disabled_reason;
  end if;

  select * into v_repeat from app.disable_third_party_provider_connection(v_connection_id, 'a different reason', v_admin, 'admin');
  if v_repeat.disabled_reason <> 'suspected compromise' then
    raise exception 'assertion failed: expected an idempotent re-disable to leave the original reason untouched, got %', v_repeat.disabled_reason;
  end if;

  select count(*) into v_audit_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.third_party_provider_connections' and action = 'disable_third_party_provider_connection';
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 disable audit event (idempotent re-disable captures none), found %', v_audit_count;
  end if;

  v_rejected := false;
  begin
    perform app.reenable_third_party_provider_connection(v_connection_id, v_tenant2_admin, 'admin');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a foreign tenant''s own OPS:Edit admin to be rejected reenabling this tenant''s own connection';
  end if;

  v_rejected := false;
  begin
    perform app.disable_third_party_provider_connection(v_connection_id, 'cross-tenant probe', v_tenant2_admin, 'admin');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a foreign tenant''s own OPS:Edit admin to be rejected disabling this tenant''s own connection';
  end if;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on either new recovery function; authenticated holds both; the repository-wide anon-grant count is unaffected by this checkpoint''s own two new functions'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon'
    and routine_name in ('disable_third_party_provider_connection', 'reenable_third_party_provider_connection');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon grants on the two new recovery functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'authenticated'
    and routine_name in ('disable_third_party_provider_connection', 'reenable_third_party_provider_connection');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both new recovery functions to be authenticated-callable, found %', v_count;
  end if;
end $$;

-- =============================================================================
-- Part B: representative cross-capability composition -- a third_party_platform-
-- sourced report through arbitration (226F) -> geofence dwell -> milestone candidate
-- (226G) -> confirm -> tenant-wide read (226H) -> the widened public tracking
-- projection (226H).
-- =============================================================================

\echo '>> Part B setup: a second tenant, a confirmed land-freight Shipment Order with a two-stop dispatched leg, an active tracking policy with a geofence_policy, and a webhook-mode third-party connection mapped to the assigned vehicle -- no direct_device involved, unlike 226G''s own file, which only ever drove the geofence evaluator through a direct_device report'
create temporary table integ_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
  v_leg app.shipment_legs;
  v_pickup_stop app.shipment_leg_stops;
  v_delivery_stop app.shipment_leg_stops;
  v_vehicle app.vehicle_operational_profiles;
  v_conn record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000048201', 'admin@acmeintegrated.test'),
    ('00000000-0000-0000-0000-000000048203', 'supreme@acmeintegrated.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000048203', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeintegrated', 'Acme Integrated Co', 'idem-acmeintegrated', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeintegrated');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEINTEGRATED-CO', 'Acme Integrated Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINTEGRATED-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000048201', 'admin@acmeintegrated.test', 'Integ Admin', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeintegrated.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000048201', 'tenant_admin', v_tenant1, null, 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Integ Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000048201', '00000000-0000-0000-0000-000000048203', 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-INTEG-A', 'Integ Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000048201', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, true, v_vehicle.record_version, '00000000-0000-0000-0000-000000048201', 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Integrated Co', 'Jane Integ', 'jane@integratedtest.test', '0811',
    '00000000-0000-0000-0000-000000048201', v_team_a, '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_lead from app.leads where email = 'jane@integratedtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Integrated Co', 'CTC226I', '11.111.111.9-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 9', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Integ Ops', 'Procurement Lead', 'jane@integratedtest.test', '0811', '00000000-0000-0000-0000-000000048201', v_team_a, '00000000-0000-0000-0000-000000048201', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000048201', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Integrated test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000048201', v_team_a, '00000000-0000-0000-0000-000000048201', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CTC226I-1', 'Contoso Integrated Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000048201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000048201', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000048201', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000048201', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000048201', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000048201', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Integrated tracking lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000048201', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000048201', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Integ Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000048201', 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000048201', 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000048201', 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000048201', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-integ-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, '00000000-0000-0000-0000-000000048201', 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000048201', 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-integ-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000048201', 'admin');
  select * into v_pickup_stop from app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), '00000000-0000-0000-0000-000000048201', 'admin');
  select * into v_delivery_stop from app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', '00000000-0000-0000-0000-000000048201', 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 1000, 1000, 16, '00000000-0000-0000-0000-000000048201', 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000048201', 'admin');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000048201', 'admin');

  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, '00000000-0000-0000-0000-000000048201', 'admin');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['third_party_platform'], 'third_party_platform', array['third_party_platform'],
    300, 100, 30, 'leg_dispatch', 'leg_complete',
    jsonb_build_object(
      'enabled', true, 'radius_meters', 500, 'dwell_seconds_before_confirm', 60,
      'route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 120),
      'overdue_arrival_grace_minutes', 60
    ),
    true, 3600, '00000000-0000-0000-0000-000000048201', 'admin'
  );

  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle.vehicle_master_id, 'acmeintegratedgps', 'EXT-VEH-INTEG-001', '00000000-0000-0000-0000-000000048201', 'admin');
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmeintegratedgps', 'webhook', '00000000-0000-0000-0000-000000048201', 'admin');

  insert into integ_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('shipment_order_id', v_shipment.id::text),
    ('shipment_number', v_shipment.shipment_number),
    ('leg_id', v_leg.id::text),
    ('pickup_stop_id', v_pickup_stop.id::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('connection_id', v_conn.connection_id::text),
    ('webhook_secret', v_conn.raw_webhook_secret),
    ('admin_actor_id', '00000000-0000-0000-0000-000000048201');
end $$;

\echo '>> composition: a third_party_platform-sourced report inside the pickup geofence, sustained past dwell_seconds_before_confirm, produces exactly one pending milestone candidate -- proving 226G''s geofence evaluator (previously only ever exercised through a direct_device report) composes correctly through the widened, now auto-disable-aware, third-party ingestion path'
do $$
declare
  v_connection_id uuid := (select value::uuid from integ_test_state where key = 'connection_id');
  v_secret text := (select value from integ_test_state where key = 'webhook_secret');
  v_tenant1 uuid := (select value::uuid from integ_test_state where key = 'tenant_id');
  v_vehicle_id uuid := (select value::uuid from integ_test_state where key = 'vehicle_master_id');
  v_ts bigint;
  v_payload text;
  v_signature text;
  v_result record;
  v_candidate_count integer;
begin
  -- First report inside the pickup radius -- pending-dwell, no candidate yet.
  v_ts := extract(epoch from now())::bigint;
  v_payload := jsonb_build_object(
    'event_id', 'integ-evt-1', 'vehicle_id', 'EXT-VEH-INTEG-001', 'event_type', 'location',
    'timestamp', now()::text, 'latitude', -6.208763, 'longitude', 106.845599
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'integ-client-1', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the first geofence report to be accepted, got %', v_result.ingest_status;
  end if;

  -- Second report, still inside, event_at past the dwell threshold -- confirms the stop.
  v_ts := extract(epoch from (now() + interval '90 seconds'))::bigint;
  v_payload := jsonb_build_object(
    'event_id', 'integ-evt-2', 'vehicle_id', 'EXT-VEH-INTEG-001', 'event_type', 'location',
    'timestamp', (now() + interval '90 seconds')::text, 'latitude', -6.208763, 'longitude', 106.845599
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'integ-client-1', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the dwell-confirming geofence report to be accepted, got %', v_result.ingest_status;
  end if;

  select count(*) into v_candidate_count from app.shipment_milestone_candidates where tenant_id = v_tenant1 and status = 'pending';
  if v_candidate_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 pending milestone candidate from the third-party-sourced geofence dwell, found %', v_candidate_count;
  end if;

  select * into v_result from app.get_vehicle_current_position(v_vehicle_id);
  if v_result.source_type <> 'third_party_platform' then
    raise exception 'assertion failed: expected the current position to be sourced from third_party_platform, got %', v_result.source_type;
  end if;
end $$;

\echo '>> composition continues: confirming the candidate produces a real app.milestone_events row; app.get_tenant_pending_milestone_candidates (226H) drops to zero for this tenant; the widened app.lookup_public_shipment_tracking (226H/OPS-180) reflects both the confirmed milestone and a live sanitized position, all sourced end to end from the third-party path'
do $$
declare
  v_tenant1 uuid := (select value::uuid from integ_test_state where key = 'tenant_id');
  v_shipment_order_id uuid := (select value::uuid from integ_test_state where key = 'shipment_order_id');
  v_shipment_number text := (select value from integ_test_state where key = 'shipment_number');
  v_admin uuid := (select value::uuid from integ_test_state where key = 'admin_actor_id');
  v_candidate app.shipment_milestone_candidates;
  v_event app.milestone_events;
  v_pending_count integer;
  v_issue record;
  v_lookup record;
  v_milestone_found boolean := false;
  v_m jsonb;
begin
  select * into v_candidate from app.shipment_milestone_candidates where tenant_id = v_tenant1 and status = 'pending';
  select * into v_event from app.confirm_milestone_candidate(v_candidate.id, v_admin, 'admin', null, false);
  if v_event.id is null or v_event.source <> 'system' then
    raise exception 'assertion failed: expected a real app.milestone_events row with source=system, got %', v_event;
  end if;

  select count(*) into v_pending_count from app.get_tenant_pending_milestone_candidates(v_tenant1, v_admin, 50);
  if v_pending_count <> 0 then
    raise exception 'assertion failed: expected zero pending milestone candidates after confirm, found %', v_pending_count;
  end if;

  select * into v_issue from app.issue_shipment_tracking_token(v_shipment_order_id, 24, v_admin, 'admin');
  select * into v_lookup from app.lookup_public_shipment_tracking(v_issue.raw_token, 'integ-public-client');
  if v_lookup.lookup_status <> 'ok' or v_lookup.shipment_number <> v_shipment_number then
    raise exception 'assertion failed: expected a real ok lookup for %, got %', v_shipment_number, v_lookup;
  end if;
  if v_lookup.vehicle_position_geojson is null or v_lookup.vehicle_position_status <> 'live' then
    raise exception 'assertion failed: expected a live sanitized vehicle position sourced end to end from the third-party path, got status=%', v_lookup.vehicle_position_status;
  end if;

  for v_m in select * from jsonb_array_elements(v_lookup.milestones) loop
    if (v_m ->> 'code') = 'pickup_arrival' then
      v_milestone_found := true;
    end if;
  end loop;
  if not v_milestone_found then
    raise exception 'assertion failed: expected the newly confirmed pickup_arrival milestone to appear in the public tracking projection''s own milestones array, got %', v_lookup.milestones;
  end if;
end $$;

\echo '>> combined cross-tenant isolation sweep: one query spanning app.third_party_provider_connections/app.shipment_milestone_candidates/app.vehicle_current_positions, scoped to each of this file''s own two tenants in turn, confirms zero rows leak across (Part A''s acmerecovery vs. Part B''s acmeintegrated)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from recovery_test_state where key = 'tenant1_id');
  v_tenant2 uuid := (select value::uuid from integ_test_state where key = 'tenant_id');
  v_leak_count integer;
begin
  select count(*) into v_leak_count from app.third_party_provider_connections where tenant_id = v_tenant2 and id = (select value::uuid from recovery_test_state where key = 'connection_id');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: Part A''s own connection must never be visible under Part B''s own tenant_id, found %', v_leak_count;
  end if;

  select count(*) into v_leak_count from app.shipment_milestone_candidates where tenant_id = v_tenant1;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: Part A''s own tenant created no shipment/milestone data at all -- expected zero milestone candidates under acmerecovery''s own tenant_id, found %', v_leak_count;
  end if;

  select count(*) into v_leak_count from app.vehicle_current_positions where tenant_id = v_tenant1;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: Part A''s own tenant never ingested a location report -- expected zero vehicle_current_positions rows under acmerecovery''s own tenant_id, found %', v_leak_count;
  end if;

  select count(*) into v_leak_count from app.vehicle_current_positions where tenant_id = v_tenant2 and vehicle_master_id = (select value::uuid from recovery_test_state where key = 'vehicle_master_id');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: Part A''s own vehicle must never appear under Part B''s own tenant_id, found %', v_leak_count;
  end if;
end $$;

\echo '>> final repository-wide tally (ATW-226A through ATW-226I): the anon-grant count remains exactly 7 -- unchanged through every widening this entire family made, including this closing checkpoint''s own two new authenticated-only recovery functions'
do $$
declare
  v_count integer;
begin
  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  if v_count <> 7 then
    raise exception 'assertion failed: expected exactly 7 distinct anon-granted functions repository-wide at the close of the 226 family, found %', v_count;
  end if;
end $$;

drop table recovery_test_state;
drop table integ_test_state;

\echo 'ALL ATW-226I db-test assertions passed.'
