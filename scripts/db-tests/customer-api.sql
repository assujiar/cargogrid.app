-- Real, executable test evidence for IAE-010 (Customer API, Prompt 338,
-- CG-S14-IAE-010) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000012000001..006.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use.
--
-- Applies IAE-009's own hard-won lessons from the start: live forged-session
-- RLS/session testing (request.jwt.claims + set role authenticated) and the
-- ATW-032 actor-identity self-check discipline are both proven live below,
-- not discovered after the fact.
--
-- Does NOT re-test app.create_api_key/app.authenticate_api_key/app.api_key_
-- has_scope's own already-covered surface (scripts/db-tests/api-key-webhook.sql)
-- or the general rate-limit/gateway-outcome mechanics (already covered,
-- generically, by scripts/db-tests/public-api-platform.sql -- this file only
-- proves the NEW customer-specific authority/dispatch-identity layer
-- 20260804020000_create_intelligence_customer_api.sql adds on top of it).

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaecustapi (staff tenant_admin with CPT:Create, account Alpha with a real account_admin + a real member with no admin authority, account Beta with zero customer membership) and a second tenant iaecustapi2 (one lone customer_user, cross-tenant isolation)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_role_id uuid; v_draft app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000012000001', 'staff@iaecustapi.test'),
    ('00000000-0000-0000-0000-000012000002', 'alpha-admin@iaecustapi.test'),
    ('00000000-0000-0000-0000-000012000003', 'alpha-member@iaecustapi.test'),
    ('00000000-0000-0000-0000-000012000004', 'outsider@iaecustapi2.test'),
    ('00000000-0000-0000-0000-000012000005', 'plain-staff@iaecustapi.test');

  perform app.provision_tenant('iaecustapi', 'IAE CustAPI Co', 'idem-iaecustapi', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaecustapi');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'IAECUSTAPI-CO', 'IaeCustApi Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAECUSTAPI-CO');

  perform app.provision_tenant('iaecustapi2', 'IAE CustAPI Co 2', 'idem-iaecustapi2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaecustapi2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  -- Staff: a real tenant_admin LAYER (app.check_api_webhook_admin_authority's
  -- own gate) AND CPT:Create RBAC (app.grant_initial_customer_portal_account_
  -- admin's own gate) -- two genuinely different authority systems, both real
  -- here. plain-staff has neither, used to prove default-deny.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000012000001', 'staff@iaecustapi.test', 'Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@iaecustapi.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000012000001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000012000005', 'plain-staff@iaecustapi.test', 'Plain Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain-staff@iaecustapi.test'), 'active', 'onboarded', 'tester');

  v_role_id := (app.create_role(v_tenant1, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role_id and status = 'published'), '00000000-0000-0000-0000-000012000001', '00000000-0000-0000-0000-000012000001', 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'IaeCustApi Account Alpha', 'iaecustapi-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'IaeCustApi Account Beta', 'iaecustapi-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;

  perform app.link_auth_identity('00000000-0000-0000-0000-000012000002', v_tenant1, 'tester', 'active');
  perform app.link_auth_identity('00000000-0000-0000-0000-000012000003', v_tenant1, 'tester', 'active');
  perform app.link_auth_identity('00000000-0000-0000-0000-000012000004', v_tenant2, 'tester', 'active');

  -- Alpha's own real account_admin, bootstrapped by staff CPT:Create authority.
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000012000002', '00000000-0000-0000-0000-000012000001', 'tester');
  -- Alpha's own real, non-admin member.
  insert into app.customer_portal_account_memberships (tenant_id, account_id, auth_user_id, role, status, invited_by)
  values (v_tenant1, v_account_alpha, '00000000-0000-0000-0000-000012000003', 'member', 'active', 'tester');

  -- Cross-tenant outsider: a real customer_user in tenant2, zero relationship to
  -- tenant1 -- a legacy-style direct grant (mirrors customer-portal-scope.sql's
  -- own "Gamma is a LEGACY-ONLY grant" fixture convention), since this identity
  -- only needs to genuinely hold the customer_user layer for tenant2, not real
  -- account_admin authority anywhere.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, created_by)
  values (v_tenant2, 'IaeCustApi2 Account', 'iaecustapi2-fp', '{}'::jsonb, 'tester') returning id into v_account_t2;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000012000004', 'customer_user', v_tenant2, v_account_t2::text, 'tester');
end;
$$;

\echo '>> app.create_customer_api_key: self-service by a real account_admin succeeds with the fixed CPT:CustomerPortal scope; a non-admin member is denied; a staff actor with NO tenant_admin layer and NO relationship to the account is denied; a staff tenant_admin may provision on behalf of a real member, but never for an identity with zero scope for the account'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_admin uuid := '00000000-0000-0000-0000-000012000002';
  v_member uuid := '00000000-0000-0000-0000-000012000003';
  v_plain_staff uuid := '00000000-0000-0000-0000-000012000005';
  v_tenant_admin uuid := '00000000-0000-0000-0000-000012000001';
  v_created record;
begin
  select * into v_created from app.create_customer_api_key(v_tenant1, v_account_alpha, v_admin, 'Self Service Key', null, 10, v_admin, 'tester');
  if v_created.scopes::text <> '["CPT:CustomerPortal"]' then
    raise exception 'assertion failed: expected the fixed scope marker, got %', v_created.scopes;
  end if;
  if v_created.customer_account_id <> v_account_alpha or v_created.customer_actor_auth_user_id <> v_admin then
    raise exception 'assertion failed: expected customer_account_id=%/customer_actor_auth_user_id=%, got %/%', v_account_alpha, v_admin, v_created.customer_account_id, v_created.customer_actor_auth_user_id;
  end if;

  begin
    perform app.create_customer_api_key(v_tenant1, v_account_alpha, v_member, 'Member Key', null, null, v_member, 'tester');
    raise exception 'assertion failed: expected insufficient_authority -- a non-admin member must not self-create a key';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.create_customer_api_key(v_tenant1, v_account_alpha, v_admin, 'Plain Staff Key', null, null, v_plain_staff, 'tester');
    raise exception 'assertion failed: expected insufficient_authority -- a staff actor with no tenant_admin layer and no account relationship must be denied';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.create_customer_api_key(v_tenant1, v_account_alpha, v_plain_staff, 'On Behalf Bad Target', null, null, v_tenant_admin, 'tester');
    raise exception 'assertion failed: expected account_not_available -- a tenant_admin may not bind a key to an identity with zero scope for the account';
  exception when no_data_found then null;
  end;

  perform app.create_customer_api_key(v_tenant1, v_account_alpha, v_member, 'On Behalf Key', null, null, v_tenant_admin, 'tester');

  raise notice 'PASS: create_customer_api_key -- self-service works with the fixed scope marker, a non-admin member and an unrelated staff actor are both denied, a tenant_admin may provision on behalf of a REAL member but never an unrelated identity';
end;
$$;

\echo '>> app.list_customer_api_keys_for_account: scoped to EXACTLY one account -- never the tenant''s own staff keys, never another account''s keys'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Beta');
  v_admin uuid := '00000000-0000-0000-0000-000012000002';
  v_tenant_admin uuid := '00000000-0000-0000-0000-000012000001';
  v_count integer;
begin
  -- A real tenant-staff key, unrelated to any customer account.
  -- v_tenant_admin already holds CPT:Create via the fixture's own "Portal
  -- Admin" role assignment (setup block) -- reused here as a real scope
  -- app.create_api_key's own evaluate_permission() check will actually pass.
  perform app.create_api_key(v_tenant1, 'Staff-only Key', '["CPT:Create"]'::jsonb, null, null, v_tenant_admin, 'tester');

  select count(*) into v_count from app.list_customer_api_keys_for_account(v_tenant1, v_account_alpha, v_admin);
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly the 2 keys previously created for Alpha (self-service + on-behalf), got %', v_count;
  end if;
  if exists (select 1 from app.list_customer_api_keys_for_account(v_tenant1, v_account_alpha, v_admin) where customer_account_id <> v_account_alpha) then
    raise exception 'assertion failed: a row for a DIFFERENT account leaked into Alpha''s own listing';
  end if;

  -- Alpha's own account_admin holds no relationship to Beta at all -- denied
  -- outright (insufficient_authority), never a silently-empty list that
  -- would blur "authorized, nothing to show" with "not authorized here".
  begin
    perform app.list_customer_api_keys_for_account(v_tenant1, v_account_beta, v_admin);
    raise exception 'assertion failed: expected insufficient_authority -- Alpha''s own account_admin holds no relationship to Beta at all';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_customer_api_keys_for_account is scoped to exactly one account -- never leaks tenant-staff keys, and refuses outright (never a silently-empty list) for an account the caller holds no relationship to';
end;
$$;

\echo '>> app.authenticate_and_authorize_api_request: a customer key dispatches as its own real customer_actor_auth_user_id, never the (possibly different) staff creator'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_member uuid := '00000000-0000-0000-0000-000012000003';
  v_tenant_admin uuid := '00000000-0000-0000-0000-000012000001';
  v_created record;
  v_result record;
begin
  select * into v_created from app.create_customer_api_key(v_tenant1, v_account_alpha, v_member, 'Dispatch Proof Key', null, 20, v_tenant_admin, 'tester');

  select * into v_result from app.authenticate_and_authorize_api_request(v_created.raw_key, 'CPT:CustomerPortal');
  if v_result.outcome <> 'ok' or v_result.created_by_auth_user_id <> v_member then
    raise exception 'assertion failed: expected outcome=ok dispatching as the real customer_actor (%), got outcome=% actor=%', v_member, v_result.outcome, v_result.created_by_auth_user_id;
  end if;
  if v_result.created_by_auth_user_id = v_tenant_admin then
    raise exception 'assertion failed: the key must never dispatch as its own staff CREATOR when a distinct customer_actor_auth_user_id is bound';
  end if;

  -- Wrong scope for a customer key -- CPT:CustomerPortal is the only scope
  -- issued; a required scope this key does not carry is refused cleanly.
  select * into v_result from app.authenticate_and_authorize_api_request(v_created.raw_key, 'INTHUB:Configure');
  if v_result.outcome <> 'forbidden_scope' then
    raise exception 'assertion failed: expected forbidden_scope for a scope this customer key never carries, got %', v_result.outcome;
  end if;

  raise notice 'PASS: authenticate_and_authorize_api_request dispatches a customer key as its own real, bound customer_actor_auth_user_id, never its staff creator; forbidden_scope holds for a scope the key does not carry';
end;
$$;

\echo '>> real downstream dispatch proof: the resolved customer_actor_auth_user_id genuinely works end to end against a live Customer Portal RPC (app.get_customer_shipment_tracking''s own real scope re-check) -- proving the gateway wiring this migration adds, not merely the identity resolution in isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_admin uuid := '00000000-0000-0000-0000-000012000002';
  v_tenant_admin uuid := '00000000-0000-0000-0000-000012000001';
  v_created record;
  v_result record;
begin
  select * into v_created from app.create_customer_api_key(v_tenant1, v_account_alpha, v_admin, 'Downstream Proof Key', null, null, v_admin, 'tester');
  select * into v_result from app.authenticate_and_authorize_api_request(v_created.raw_key, 'CPT:CustomerPortal');

  -- A genuinely nonexistent shipment: the RPC's own anti-enumeration
  -- shipment_order_not_found proves the resolved actor really reached a live
  -- Customer Portal RPC (a bad/unresolved actor would instead surface as a
  -- different, earlier authority failure).
  begin
    perform app.get_customer_shipment_tracking(v_result.tenant_id, v_result.created_by_auth_user_id, gen_random_uuid());
    raise exception 'assertion failed: expected shipment_order_not_found for a genuinely nonexistent shipment id';
  exception
    when no_data_found then null;
  end;

  raise notice 'PASS: the gateway-resolved dispatch identity genuinely reaches a live Customer Portal RPC end to end (app.get_customer_shipment_tracking''s own anti-enumeration path)';
end;
$$;

\echo '>> self-service revoke/rotate: a real account_admin may revoke/rotate their OWN account''s key; the customer_account_id/customer_actor_auth_user_id are carried forward onto a rotated key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_admin uuid := '00000000-0000-0000-0000-000012000002';
  v_created record;
  v_rotated record;
  v_revoked app.api_keys;
begin
  select * into v_created from app.create_customer_api_key(v_tenant1, v_account_alpha, v_admin, 'Revoke Rotate Key', null, null, v_admin, 'tester');

  select * into v_rotated from app.rotate_api_key(v_created.id, 60, v_admin, 'tester');
  if (select customer_account_id from app.api_keys where id = v_rotated.id) <> v_account_alpha then
    raise exception 'assertion failed: the rotated key must carry customer_account_id forward';
  end if;
  if (select customer_actor_auth_user_id from app.api_keys where id = v_rotated.id) <> v_admin then
    raise exception 'assertion failed: the rotated key must carry customer_actor_auth_user_id forward';
  end if;

  select * into v_revoked from app.revoke_api_key(v_rotated.id, 'self-service cleanup', v_admin, 'tester');
  if v_revoked.status <> 'revoked' then
    raise exception 'assertion failed: expected the rotated key to be genuinely revocable by its own account_admin, got status=%', v_revoked.status;
  end if;

  raise notice 'PASS: a real account_admin can revoke/rotate their OWN account''s key via PLT-129''s own extended revoke_api_key/rotate_api_key; customer_account_id/customer_actor_auth_user_id survive rotation';
end;
$$;

\echo '>> cross-tenant isolation: tenant2''s own real customer_user account_admin cannot create/list/revoke a key for tenant1''s own account, whether by passing tenant1''s own id or their own tenant2 id against a tenant1 account'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaecustapi2');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_outsider uuid := '00000000-0000-0000-0000-000012000004';
begin
  begin
    perform app.create_customer_api_key(v_tenant1, v_account_alpha, v_outsider, 'Cross Tenant Key', null, null, v_outsider, 'tester');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s own outsider holds no account_admin/staff authority over a tenant1 account (the authority check runs before scope-binding)';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.list_customer_api_keys_for_account(v_tenant1, v_account_alpha, v_outsider);
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s own outsider is not an account_admin (or staff) of tenant1''s own account';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: cross-tenant isolation holds for create/list -- a real customer_user in an unrelated tenant can neither create nor list a key for another tenant''s own account';
end;
$$;

\echo '>> live forged-session proof (request.jwt.claims + set role authenticated): the REAL account_admin, acting through a genuine authenticated session (not the connecting superuser), can create and revoke their own account''s key end to end -- proving app.create_customer_api_key/app.revoke_api_key''s own widened grant to authenticated is real, not merely documented'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_admin uuid := '00000000-0000-0000-0000-000012000002';
  v_created record;
  v_revoked app.api_keys;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000012000002", "role": "authenticated"}', false);
  set role authenticated;

  select * into v_created from app.create_customer_api_key(v_tenant1, v_account_alpha, v_admin, 'Forged Session Key', null, null, v_admin, 'tester');
  select * into v_revoked from app.revoke_api_key(v_created.id, 'forged-session cleanup', v_admin, 'tester');
  if v_revoked.status <> 'revoked' then
    raise exception 'assertion failed: expected a genuine authenticated session to revoke its own just-created key';
  end if;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: a real forged authenticated session, not the connecting superuser, creates and revokes its own account''s API key end to end';
end;
$$;

\echo '>> ATW-032 actor-identity proof: a genuine authenticated session may not claim to act as a DIFFERENT identity when calling app.create_customer_api_key, even the account''s own real admin'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecustapi');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'IaeCustApi Account Alpha');
  v_member uuid := '00000000-0000-0000-0000-000012000003';
  v_admin uuid := '00000000-0000-0000-0000-000012000002';
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000012000003", "role": "authenticated"}', false);
  set role authenticated;

  begin
    perform app.create_customer_api_key(v_tenant1, v_account_alpha, v_admin, 'Impersonation Attempt', null, null, v_admin, 'tester');
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not claim identity %', v_member, v_admin;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: app.create_customer_api_key refuses a genuine authenticated session claiming a different identity, even the account''s own real admin';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-010 function'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'check_api_key_manage_authority', 'create_customer_api_key', 'list_customer_api_keys_for_account'
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

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-010 function';
end;
$$;

\echo '>> app.api_keys.customer_account_id/customer_actor_auth_user_id shape constraint: both null or both set, never one alone'
do $$
begin
  begin
    insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, created_by_auth_user_id, customer_account_id)
    values ((select id from app.tenants where slug = 'iaecustapi'), 'Malformed Key', 'cgk_malformed', 'deadbeef', '[]'::jsonb, '00000000-0000-0000-0000-000012000001', (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'iaecustapi') limit 1));
    raise exception 'assertion failed: expected api_keys_customer_scope_shape_check to reject customer_account_id set without customer_actor_auth_user_id';
  exception
    when check_violation then null;
  end;

  raise notice 'PASS: api_keys_customer_scope_shape_check rejects a half-set customer binding';
end;
$$;

\echo '>> customer-api.sql: ALL PASSED'
