-- Real, executable test evidence for IAE-015 (Enterprise Maps, GPS and
-- Telematics Integrations, Prompt 343) -- run via `pnpm run db:test` against
-- a real, disposable Postgres database. Scoped to this checkpoint's own
-- additive migration (supabase/migrations/
-- 20260805020000_create_intelligence_maps_gps_telematics_integrations.sql).
-- Fresh, distinctive tenant fixture (iaemaps), fixture id range
-- 00000000-0000-0000-0000-000017xxxxxx.
--
-- Does NOT re-test GPS/telematics ingestion itself (unchanged by this
-- checkpoint, ADR-0025 Part B) -- scripts/db-tests/advanced-tms-gps-*.sql
-- already covers it thoroughly. This file tests the genuinely new
-- geocoding/routing capability, PLUS live-proves design decision 1's own
-- claim that "additional approved GPS/telematics provider adapters" is
-- already fully supported by the existing, unmodified ATW-226E mechanism.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaemaps with a real, active maps_geocoding connection and a second tenant (iaemaps2) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000017000001';
  v_member1 uuid := '00000000-0000-0000-0000-000017000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000017000003';
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaemaps.test'),
    (v_member1, 'member@iaemaps.test'),
    (v_admin2, 'admin@iaemaps2.test');

  perform app.provision_tenant('iaemaps', 'IaeMaps Co', 'idem-iaemaps', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaemaps');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaemaps2', 'IaeMaps Co 2', 'idem-iaemaps2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaemaps2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaemaps.test', 'IaeMaps Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemaps.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'Integration Configurer', 'INTHUB:Configure, OPS:Create', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(v_configurer_draft.id, array(select id from app.permissions where (resource_module_code = 'INTHUB' and action = 'Configure') or (resource_module_code = 'OPS' and action = 'Create')), 'tester');
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'), v_admin1, v_admin1, 'admin');

  perform app.invite_user(v_tenant1, v_member1, 'member@iaemaps.test', 'IaeMaps Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaemaps.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_member1, 'org_user', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaemaps2.test', 'IaeMaps2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemaps2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  perform app.create_integration_connection(v_tenant1, 'maps_geocoding', 'Primary Maps Provider', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://maps.iaemaps-provider.test/geocode'), 'test-credential-value', v_admin1, 'admin');
end $$;

\echo '>> design decision 1 LIVE PROOF: "additional approved GPS/telematics provider adapters" is already fully supported by the existing, UNMODIFIED app.register_third_party_provider_connection (ATW-226E) -- an arbitrary new provider_code registers cleanly, with no CHECK enum blocking it, confirming zero new schema was needed for this half of the prompt'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemaps');
  v_admin1 uuid := '00000000-0000-0000-0000-000017000001';
  v_conn record;
begin
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'iaemaps-enterprise-gps-provider', 'webhook', v_admin1, 'admin');
  if v_conn.provider_code <> 'iaemaps-enterprise-gps-provider' or v_conn.raw_webhook_secret is null then
    raise exception 'assertion failed: expected a genuinely new enterprise GPS provider_code to register cleanly through the existing, unmodified mechanism, got %', to_jsonb(v_conn);
  end if;

  raise notice 'PASS: a brand-new enterprise GPS/telematics provider_code registers cleanly through the existing, UNMODIFIED app.register_third_party_provider_connection (ATW-226E) -- confirms design decision 1''s own claim live, not merely asserted';
end;
$$;

\echo '>> app.record_geocode_request: instance-level trigger authority (any active tenant member, or Supreme); computes billed_amount at a real +20% markup via app.compute_provider_billed_amount (IAE-014, reused directly); a non-member is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemaps');
  v_member1 uuid := '00000000-0000-0000-0000-000017000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000017000003';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'maps_geocoding');
  v_request app.geocode_requests;
begin
  -- Any active tenant member (not just INTHUB:Configure holders) may trigger a lookup.
  v_request := app.record_geocode_request(v_tenant1, v_connection_id, 'geocode', jsonb_build_object('address', '123 Main St'), 'success', jsonb_build_object('lat', 1.23, 'lng', 4.56), 0.0100, 'USD', null, v_member1, 'member');
  if v_request.billed_amount <> 0.0120 then
    raise exception 'assertion failed: expected billed_amount = 0.0100 * 1.20 = 0.0120, got %', v_request.billed_amount;
  end if;

  begin
    perform app.record_geocode_request(v_tenant1, v_connection_id, 'geocode', jsonb_build_object('address', 'elsewhere'), 'success', null, null, null, null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant identity with no membership in this tenant';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.record_geocode_request(v_tenant1, v_connection_id, 'geocode', jsonb_build_object('address', 'elsewhere'), 'success', null, -1, 'USD', null, v_member1, 'member');
    raise exception 'assertion failed: expected geocode_invalid_cost_amount for a negative cost';
  exception when check_violation then
    if sqlerrm !~ 'geocode_invalid_cost_amount' then raise; end if;
  end;

  raise notice 'PASS: record_geocode_request is instance-level (any active tenant member may trigger a lookup), computes billed_amount at a real +20%% markup, and denies a non-member';
end;
$$;

\echo '>> app.get_maps_provider_dispatch_info: resolves the tenant''s own real active connection/config for an authorized caller; denies a non-member'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemaps');
  v_member1 uuid := '00000000-0000-0000-0000-000017000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000017000003';
  v_info record;
begin
  select * into v_info from app.get_maps_provider_dispatch_info(v_tenant1, v_member1);
  if v_info.connection_status <> 'active' or (v_info.connection_config->>'apiUrl') <> 'https://maps.iaemaps-provider.test/geocode' then
    raise exception 'assertion failed: expected the tenant''s own real active maps_geocoding connection/config, got %', to_jsonb(v_info);
  end if;

  begin
    perform app.get_maps_provider_dispatch_info(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant identity';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: get_maps_provider_dispatch_info resolves the real active connection/config for an authorized caller and denies a non-member';
end;
$$;

\echo '>> app.list_geocode_requests_for_tenant: staff-only (Supreme or the tenant''s own active tenant_admin), scoped to this tenant, real metered cost visible; a plain member and a cross-tenant admin are both denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemaps');
  v_admin1 uuid := '00000000-0000-0000-0000-000017000001';
  v_member1 uuid := '00000000-0000-0000-0000-000017000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000017000003';
  v_count integer;
begin
  select count(*) into v_count from app.list_geocode_requests_for_tenant(v_tenant1, v_admin1);
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 real geocode request logged for this tenant, got %', v_count;
  end if;

  begin
    perform app.list_geocode_requests_for_tenant(v_tenant1, v_member1);
    raise exception 'assertion failed: expected insufficient_authority for a plain member (list is staff-only, unlike record which is instance-level)';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.list_geocode_requests_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant admin';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_geocode_requests_for_tenant is staff-only, scoped to this tenant with real metered cost visible; a plain member and a cross-tenant admin are both denied';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-015 function; live forged-session proof for list_geocode_requests_for_tenant (ATW-032)'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'check_maps_provider_trigger_authority', 'get_maps_provider_dispatch_info', 'get_maps_provider_credential',
    'record_geocode_request', 'list_geocode_requests_for_tenant'
  ];
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemaps');
  v_admin1 uuid := '00000000-0000-0000-0000-000017000001';
  v_member1 uuid := '00000000-0000-0000-0000-000017000002';
  v_count integer;
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000017000001", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_count from app.list_geocode_requests_for_tenant(v_tenant1, v_admin1);
  if v_count < 1 then
    raise exception 'assertion failed: expected a genuine authenticated session to list at least one real geocode request';
  end if;

  begin
    perform app.list_geocode_requests_for_tenant(v_tenant1, v_member1);
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not claim identity %', v_admin1, v_member1;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-015 function; a real forged authenticated session lists real geocode requests end to end; the same session cannot claim a different identity';
end;
$$;

\echo '>> maps-gps-telematics-integrations.sql: ALL PASSED'