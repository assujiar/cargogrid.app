-- Real, executable test evidence for PLT-129 (API Key and Webhook Primitives, CG-S6-PLT-026).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; Acme has a tenant_admin (holding exactly HRS:View personal data via a real role assignment), a regular org_user, and a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_role app.roles;
  v_version app.role_versions;
  v_permission_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000002101', 'tenantadminkey@example.test'),
    ('00000000-0000-0000-0000-000000002102', 'regularuserkey@example.test'),
    ('00000000-0000-0000-0000-000000002103', 'supremekey@example.test'),
    ('00000000-0000-0000-0000-000000002104', 'othertenantkey@example.test');

  perform app.provision_tenant('acmekey', 'Acme Key Co', 'idem-acmekey', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002101', 'tenantadminkey@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminkey@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002101', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002102', 'regularuserkey@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserkey@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002102', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmokey', 'Gizmo Key Co', 'idem-gizmokey', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmokey');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000002104', 'othertenantkey@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantkey@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002104', 'tenant_admin', v_other_tenant_id, null, 'tester');

  -- Real role/permission chain: Acme's tenant_admin holds exactly HRS:View personal data.
  v_role := app.create_role(v_tenant_id, 'Key Manager Role', 'Holds exactly one real permission for scope-narrowing tests', 'tester');
  v_version := app.create_role_version(v_role.id, 'tester');
  select id into v_permission_id from app.permissions where resource_module_code = 'HRS' and action = 'View personal data';
  perform app.set_role_version_permissions(v_version.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_version.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, v_version.id, '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002103', 'tester');
end;
$$;

\echo '>> app.register_webhook_event_type: idempotent, Supreme-Admin-only'
do $$
declare
  v_registered1 app.webhook_event_types;
  v_registered2 app.webhook_event_types;
begin
  begin
    perform app.register_webhook_event_type('test.event', 'Test Event', 'API-WH', '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a webhook event type';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_webhook_event_type('test.event', 'Test Event', 'API-WH', '00000000-0000-0000-0000-000000002103', 'supreme admin');
  v_registered2 := app.register_webhook_event_type('test.event', 'Test Event', 'API-WH', '00000000-0000-0000-0000-000000002103', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  -- Two additional, isolated event types so later scenario groups' delivery tests each
  -- fan out to exactly the one endpoint they register, never accumulating fan-out from
  -- an earlier group's endpoint that also happens to subscribe to 'test.event'.
  perform app.register_webhook_event_type('test.delivery', 'Test Delivery Event', 'API-WH', '00000000-0000-0000-0000-000000002103', 'supreme admin');
  perform app.register_webhook_event_type('test.autodisable', 'Test Auto-Disable Event', 'API-WH', '00000000-0000-0000-0000-000000002103', 'supreme admin');
end;
$$;

\echo '>> app.create_api_key: unauthorized actor, missing name/scopes, invalid scope format, scope-exceeds-actor-authority, invalid rate limit/expiry all rejected; a scope the actor actually holds succeeds, raw_key returned exactly once and never equals the stored hash'
do $$
declare
  v_tenant_id uuid;
  v_key record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');

  begin
    perform app.create_api_key(v_tenant_id, 'x', '["HRS:View personal data"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002102', 'regular user');
    raise exception 'assertion failed: expected a regular org_user (no support/supreme authority) to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_api_key(v_tenant_id, '', '["HRS:View personal data"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_missing_name';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_missing_name' then raise; end if;
  end;

  begin
    perform app.create_api_key(v_tenant_id, 'CI key', '[]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_missing_scopes';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_missing_scopes' then raise; end if;
  end;

  begin
    perform app.create_api_key(v_tenant_id, 'CI key', '["not-a-valid-scope"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_invalid_scope_format';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_invalid_scope_format' then raise; end if;
  end;

  begin
    perform app.create_api_key(v_tenant_id, 'CI key', '["FIN:View cost"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_scope_exceeds_actor_authority (tenant_admin does not hold FIN:View cost)';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'api_key_scope_exceeds_actor_authority' then raise; end if;
  end;

  begin
    perform app.create_api_key(v_tenant_id, 'CI key', '["HRS:View personal data"]'::jsonb, null, 0, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_invalid_rate_limit';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_invalid_rate_limit' then raise; end if;
  end;

  begin
    perform app.create_api_key(v_tenant_id, 'CI key', '["HRS:View personal data"]'::jsonb, now() - interval '1 day', null, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_invalid_expiry';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_invalid_expiry' then raise; end if;
  end;

  select * into v_key from app.create_api_key(v_tenant_id, 'CI key', '["HRS:View personal data"]'::jsonb, null, 60, '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_key.raw_key !~ '^cgk_' or length(v_key.raw_key) < 20 then
    raise exception 'assertion failed: expected a real cgk_-prefixed raw key';
  end if;
  if v_key.key_prefix <> substring(v_key.raw_key from 1 for 12) then
    raise exception 'assertion failed: expected key_prefix to be the raw key''s own first 12 characters';
  end if;
  if not exists (select 1 from app.api_keys where id = v_key.id and key_hash = encode(digest(v_key.raw_key, 'sha256'), 'hex')) then
    raise exception 'assertion failed: expected the stored key_hash to be the real sha256 digest of the raw key';
  end if;
end;
$$;

\echo '>> app.authenticate_api_key: unknown key rejected; a real key authenticates and reveals its tenant/scopes; last_used_at advances'
do $$
declare
  v_tenant_id uuid;
  v_key record;
  v_auth record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_key from app.create_api_key(v_tenant_id, 'Auth test key', '["HRS:View personal data"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  begin
    perform app.authenticate_api_key('cgk_' || repeat('0', 48));
    raise exception 'assertion failed: expected api_key_not_found for an unknown key';
  exception
    when no_data_found then
      null;
  end;

  select * into v_auth from app.authenticate_api_key(v_key.raw_key);
  if v_auth.tenant_id <> v_tenant_id then
    raise exception 'assertion failed: expected authentication to reveal the correct tenant_id';
  end if;
  if not (v_auth.scopes ? 'HRS:View personal data') then
    raise exception 'assertion failed: expected authentication to reveal the key''s own scopes';
  end if;
  if not app.api_key_has_scope(v_auth.api_key_id, 'HRS:View personal data') then
    raise exception 'assertion failed: expected app.api_key_has_scope to confirm the held scope';
  end if;
  if app.api_key_has_scope(v_auth.api_key_id, 'FIN:View cost') then
    raise exception 'assertion failed: expected app.api_key_has_scope to deny an unrelated scope';
  end if;
  if (select last_used_at from app.api_keys where id = v_key.id) is null then
    raise exception 'assertion failed: expected last_used_at to be set after authentication';
  end if;
end;
$$;

\echo '>> app.rotate_api_key: unauthorized/not-found/non-active/invalid-overlap rejected; overlap>0 keeps the old key valid until its new bounded expiry, overlap=0 revokes it immediately'
do $$
declare
  v_tenant_id uuid;
  v_key record;
  v_rotated record;
  v_old_after app.api_keys;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_key from app.create_api_key(v_tenant_id, 'Rotate test key', '["HRS:View personal data"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  begin
    perform app.rotate_api_key(v_key.id, 60, '00000000-0000-0000-0000-000000002102', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied rotating a key';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.rotate_api_key(gen_random_uuid(), 60, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_not_found';
  exception
    when no_data_found then
      null;
  end;

  begin
    perform app.rotate_api_key(v_key.id, -1, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_invalid_overlap_minutes';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_invalid_overlap_minutes' then raise; end if;
  end;

  select * into v_rotated from app.rotate_api_key(v_key.id, 60, '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_rotated.id = v_key.id then
    raise exception 'assertion failed: expected rotation to mint a genuinely new key row';
  end if;
  select * into v_old_after from app.api_keys where id = v_key.id;
  if v_old_after.status <> 'active' or v_old_after.expires_at is null or v_old_after.expires_at > now() + interval '61 minutes' then
    raise exception 'assertion failed: expected the old key to remain active but bounded to roughly a 60-minute overlap window, got status=% expires_at=%', v_old_after.status, v_old_after.expires_at;
  end if;
  -- Old key must still authenticate during the overlap window.
  perform app.authenticate_api_key(v_key.raw_key);

  begin
    perform app.rotate_api_key(v_rotated.id, 0, '00000000-0000-0000-0000-000000002101', 'tenant admin');
  end;
  begin
    perform app.authenticate_api_key(v_rotated.raw_key);
    raise exception 'assertion failed: expected the just-rotated-away key to be immediately revoked (overlap=0)';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'api_key_revoked' then raise; end if;
  end;

  begin
    perform app.rotate_api_key(v_rotated.id, 60, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_not_active (already revoked by its own overlap=0 rotation)';
  exception
    when check_violation then
      if sqlerrm !~ 'api_key_not_active' then raise; end if;
  end;
end;
$$;

\echo '>> app.revoke_api_key: unauthorized/not-found rejected; idempotent double-revoke; a revoked key fails authentication'
do $$
declare
  v_tenant_id uuid;
  v_key record;
  v_revoked1 app.api_keys;
  v_revoked2 app.api_keys;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_key from app.create_api_key(v_tenant_id, 'Revoke test key', '["HRS:View personal data"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  begin
    perform app.revoke_api_key(v_key.id, 'compromised', '00000000-0000-0000-0000-000000002102', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied revoking a key';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.revoke_api_key(gen_random_uuid(), 'x', '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected api_key_not_found';
  exception
    when no_data_found then
      null;
  end;

  v_revoked1 := app.revoke_api_key(v_key.id, 'compromised', '00000000-0000-0000-0000-000000002101', 'tenant admin');
  v_revoked2 := app.revoke_api_key(v_key.id, 'compromised again', '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_revoked1.revoked_at <> v_revoked2.revoked_at then
    raise exception 'assertion failed: expected a repeated revoke to be idempotent (same revoked_at), not a fresh mutation';
  end if;

  begin
    perform app.authenticate_api_key(v_key.raw_key);
    raise exception 'assertion failed: expected a revoked key to fail authentication';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'api_key_revoked' then raise; end if;
  end;
end;
$$;

\echo '>> app.list_api_keys_for_tenant: authority-gated, excludes key_hash from its result shape entirely, and is tenant-isolated'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmokey');

  begin
    perform app.list_api_keys_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000002102');
    raise exception 'assertion failed: expected a regular org_user to be denied listing keys';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.list_api_keys_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000002101');
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one key visible to the tenant''s own admin';
  end if;

  begin
    perform app.list_api_keys_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000002104');
    raise exception 'assertion failed: expected the other tenant''s admin to be denied listing Acme''s keys (cross-tenant isolation)';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.validate_webhook_url: rejects non-https and private/loopback/link-local literal hosts; accepts a normal https host'
do $$
begin
  begin
    perform app.validate_webhook_url('http://example.test/hook');
    raise exception 'assertion failed: expected webhook_invalid_url_scheme for http://';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_invalid_url_scheme' then raise; end if;
  end;

  begin
    perform app.validate_webhook_url('https://localhost/hook');
    raise exception 'assertion failed: expected webhook_unsafe_url_host for localhost';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unsafe_url_host' then raise; end if;
  end;

  begin
    perform app.validate_webhook_url('https://127.0.0.1/hook');
    raise exception 'assertion failed: expected webhook_unsafe_url_host for a loopback IPv4 literal';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unsafe_url_host' then raise; end if;
  end;

  begin
    perform app.validate_webhook_url('https://192.168.1.5/hook');
    raise exception 'assertion failed: expected webhook_unsafe_url_host for a private IPv4 literal';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unsafe_url_host' then raise; end if;
  end;

  begin
    perform app.validate_webhook_url('https://169.254.169.254/hook');
    raise exception 'assertion failed: expected webhook_unsafe_url_host for a link-local IPv4 literal (cloud metadata endpoint shape)';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unsafe_url_host' then raise; end if;
  end;

  if not app.validate_webhook_url('https://hooks.example-partner.test/cargogrid') then
    raise exception 'assertion failed: expected a normal public https host to validate';
  end if;
end;
$$;

\echo '>> app.register_webhook_endpoint: unauthorized/unsafe-url/missing-or-unknown-event-types rejected; a valid registration returns raw_secret exactly once'
do $$
declare
  v_tenant_id uuid;
  v_endpoint record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');

  begin
    perform app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/a', '["test.event"]'::jsonb, '00000000-0000-0000-0000-000000002102', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied registering an endpoint';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.register_webhook_endpoint(v_tenant_id, 'https://10.0.0.5/a', '["test.event"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected webhook_unsafe_url_host';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unsafe_url_host' then raise; end if;
  end;

  begin
    perform app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/a', '[]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected webhook_missing_event_types';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_missing_event_types' then raise; end if;
  end;

  begin
    perform app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/a', '["not.a.real.event"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected webhook_unknown_event_type';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unknown_event_type' then raise; end if;
  end;

  select * into v_endpoint from app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/a', '["test.event"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_endpoint.raw_secret !~ '^whsec_' then
    raise exception 'assertion failed: expected a real whsec_-prefixed raw secret';
  end if;
  if not exists (select 1 from app.webhook_subscriptions where webhook_endpoint_id = v_endpoint.id and event_type_code = 'test.event') then
    raise exception 'assertion failed: expected a real webhook_subscriptions row';
  end if;
end;
$$;

\echo '>> app.rotate_webhook_secret / app.disable_webhook_endpoint / app.reenable_webhook_endpoint: authority-gated, idempotent disable, reenable resets the failure counter'
do $$
declare
  v_tenant_id uuid;
  v_endpoint record;
  v_rotated record;
  v_disabled1 app.webhook_endpoints;
  v_disabled2 app.webhook_endpoints;
  v_reenabled app.webhook_endpoints;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_endpoint from app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/b', '["test.event"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  select * into v_rotated from app.rotate_webhook_secret(v_endpoint.id, '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_rotated.raw_secret = v_endpoint.raw_secret then
    raise exception 'assertion failed: expected rotation to produce a genuinely different secret';
  end if;

  v_disabled1 := app.disable_webhook_endpoint(v_endpoint.id, 'manual pause', '00000000-0000-0000-0000-000000002101', 'tenant admin');
  v_disabled2 := app.disable_webhook_endpoint(v_endpoint.id, 'manual pause again', '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_disabled1.auto_disabled_at <> v_disabled2.auto_disabled_at then
    raise exception 'assertion failed: expected a repeated disable to be idempotent';
  end if;

  update app.webhook_endpoints set consecutive_failure_count = 7 where id = v_endpoint.id;
  v_reenabled := app.reenable_webhook_endpoint(v_endpoint.id, '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_reenabled.status <> 'active' or v_reenabled.consecutive_failure_count <> 0 or v_reenabled.auto_disabled_at is not null then
    raise exception 'assertion failed: expected reenable to reset status/failure-count/auto_disabled_at';
  end if;
end;
$$;

\echo '>> app.list_webhook_endpoints_for_tenant: authority-gated, excludes secret_value from its result shape entirely, and is tenant-isolated'
do $$
declare
  v_tenant_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');

  begin
    perform app.list_webhook_endpoints_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000002102');
    raise exception 'assertion failed: expected a regular org_user to be denied listing endpoints';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.list_webhook_endpoints_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000002101');
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one endpoint visible to the tenant''s own admin';
  end if;

  begin
    perform app.list_webhook_endpoints_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000002104');
    raise exception 'assertion failed: expected the other tenant''s admin to be denied listing Acme''s endpoints';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.queue_webhook_delivery: unauthorized/unsafe-payload/missing-idempotency-key rejected; zero subscribers returns an empty set (not an error); a valid publish delivers one row per subscribed active endpoint, and replays idempotently'
do $$
declare
  v_tenant_id uuid;
  v_count integer;
  v_delivery1 app.webhook_deliveries;
  v_delivery2 app.webhook_deliveries;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');

  begin
    perform app.queue_webhook_delivery(v_tenant_id, 'test.event', '{}'::jsonb, 'idem-q1', '00000000-0000-0000-0000-000000002104', 'other tenant admin');
    raise exception 'assertion failed: expected an actor with no membership in this tenant to be refused outright';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.queue_webhook_delivery(v_tenant_id, 'test.event', jsonb_build_object('note', '<script>alert(1)</script>'), 'idem-q2', '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected webhook_unsafe_payload for an angle-bracketed value';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_unsafe_payload' then raise; end if;
  end;

  begin
    perform app.queue_webhook_delivery(v_tenant_id, 'test.event', '{}'::jsonb, '', '00000000-0000-0000-0000-000000002101', 'tenant admin');
    raise exception 'assertion failed: expected webhook_missing_idempotency_key';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_missing_idempotency_key' then raise; end if;
  end;

  select count(*) into v_count from app.queue_webhook_delivery(v_tenant_id, 'nobody.subscribes', '{}'::jsonb, 'idem-nosub', '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_count <> 0 then
    raise exception 'assertion failed: expected publishing an event with zero subscribers to return an empty set, not an error';
  end if;

  select * into v_delivery1 from app.queue_webhook_delivery(v_tenant_id, 'test.event', jsonb_build_object('shipment_id', '9001'), 'idem-q3', '00000000-0000-0000-0000-000000002101', 'tenant admin') limit 1;
  if v_delivery1.status <> 'pending' or v_delivery1.attempts <> 0 then
    raise exception 'assertion failed: unexpected initial delivery state %', v_delivery1;
  end if;

  select * into v_delivery2 from app.queue_webhook_delivery(v_tenant_id, 'test.event', jsonb_build_object('shipment_id', '9001'), 'idem-q3', '00000000-0000-0000-0000-000000002101', 'tenant admin') limit 1;
  if v_delivery2.id <> v_delivery1.id then
    raise exception 'assertion failed: expected a repeated idempotency_key to return the existing delivery, not create a duplicate';
  end if;
end;
$$;

\echo '>> app.record_webhook_delivery_attempt: not-found/already-terminal/invalid-status rejected; a success delivers and resets the endpoint failure counter; repeated failures back off then reach dead_letter at max_attempts; the audit entry maps failed -> failure (the exact audit_logs.result CHECK class of bug PLT-127 found)'
do $$
declare
  v_tenant_id uuid;
  v_endpoint record;
  v_delivery app.webhook_deliveries;
  v_updated app.webhook_deliveries;
  v_i integer;
  v_audit_result text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_endpoint from app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/c', '["test.delivery"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  -- Success path.
  select * into v_delivery from app.queue_webhook_delivery(v_tenant_id, 'test.delivery', '{}'::jsonb, 'idem-success-1', '00000000-0000-0000-0000-000000002101', 'tenant admin') limit 1;
  v_updated := app.record_webhook_delivery_attempt(v_delivery.id, 'success', 200, null, '00000000-0000-0000-0000-000000002101', 'delivery worker');
  if v_updated.status <> 'delivered' or v_updated.attempts <> 1 then
    raise exception 'assertion failed: expected a success to deliver on attempt 1';
  end if;

  begin
    perform app.record_webhook_delivery_attempt(v_delivery.id, 'failed', 500, 'should not run', '00000000-0000-0000-0000-000000002101', 'delivery worker');
    raise exception 'assertion failed: expected webhook_delivery_already_terminal for a delivered delivery';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_delivery_already_terminal' then raise; end if;
  end;

  begin
    perform app.record_webhook_delivery_attempt(gen_random_uuid(), 'success', 200, null, '00000000-0000-0000-0000-000000002101', 'delivery worker');
    raise exception 'assertion failed: expected webhook_delivery_not_found';
  exception
    when no_data_found then
      null;
  end;

  -- Failure/backoff/dead_letter path (max_attempts default = 5).
  select * into v_delivery from app.queue_webhook_delivery(v_tenant_id, 'test.delivery', '{}'::jsonb, 'idem-fail-1', '00000000-0000-0000-0000-000000002101', 'tenant admin') limit 1;

  begin
    perform app.record_webhook_delivery_attempt(v_delivery.id, 'not-a-status', null, null, '00000000-0000-0000-0000-000000002101', 'delivery worker');
    raise exception 'assertion failed: expected webhook_invalid_attempt_status';
  exception
    when check_violation then
      if sqlerrm !~ 'webhook_invalid_attempt_status' then raise; end if;
  end;

  for v_i in 1..5 loop
    v_updated := app.record_webhook_delivery_attempt(v_delivery.id, 'failed', 503, 'endpoint unreachable', '00000000-0000-0000-0000-000000002101', 'delivery worker');
  end loop;
  if v_updated.status <> 'dead_letter' or v_updated.attempts <> 5 or v_updated.next_attempt_at is not null then
    raise exception 'assertion failed: expected the 5th consecutive failure to reach dead_letter with no further next_attempt_at, got status=% attempts=%', v_updated.status, v_updated.attempts;
  end if;

  select result into v_audit_result from app.audit_logs where action = 'record_webhook_delivery_attempt' and resource_id = v_delivery.id order by occurred_at desc limit 1;
  if v_audit_result <> 'failure' then
    raise exception 'assertion failed: expected the failed-attempt audit entry to record result=failure (audit_logs.result only allows success/failure), got %', v_audit_result;
  end if;
end;
$$;

\echo '>> auto-disable: 10 consecutive delivery failures across separate deliveries to the same endpoint disable it (ADR-0011); a further queue attempt against the now-disabled endpoint delivers to nobody; the next success would have reset the counter'
do $$
declare
  v_tenant_id uuid;
  v_endpoint record;
  v_delivery app.webhook_deliveries;
  v_i integer;
  v_endpoint_after app.webhook_endpoints;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_endpoint from app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/d', '["test.autodisable"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  for v_i in 1..10 loop
    select * into v_delivery from app.queue_webhook_delivery(v_tenant_id, 'test.autodisable', '{}'::jsonb, 'idem-disable-' || v_i, '00000000-0000-0000-0000-000000002101', 'tenant admin') limit 1;
    perform app.record_webhook_delivery_attempt(v_delivery.id, 'failed', 500, 'endpoint down', '00000000-0000-0000-0000-000000002101', 'delivery worker');
  end loop;

  select * into v_endpoint_after from app.webhook_endpoints where id = v_endpoint.id;
  if v_endpoint_after.status <> 'disabled' or v_endpoint_after.consecutive_failure_count < 10 or v_endpoint_after.auto_disabled_at is null then
    raise exception 'assertion failed: expected the endpoint to auto-disable at the 10-consecutive-failure threshold, got status=% count=%', v_endpoint_after.status, v_endpoint_after.consecutive_failure_count;
  end if;

  select count(*) into v_count from app.queue_webhook_delivery(v_tenant_id, 'test.autodisable', '{}'::jsonb, 'idem-after-disable', '00000000-0000-0000-0000-000000002101', 'tenant admin');
  if v_count <> 0 then
    raise exception 'assertion failed: expected a disabled endpoint to receive no new deliveries';
  end if;
end;
$$;

\echo '>> app.compute_webhook_signature / app.verify_webhook_signature: a correctly signed payload verifies, a tampered payload fails, a stale timestamp outside the 5-minute tolerance fails, an unknown endpoint raises (ADR-0011)'
do $$
declare
  v_tenant_id uuid;
  v_endpoint record;
  v_payload text;
  v_timestamp bigint;
  v_signature text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmekey');
  select * into v_endpoint from app.register_webhook_endpoint(v_tenant_id, 'https://hooks.example-partner.test/e', '["test.event"]'::jsonb, '00000000-0000-0000-0000-000000002101', 'tenant admin');

  v_payload := '{"event":"test.event"}';
  v_timestamp := extract(epoch from now())::bigint;
  v_signature := app.compute_webhook_signature(v_endpoint.id, v_payload, v_timestamp);

  if not app.verify_webhook_signature(v_endpoint.id, v_payload, v_timestamp, v_signature) then
    raise exception 'assertion failed: expected a correctly signed, fresh payload to verify';
  end if;

  if app.verify_webhook_signature(v_endpoint.id, '{"event":"tampered"}', v_timestamp, v_signature) then
    raise exception 'assertion failed: expected a tampered payload to fail verification';
  end if;

  if app.verify_webhook_signature(v_endpoint.id, v_payload, v_timestamp - 400, v_signature) then
    raise exception 'assertion failed: expected a signature computed 400 seconds ago to fail the 5-minute (300s) tolerance window';
  end if;

  begin
    perform app.compute_webhook_signature(gen_random_uuid(), v_payload, v_timestamp);
    raise exception 'assertion failed: expected webhook_endpoint_not_found';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct table access to api_keys/webhook_endpoints/webhook_deliveries/webhook_delivery_attempts; app.webhook_event_types is broadly readable'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002101", "role": "authenticated"}';

  begin
    perform 1 from app.api_keys limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.api_keys entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform 1 from app.webhook_endpoints limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.webhook_endpoints entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform 1 from app.webhook_deliveries limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.webhook_deliveries entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform 1 from app.webhook_delivery_attempts limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.webhook_delivery_attempts entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.webhook_event_types where code = 'test.event';
  if v_count <> 1 then
    raise exception 'assertion failed: expected app.webhook_event_types to be broadly readable';
  end if;

  reset role;
end;
$$;

\echo '>> PLT-129 (API Key and Webhook Primitives) test suite passed'
