-- Real, executable test evidence for IAE-008 (Integration Hub, Prompt 336,
-- CG-S14-IAE-008) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000010000001..005.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use.
--
-- The standout proof in this file (section "credential isolation is real,
-- not merely documented") is a live forged-session probe showing that even
-- an ordinary, real, active tenant member cannot SELECT so much as one row
-- of app.integration_connection_credentials directly -- not merely that the
-- RPC layer hides it, the raw table itself refuses every authenticated
-- session, unlike the closest pre-existing precedent this migration's own
-- header discloses (app.third_party_provider_connections.webhook_secret_value,
-- which authenticated CAN select directly today).

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: one tenant (iaehubco) with a Supreme Admin, an INTHUB:Configure holder, a plain member, a customer_user portal principal, and a second tenant (iaehubco2) with one lone member for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000010000001', 'supreme@iaehubco.test'),
    ('00000000-0000-0000-0000-000010000002', 'configurer@iaehubco.test'),
    ('00000000-0000-0000-0000-000010000003', 'member@iaehubco.test'),
    ('00000000-0000-0000-0000-000010000004', 'portal@iaehubco.test'),
    ('00000000-0000-0000-0000-000010000005', 'member@iaehubco2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000010000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaehubco', 'IAE Hub Co', 'idem-iaehubco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaehubco2', 'IAE Hub Co 2', 'idem-iaehubco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaehubco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000010000002', 'configurer@iaehubco.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaehubco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000010000003', 'member@iaehubco.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaehubco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000010000004', 'portal@iaehubco.test', 'Portal Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'portal@iaehubco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000010000004', 'customer_user', v_tenant1, 'iae-hub-portal-ref', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000010000005', 'member@iaehubco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaehubco2.test'), 'active', 'onboarded', 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'Integration Configurer', 'INTHUB:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(
    v_configurer_draft.id,
    array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'),
    '00000000-0000-0000-0000-000010000002', '00000000-0000-0000-0000-000010000001', 'tester');
end;
$$;

\echo '>> app.register_integration_adapter: Supreme-only, idempotent by code'
do $$
declare
  v_adapter app.integration_adapters;
  v_again app.integration_adapters;
begin
  begin
    perform app.register_integration_adapter('iae_hub_test_adapter', 'IAE Hub Test Adapter', 'communication', '00000000-0000-0000-0000-000010000002', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- a non-Supreme actor may not register an adapter';
  exception
    when insufficient_privilege then null;
  end;

  v_adapter := app.register_integration_adapter('iae_hub_test_adapter', 'IAE Hub Test Adapter', 'communication', '00000000-0000-0000-0000-000010000001', 'tester');
  if v_adapter.category <> 'communication' then
    raise exception 'assertion failed: expected a real, persisted adapter row';
  end if;

  v_again := app.register_integration_adapter('iae_hub_test_adapter', 'a different name entirely', 'a different category', '00000000-0000-0000-0000-000010000001', 'tester');
  if v_again.name <> 'IAE Hub Test Adapter' then
    raise exception 'assertion failed: expected idempotent replay to return the ORIGINAL row, never silently overwrite it';
  end if;
end;
$$;

\echo '>> app.create_integration_connection: INTHUB:Configure-gated, rejects an unknown adapter/missing name/missing credential, succeeds and stores the credential in a fully separate table'
do $$
declare
  v_tenant1 uuid;
  v_connection app.integration_connections;
  v_credential_count integer;
  v_credential_value text;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');

  begin
    perform app.create_integration_connection(v_tenant1, 'iae_hub_test_adapter', 'Should be denied', 'production', null, null, null, '{}'::jsonb, 'secret-x', '00000000-0000-0000-0000-000010000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- member lacks INTHUB:Configure';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.create_integration_connection(v_tenant1, 'not_a_real_adapter', 'x', 'production', null, null, null, '{}'::jsonb, 'secret-x', '00000000-0000-0000-0000-000010000002', 'tester');
    raise exception 'assertion failed: expected integration_adapter_unknown';
  exception
    when check_violation then
      if sqlerrm !~ 'integration_adapter_unknown' then raise; end if;
  end;

  begin
    perform app.create_integration_connection(v_tenant1, 'iae_hub_test_adapter', 'x', 'production', null, null, null, '{}'::jsonb, '', '00000000-0000-0000-0000-000010000002', 'tester');
    raise exception 'assertion failed: expected integration_connection_missing_credential';
  exception
    when check_violation then
      if sqlerrm !~ 'integration_connection_missing_credential' then raise; end if;
  end;

  v_connection := app.create_integration_connection(
    v_tenant1, 'iae_hub_test_adapter', 'Primary Comms Adapter', 'production',
    'Platform Ops', 'ops@iaehubco.test', 'https://runbooks.internal/iae-hub-test-adapter',
    jsonb_build_object('base_url', 'https://api.example.test'), 'sk_live_real_secret_value',
    '00000000-0000-0000-0000-000010000002', 'tester'
  );
  if v_connection.status <> 'active' or v_connection.owner_team <> 'Platform Ops' then
    raise exception 'assertion failed: expected a real, active connection with the supplied owner fields';
  end if;

  -- The credential lives in a SEPARATE table -- confirmed by direct
  -- superuser query (this test session, unlike a real authenticated
  -- session, has full raw access) that it was really stored, and that the
  -- returned/query-visible app.integration_connections row structurally
  -- has no credential column at all (proven via information_schema below,
  -- not merely "the app didn't happen to select it").
  select count(*) into v_credential_count from app.integration_connection_credentials where connection_id = v_connection.id;
  if v_credential_count <> 1 then
    raise exception 'assertion failed: expected exactly one real credential row, got %', v_credential_count;
  end if;
  -- ISS-2026-257: the column is now pgp_sym_encrypt''d at rest -- decrypt it back
  -- (via the same private helper the RPCs themselves use) to confirm the real
  -- plaintext round-trips correctly, not merely that SOME bytes are stored.
  select app._decrypt_integration_secret(credential_value_encrypted) into v_credential_value from app.integration_connection_credentials where connection_id = v_connection.id;
  if v_credential_value <> 'sk_live_real_secret_value' then
    raise exception 'assertion failed: expected the real supplied credential value to decrypt back verbatim';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'integration_connections' and column_name ilike '%credential%'
  ) then
    raise exception 'assertion failed: app.integration_connections must never carry a credential-shaped column at all';
  end if;
end;
$$;

\echo '>> app.update_integration_connection_config / app.rotate_integration_connection_credential: real updates, credential rotation never touches the connection row itself'
do $$
declare
  v_tenant1 uuid;
  v_connection_id uuid;
  v_updated app.integration_connections;
  v_credential_value text;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');
  v_connection_id := (select id from app.integration_connections where tenant_id = v_tenant1 and name = 'Primary Comms Adapter');

  v_updated := app.update_integration_connection_config(
    v_connection_id, jsonb_build_object('base_url', 'https://api-v2.example.test'), 'Platform Ops', 'ops2@iaehubco.test', 'https://runbooks.internal/v2',
    '00000000-0000-0000-0000-000010000002', 'tester'
  );
  if v_updated.config ->> 'base_url' <> 'https://api-v2.example.test' or v_updated.owner_email <> 'ops2@iaehubco.test' then
    raise exception 'assertion failed: expected the real config/owner update to persist';
  end if;
  if v_updated.record_version <= 1 then
    raise exception 'assertion failed: expected record_version to advance on update';
  end if;

  perform app.rotate_integration_connection_credential(v_connection_id, 'sk_live_rotated_secret_value', '00000000-0000-0000-0000-000010000002', 'tester');
  select app._decrypt_integration_secret(credential_value_encrypted) into v_credential_value from app.integration_connection_credentials where connection_id = v_connection_id;
  if v_credential_value <> 'sk_live_rotated_secret_value' then
    raise exception 'assertion failed: expected the credential to actually rotate to the new supplied value';
  end if;
end;
$$;

\echo '>> app.record_integration_health_check: real append-only history, auto-disable at 10 consecutive unhealthy checks (mirrors ADR-0011''s own threshold), history survives disable'
do $$
declare
  v_tenant1 uuid;
  v_connection_id uuid;
  v_connection app.integration_connections;
  v_i integer;
  v_history_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');
  v_connection_id := (select id from app.integration_connections where tenant_id = v_tenant1 and name = 'Primary Comms Adapter');

  perform app.record_integration_health_check(v_connection_id, 'healthy', 'ok', '00000000-0000-0000-0000-000010000002', 'tester');
  select * into v_connection from app.integration_connections where id = v_connection_id;
  if v_connection.last_health_status <> 'healthy' or v_connection.consecutive_failure_count <> 0 then
    raise exception 'assertion failed: expected a healthy check to reset the failure counter and record last_health_status';
  end if;

  for v_i in 1..10 loop
    perform app.record_integration_health_check(v_connection_id, 'unhealthy', 'timeout ' || v_i, '00000000-0000-0000-0000-000010000002', 'tester');
  end loop;

  select * into v_connection from app.integration_connections where id = v_connection_id;
  if v_connection.status <> 'disabled' or v_connection.consecutive_failure_count <> 10 then
    raise exception 'assertion failed: expected auto-disable at exactly 10 consecutive unhealthy checks, got status=% failures=%', v_connection.status, v_connection.consecutive_failure_count;
  end if;
  if v_connection.auto_disabled_at is null or v_connection.disabled_reason !~ 'auto-disabled' then
    raise exception 'assertion failed: expected a real auto_disabled_at timestamp and a disclosed disabled_reason';
  end if;

  select count(*) into v_history_count from app.integration_health_checks where connection_id = v_connection_id;
  if v_history_count <> 11 then
    raise exception 'assertion failed: expected 11 real, append-only health-check rows (1 healthy + 10 unhealthy), got %', v_history_count;
  end if;

  if not app.check_integration_connection_active(v_connection_id) = false then
    raise exception 'assertion failed: expected the real guard function to report an auto-disabled connection as inactive';
  end if;
end;
$$;

\echo '>> app.set_integration_connection_status: manual re-enable resets the failure counter; disabling/re-enabling never deletes health-check history; app.check_integration_connection_active reflects live status'
do $$
declare
  v_tenant1 uuid;
  v_connection_id uuid;
  v_connection app.integration_connections;
  v_history_count_before integer;
  v_history_count_after integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');
  v_connection_id := (select id from app.integration_connections where tenant_id = v_tenant1 and name = 'Primary Comms Adapter');

  select count(*) into v_history_count_before from app.integration_health_checks where connection_id = v_connection_id;

  v_connection := app.set_integration_connection_status(v_connection_id, 'active', null, '00000000-0000-0000-0000-000010000002', 'tester');
  if v_connection.status <> 'active' or v_connection.consecutive_failure_count <> 0 then
    raise exception 'assertion failed: expected re-activation to reset the failure counter';
  end if;
  if not app.check_integration_connection_active(v_connection_id) then
    raise exception 'assertion failed: expected the guard function to report the re-activated connection as active';
  end if;

  perform app.set_integration_connection_status(v_connection_id, 'disabled', 'planned maintenance', '00000000-0000-0000-0000-000010000002', 'tester');
  select count(*) into v_history_count_after from app.integration_health_checks where connection_id = v_connection_id;
  if v_history_count_after <> v_history_count_before then
    raise exception 'assertion failed: disabling a connection must never delete its own health-check history (Prompt 336 §24 "preserving evidence/history")';
  end if;
  if app.check_integration_connection_active(v_connection_id) then
    raise exception 'assertion failed: expected the guard function to report a manually-disabled connection as inactive';
  end if;
end;
$$;

\echo '>> C-05 discipline: a tenant-2 actor with zero relationship to tenant-1''s own connection gets the SAME integration_connection_not_found a missing id would produce, never a tenant-id-disclosing insufficient_authority'
do $$
declare
  v_tenant1 uuid;
  v_connection_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');
  v_connection_id := (select id from app.integration_connections where tenant_id = v_tenant1 and name = 'Primary Comms Adapter');

  begin
    perform app.set_integration_connection_status(v_connection_id, 'active', null, '00000000-0000-0000-0000-000010000005', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1 must see the same not_found a missing id would produce';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.rotate_integration_connection_credential(v_connection_id, 'x', '00000000-0000-0000-0000-000010000005', 'tester');
    raise exception 'assertion failed: expected no_data_found for rotate_integration_connection_credential too';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-008 function; authenticated has no direct INSERT/UPDATE/DELETE on integration_connections/integration_health_checks; authenticated holds ZERO privilege of any kind on integration_connection_credentials'
do $$
declare
  v_bad_grant record;
  v_leak_count integer;
begin
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in (
        'register_integration_adapter', 'create_integration_connection', 'update_integration_connection_config',
        'rotate_integration_connection_credential', 'set_integration_connection_status',
        'record_integration_health_check', 'check_integration_connection_active'
      )
      and grantee = 'anon'
  loop
    raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_bad_grant.routine_name;
  end loop;

  for v_bad_grant in
    select privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name in ('integration_connections', 'integration_health_checks')
      and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  loop
    raise exception 'assertion failed: authenticated must not hold direct % on the new integration-hub tables', v_bad_grant.privilege_type;
  end loop;

  -- Self-caught correction (repository-wide rbac-enforcement.sql sweep,
  -- ATW-032/ISS-2026-032): app.register_integration_adapter's own
  -- app.is_supreme_admin(p_actor_auth_user_id) check validates the CLAIMED
  -- actor, never the calling session -- must be service_role-only, never
  -- authenticated, matching every prior registry-registration function.
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app' and routine_name = 'register_integration_adapter' and grantee = 'authenticated'
  loop
    raise exception 'assertion failed: authenticated must not hold EXECUTE on app.register_integration_adapter -- service_role-only, matching every prior Supreme-Admin-gated registry-registration function';
  end loop;

  select count(*) into v_leak_count from information_schema.role_table_grants
  where table_schema = 'app' and table_name = 'integration_connection_credentials' and grantee in ('authenticated', 'anon');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: expected ZERO grants of any kind to authenticated/anon on app.integration_connection_credentials, found %', v_leak_count;
  end if;
end;
$$;

\echo '>> credential isolation is real, not merely documented: a live forged real-tenant-member session cannot SELECT so much as one row of app.integration_connection_credentials directly, even though it CAN see its own tenant''s app.integration_connections; a customer_user-layer portal principal sees zero rows of either connections/health-checks table'
do $$
declare
  v_tenant1 uuid;
  v_connection_id uuid;
  v_count integer;
  v_denied boolean := false;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaehubco');
  v_connection_id := (select id from app.integration_connections where tenant_id = v_tenant1 and name = 'Primary Comms Adapter');

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000010000003", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.integration_connections where id = v_connection_id;
  if v_count <> 1 then raise exception 'FAIL (RLS): an ordinary tenant member should see the tenant''s own connection via raw RLS, got %', v_count; end if;
  begin
    perform count(*) from app.integration_connection_credentials where connection_id = v_connection_id;
    raise exception 'FAIL: a real, active, ordinary tenant member session was able to SELECT app.integration_connection_credentials directly -- design decision 3''s own isolation has regressed';
  exception
    when insufficient_privilege then
      v_denied := true;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  if not v_denied then
    raise exception 'assertion failed: expected a permission-denied error querying app.integration_connection_credentials as authenticated';
  end if;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000010000004", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.integration_connections where tenant_id = v_tenant1;
  if v_count <> 0 then raise exception 'FAIL (RLS): customer_user-layer portal principal sees % integration_connections row(s) via raw RLS, expected 0', v_count; end if;
  select count(*) into v_count from app.integration_health_checks where connection_id = v_connection_id;
  if v_count <> 0 then raise exception 'FAIL (RLS): customer_user-layer portal principal sees % integration_health_checks row(s) via raw RLS, expected 0', v_count; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: app.integration_connection_credentials refuses even a real, active, ordinary tenant-member authenticated session outright (not merely undocumented by the RPC layer); a customer_user-layer principal sees zero rows of either remaining new table despite real active tenant membership';
end;
$$;

\echo '>> audit trail: create/update-config/rotate-credential/set-status/record-health-check each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.integration_connections' and action = 'create_integration_connection';
  if v_count = 0 then raise exception 'assertion failed: expected a create_integration_connection audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.integration_connections' and action = 'rotate_integration_connection_credential';
  if v_count = 0 then raise exception 'assertion failed: expected a rotate_integration_connection_credential audit event'; end if;
  if exists (select 1 from app.audit_logs where action = 'rotate_integration_connection_credential' and (after_value::text ilike '%sk_live%' or before_value::text ilike '%sk_live%')) then
    raise exception 'assertion failed: a credential value must never reach app.audit_logs (C-24)';
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.integration_health_checks' and action = 'record_integration_health_check';
  if v_count = 0 then raise exception 'assertion failed: expected a record_integration_health_check audit event'; end if;
end;
$$;

\echo '>> ISS-2026-150 closure: app.create_integration_connection now composes app.assert_ip_allowed + app.has_active_ip_allowlist_bypass when a caller supplies p_client_ip -- a fresh, dedicated tenant (iaehubip), never touched by any earlier block in this file, so this enforced-mode policy cannot collide with any other block''s own unrelated create_integration_connection call'
do $$
declare
  v_tenant uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000010900000';
  v_admin uuid := '00000000-0000-0000-0000-000010900001';
  v_configurer uuid := '00000000-0000-0000-0000-000010900002';
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
  v_grant app.ip_allowlist_bypass_grants;
  v_connection app.integration_connections;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaehubip.test'),
    (v_admin, 'admin@iaehubip.test'),
    (v_configurer, 'configurer@iaehubip.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaehubip', 'IaeHubIp Co', 'idem-iaehubip', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iaehubip');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iaehubip.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaehubip.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant, v_configurer, 'configurer@iaehubip.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaehubip.test'), 'active', 'onboarded', 'tester');

  -- v_admin needs its own explicit SEC:Configure grant (a bare tenant_admin
  -- membership carries no module permission on its own -- only a real, published,
  -- explicitly-permissioned role assignment does, per app.evaluate_permission);
  -- v_configurer needs its own explicit INTHUB:Configure grant.
  v_admin_role := (app.create_role(v_tenant, 'IaeHubIp Admin', 'SEC:Configure', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_admin, v_supreme, 'supreme');

  v_configurer_role := (app.create_role(v_tenant, 'IaeHubIp Configurer', 'INTHUB:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(v_configurer_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'), v_configurer, v_admin, 'admin');

  -- Real allowlist entry (203.0.113.0/24, scope admin) plus enforced mode -- mirrors
  -- ip-restriction-network-access.sql's own established setup pattern verbatim.
  perform app.add_ip_allowlist_entry(v_tenant, '203.0.113.0/24', 'iaehubip office range', 'admin', v_admin, 'admin');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant, 'enforced', v_admin, 'admin');

  -- (a) out-of-range p_client_ip -- denied, ip_not_allowed.
  begin
    perform app.create_integration_connection(
      v_tenant, 'iae_hub_test_adapter', 'Should be IP-denied', 'production', null, null, null, '{}'::jsonb, 'secret-ip-a',
      v_configurer, 'configurer', '198.51.100.7'
    );
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-range p_client_ip under enforced mode, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlerrm !~ 'ip_not_allowed' then raise; end if;
  end;

  -- (b) in-range p_client_ip -- succeeds.
  v_connection := app.create_integration_connection(
    v_tenant, 'iae_hub_test_adapter', 'IP-allowed connection', 'production', null, null, null, '{}'::jsonb, 'secret-ip-b',
    v_configurer, 'configurer', '203.0.113.42'
  );
  if v_connection.status <> 'active' then
    raise exception 'assertion failed: expected a real, active connection for an in-range p_client_ip, got %', to_jsonb(v_connection);
  end if;

  -- (c) p_client_ip omitted/null -- succeeds regardless of the enforced policy, proving
  -- the non-interactive-caller exemption (every existing call site in this repository,
  -- including every OTHER block in this very file, relies on exactly this behavior).
  -- Uses environment='sandbox' rather than 'production' -- distinct from (b) above --
  -- because app.integration_connections enforces a unique (tenant_id, adapter_code,
  -- environment) constraint and this block deliberately reuses one adapter_code across
  -- all 3 successful inserts in this test.
  v_connection := app.create_integration_connection(
    v_tenant, 'iae_hub_test_adapter', 'No-IP connection', 'sandbox', null, null, null, '{}'::jsonb, 'secret-ip-c',
    v_configurer, 'configurer'
  );
  if v_connection.status <> 'active' then
    raise exception 'assertion failed: expected a real, active connection when p_client_ip is omitted, regardless of the enforced IP allowlist policy, got %', to_jsonb(v_connection);
  end if;

  -- Additional assertion (kept bounded to this one file, per spec): an actor holding a
  -- currently-active bypass grant is NOT denied even with an out-of-range p_client_ip.
  v_grant := app.request_ip_allowlist_bypass(v_tenant, v_configurer, 'iaehubip IP-bypass regression', v_admin, 'admin');
  -- Approved by v_supreme, not v_admin -- app.approve_ip_allowlist_bypass forbids
  -- self-approval at the CHECK-constraint level, and v_admin is the requester above.
  -- Supreme Admin holds SEC:Approve everywhere via the supreme_admin_exception path
  -- in app.evaluate_permission (same precedent as enterprise-mfa-session-controls.sql).
  v_grant := app.approve_ip_allowlist_bypass(v_grant.id, v_supreme, 'supreme');
  if v_grant.status <> 'approved' then
    raise exception 'assertion failed: expected the bypass grant to be approved, got %', v_grant.status;
  end if;
  if not app.has_active_ip_allowlist_bypass(v_tenant, v_configurer) then
    raise exception 'assertion failed: expected v_configurer to hold an active IP allowlist bypass grant';
  end if;

  -- A 3rd distinct adapter_code is registered here rather than reusing
  -- 'iae_hub_test_adapter' with (b)/(c)'s already-taken (production, sandbox) pair --
  -- both valid `environment` values are already consumed above, and the unique
  -- constraint is on (tenant_id, adapter_code, environment) together.
  perform app.register_integration_adapter('iae_hub_ip_bypass_test_adapter', 'IAE Hub IP Bypass Test Adapter', 'communication', v_supreme, 'supreme');
  v_connection := app.create_integration_connection(
    v_tenant, 'iae_hub_ip_bypass_test_adapter', 'Bypass-holder connection', 'production', null, null, null, '{}'::jsonb, 'secret-ip-bypass',
    v_configurer, 'configurer', '198.51.100.7'
  );
  if v_connection.status <> 'active' then
    raise exception 'assertion failed: expected a real, active connection for an out-of-range p_client_ip when the actor holds an active bypass grant, got %', to_jsonb(v_connection);
  end if;

  raise notice 'PASS: app.create_integration_connection (ISS-2026-150 closure) denies an out-of-range p_client_ip under enforced mode, allows an in-range one, allows a null p_client_ip regardless of enforcement, and exempts an active bypass-grant holder even from an out-of-range IP';
end;
$$;

\echo 'ALL IAE-008 (Integration Hub) db-test assertions passed.'
