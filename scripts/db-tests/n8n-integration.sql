-- Real, executable test evidence for IAE-013 (n8n Integration, Prompt 341) --
-- run via `pnpm run db:test` against a real, disposable Postgres database. Scoped
-- to this checkpoint's own additive migration (supabase/migrations/
-- 20260804050000_create_intelligence_n8n_integration.sql). Fresh, distinctive
-- tenant fixture (iaen8n/iaen8n2), fixture id range
-- 00000000-0000-0000-0000-000015xxxxxx.
--
-- n8n itself calls the SAME /api/v1 REST surface (scripts/db-tests/public-api-
-- platform.sql) and receives events through the SAME webhook delivery mechanism
-- (scripts/db-tests/webhook-management.sql) every other consumer already uses --
-- this file tests only the governance/linking layer this checkpoint adds
-- (the allowlist, the connector registration composing app.create_api_key, and
-- the live-joined connector list), never re-testing either already-covered
-- primitive's own mechanics.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaen8n (tenant_admin with a real role holding OPS:View/TKT:View/TKT:Create/INTHUB:View -- exactly the seeded allowlist -- plus a plain PRC:View-only staff member with none of those scopes) and a second tenant iaen8n2 (its own tenant_admin, for cross-tenant isolation). A Supreme Admin for allowlist registration. One real webhook endpoint in tenant1.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000015000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000015000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000015000003';
  v_supreme uuid := '00000000-0000-0000-0000-000015000999';
  v_admin_role uuid;
  v_staff_role uuid;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaen8n.test'),
    (v_staff1, 'staff@iaen8n.test'),
    (v_admin2, 'admin@iaen8n2.test'),
    (v_supreme, 'supreme@iaen8n.test');

  perform app.provision_tenant('iaen8n', 'IaeN8n Co', 'idem-iaen8n', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaen8n');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaen8n2', 'IaeN8n Co 2', 'idem-iaen8n2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaen8n2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaen8n.test', 'IaeN8n Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaen8n.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');
  v_admin_role := (app.create_role(v_tenant1, 'IaeN8n Admin Role', 'exactly the seeded n8n allowlist, plus API/webhook admin', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin_role, 'tester')).id, array(select id from app.permissions where code in ('OPS:View', 'TKT:View', 'TKT:Create', 'INTHUB:View')), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_admin1, v_admin1, 'admin');

  perform app.invite_user(v_tenant1, v_staff1, 'staff@iaen8n.test', 'IaeN8n Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@iaen8n.test'), 'active', 'onboarded', 'tester');
  v_staff_role := (app.create_role(v_tenant1, 'IaeN8n Viewer', 'PRC:View only -- none of the n8n allowlisted scopes, no admin authority', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(select id from app.permissions where code = 'PRC:View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), v_staff1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaen8n2.test', 'IaeN8n2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaen8n2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  perform app.register_webhook_endpoint(v_tenant1, 'https://n8n.iaen8n.test/webhook/abc', '["webhook.test"]'::jsonb, v_admin1, 'admin');
end $$;

\echo '>> app.register_n8n_allowlisted_action / app.list_n8n_action_allowlist: Supreme-only, idempotent by scope, rejects a scope that is not a real app.permissions code; the seeded allowlist is globally readable'
do $$
declare
  v_admin1 uuid := '00000000-0000-0000-0000-000015000001';
  v_supreme uuid := '00000000-0000-0000-0000-000015000999';
  v_row1 app.n8n_action_allowlist;
  v_row2 app.n8n_action_allowlist;
  v_count integer;
begin
  begin
    perform app.register_n8n_allowlisted_action('OPS:Assign', 'not for n8n', v_admin1, 'admin');
    raise exception 'assertion failed: expected insufficient_authority for a non-Supreme actor';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.register_n8n_allowlisted_action('FAKE:Nonexistent', 'not a real permission', v_supreme, 'supreme');
    raise exception 'assertion failed: expected n8n_scope_not_a_real_permission for a fictional scope';
  exception when check_violation then
    if sqlerrm !~ 'n8n_scope_not_a_real_permission' then raise; end if;
  end;

  v_row1 := app.register_n8n_allowlisted_action('OPS:Assign', 'a real, deliberately narrow test addition', v_supreme, 'supreme');
  v_row2 := app.register_n8n_allowlisted_action('OPS:Assign', 'a real, deliberately narrow test addition', v_supreme, 'supreme');
  if v_row1.created_at <> v_row2.created_at then
    raise exception 'assertion failed: expected a repeated registration to return the SAME row, not create a duplicate';
  end if;

  select count(*) into v_count from app.list_n8n_action_allowlist();
  if v_count < 6 then
    raise exception 'assertion failed: expected at least the 5 seeded rows plus this block''s own addition, got %', v_count;
  end if;

  raise notice 'PASS: register_n8n_allowlisted_action is Supreme-only, idempotent by scope, and rejects a fictional permission code; list_n8n_action_allowlist is globally readable and reflects real registrations live';
end;
$$;

\echo '>> app.create_n8n_connector: BOTH the n8n allowlist AND the creating actor''s own current RBAC must permit every requested scope; an optional linked webhook endpoint must belong to the same tenant; a non-admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaen8n');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaen8n2');
  v_admin1 uuid := '00000000-0000-0000-0000-000015000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000015000002';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1);
  v_created record;
begin
  -- Allowlisted AND held -- succeeds.
  select * into v_created from app.create_n8n_connector(v_tenant1, 'Shipment Notifier', '["OPS:View", "TKT:Create"]'::jsonb, v_endpoint_a, 60, v_admin1, 'admin');
  if v_created.scopes <> '["OPS:View", "TKT:Create"]'::jsonb or v_created.webhook_endpoint_id <> v_endpoint_a or v_created.raw_key is null then
    raise exception 'assertion failed: unexpected shape from create_n8n_connector: %', to_jsonb(v_created);
  end if;

  -- Allowlisted (PRC:View is seeded) but NOT held by admin1 -- his role holds only
  -- OPS:View/TKT:View/TKT:Create/INTHUB:View -- denied by create_api_key's own RBAC re-check.
  begin
    perform app.create_n8n_connector(v_tenant1, 'Overreaching Connector', '["PRC:View"]'::jsonb, null, null, v_admin1, 'admin');
    raise exception 'assertion failed: expected api_key_scope_exceeds_actor_authority -- PRC:View is allowlisted but not held by admin1';
  exception when insufficient_privilege then null;
  end;

  -- Held by the actor but NOT allowlisted -- denied by the allowlist check.
  begin
    perform app.create_n8n_connector(v_tenant1, 'Unlisted Scope Connector', '["INTHUB:Configure"]'::jsonb, null, null, v_admin1, 'admin');
    raise exception 'assertion failed: expected n8n_scope_not_allowlisted -- INTHUB:Configure is not on the seeded allowlist';
  exception when check_violation then
    if sqlerrm !~ 'n8n_scope_not_allowlisted' then raise; end if;
  end;

  -- A webhook endpoint from a DIFFERENT tenant cannot be linked.
  declare
    v_endpoint_t2 record;
  begin
    select * into v_endpoint_t2 from app.register_webhook_endpoint(v_tenant2, 'https://n8n.iaen8n2.test/webhook/xyz', '["webhook.test"]'::jsonb, '00000000-0000-0000-0000-000015000003', 'admin2');
    begin
      perform app.create_n8n_connector(v_tenant1, 'Cross Tenant Endpoint', '["OPS:View"]'::jsonb, v_endpoint_t2.id, null, v_admin1, 'admin');
      raise exception 'assertion failed: expected webhook_endpoint_not_found for a DIFFERENT tenant''s own endpoint';
    exception when no_data_found then null;
    end;
  end;

  -- Tier C Batch 3 fix: a DISABLED endpoint (same tenant) cannot be linked
  -- either -- it would simply never receive deliveries (app.queue_webhook_
  -- delivery''s own fan-out only selects status=active endpoints).
  declare
    v_disabled_endpoint record;
  begin
    select * into v_disabled_endpoint from app.register_webhook_endpoint(v_tenant1, 'https://n8n.iaen8n.test/webhook/disabled', '["webhook.test"]'::jsonb, v_admin1, 'admin');
    perform app.disable_webhook_endpoint(v_disabled_endpoint.id, 'test disable', v_admin1, 'admin');
    begin
      perform app.create_n8n_connector(v_tenant1, 'Disabled Endpoint Link', '["OPS:View"]'::jsonb, v_disabled_endpoint.id, null, v_admin1, 'admin');
      raise exception 'assertion failed: expected webhook_endpoint_not_active for a disabled endpoint link';
    exception when check_violation then
      if sqlerrm !~ 'webhook_endpoint_not_active' then raise; end if;
    end;
  end;

  begin
    perform app.create_n8n_connector(v_tenant1, 'Denied Attempt', '["OPS:View"]'::jsonb, null, null, v_staff1, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for a non-admin staff member';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: create_n8n_connector requires BOTH allowlist membership AND the creating actor''s own current RBAC for every scope; a cross-tenant webhook endpoint link, a disabled-endpoint link (Tier C Batch 3 fix), and a non-admin are all denied';
end;
$$;

\echo '>> app.revoke_n8n_connector: delegates entirely to app.revoke_api_key -- the connector''s own linking row is left in place as a historical record'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaen8n');
  v_admin1 uuid := '00000000-0000-0000-0000-000015000001';
  v_connector_id uuid;
  v_revoked app.api_keys;
  v_still_linked integer;
begin
  select connector_id into v_connector_id from app.list_n8n_connectors_for_tenant(v_tenant1, v_admin1) where name = 'Shipment Notifier';

  v_revoked := app.revoke_n8n_connector(v_connector_id, 'self-cleanup', v_admin1, 'admin');
  if v_revoked.status <> 'revoked' then
    raise exception 'assertion failed: expected the underlying api_key to be revoked, got status=%', v_revoked.status;
  end if;

  select count(*) into v_still_linked from app.n8n_connectors where id = v_connector_id;
  if v_still_linked <> 1 then
    raise exception 'assertion failed: expected the connector''s own linking row to remain in place as a historical record';
  end if;

  raise notice 'PASS: revoke_n8n_connector delegates to app.revoke_api_key -- the connector''s own linking row survives, matching how a revoked app.api_keys row is itself never deleted';
end;
$$;

\echo '>> app.rotate_n8n_connector (Tier C Batch 3 fix): composes app.rotate_api_key AND re-points app.n8n_connectors.api_key_id at the newly-minted key row -- the generic rotate must never be used for a connector, it would silently orphan the linkage'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaen8n');
  v_admin1 uuid := '00000000-0000-0000-0000-000015000001';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 limit 1);
  v_created record;
  v_rotated record;
  v_listed record;
begin
  select * into v_created from app.create_n8n_connector(v_tenant1, 'Rotate Proof Connector', '["OPS:View"]'::jsonb, v_endpoint_a, null, v_admin1, 'admin');

  v_rotated := app.rotate_n8n_connector(v_created.connector_id, 0, v_admin1, 'admin');
  if v_rotated.api_key_id = v_created.api_key_id or v_rotated.raw_key is null then
    raise exception 'assertion failed: expected rotate_n8n_connector to mint a genuinely new key row, got %', to_jsonb(v_rotated);
  end if;

  -- The REGRESSION this proves: without the fix, app.n8n_connectors.
  -- api_key_id would still point at v_created.api_key_id -- the OLD,
  -- immediately-revoked (overlap=0) key -- while the real new key sat
  -- orphaned and unreachable through this console.
  select connector_id, api_key_id, status into v_listed from app.list_n8n_connectors_for_tenant(v_tenant1, v_admin1) where connector_id = v_created.connector_id;
  if v_listed.api_key_id <> v_rotated.api_key_id then
    raise exception 'assertion failed: expected the connector''s own linkage to follow to the new key %, still points at %', v_rotated.api_key_id, v_listed.api_key_id;
  end if;
  if v_listed.status <> 'active' then
    raise exception 'assertion failed: expected the connector''s own live-joined status to reflect the NEW (active) key, got %', v_listed.status;
  end if;

  raise notice 'PASS: rotate_n8n_connector keeps app.n8n_connectors.api_key_id pointed at whichever key is genuinely live -- no orphaned successor key, no stale console status';
end;
$$;

\echo '>> app.list_n8n_connectors_for_tenant: scoped to this tenant, live-joined with the linked app.api_keys/app.webhook_endpoints rows; a non-admin and a cross-tenant admin are both denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaen8n');
  v_staff1 uuid := '00000000-0000-0000-0000-000015000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000015000003';
  v_row record;
  v_found boolean := false;
begin
  for v_row in select * from app.list_n8n_connectors_for_tenant(v_tenant1, '00000000-0000-0000-0000-000015000001') loop
    if v_row.name = 'Shipment Notifier' then
      v_found := true;
      if v_row.webhook_endpoint_url is null or v_row.status <> 'revoked' then
        raise exception 'assertion failed: expected the live-joined endpoint url and the real (revoked) status, got %', to_jsonb(v_row);
      end if;
    end if;
  end loop;
  if not v_found then
    raise exception 'assertion failed: expected to find the Shipment Notifier connector';
  end if;

  begin
    perform app.list_n8n_connectors_for_tenant(v_tenant1, v_staff1);
    raise exception 'assertion failed: expected insufficient_authority for a non-admin staff member';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.list_n8n_connectors_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for tenant2''s own admin against tenant1''s own connectors';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_n8n_connectors_for_tenant is scoped to this tenant, live-joined with the linked key/endpoint state; a non-admin and a cross-tenant admin are both denied';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-013 function'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'register_n8n_allowlisted_action', 'list_n8n_action_allowlist', 'create_n8n_connector',
    'revoke_n8n_connector', 'rotate_n8n_connector', 'list_n8n_connectors_for_tenant'
  ];
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-013 function';
end;
$$;

\echo '>> live forged-session proof (request.jwt.claims + set role authenticated): the REAL tenant_admin, acting through a genuine authenticated session (not the connecting superuser), can list n8n connectors end to end; the same session cannot claim a different identity (ATW-032)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaen8n');
  v_admin1 uuid := '00000000-0000-0000-0000-000015000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000015000002';
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000015000001", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_count from app.list_n8n_connectors_for_tenant(v_tenant1, v_admin1);
  if v_count = 0 then
    raise exception 'assertion failed: expected a genuine authenticated session to list at least one real connector';
  end if;

  begin
    perform app.list_n8n_connectors_for_tenant(v_tenant1, v_staff1);
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not claim identity %', v_admin1, v_staff1;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: a real forged authenticated session, not the connecting superuser, lists real n8n connectors end to end; the same session cannot claim a different identity';
end;
$$;

\echo '>> n8n-integration.sql: ALL PASSED'
